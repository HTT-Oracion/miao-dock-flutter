import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_qjs/flutter_qjs.dart';

import '../../../../../core/storage/shell_prefs.dart';

import '../../domain/online_error.dart';
import '../../domain/online_models.dart';
import '../../domain/online_source.dart';
import '../../domain/source_engine.dart';
import '../../domain/source_manifest.dart';
import 'source_document_registry.dart';
import '../source_dto.dart';
import '../source_http.dart';

/// 从落盘源包读取 JS。测试可替换为内存实现。
abstract interface class SourceCodeLoader {
  Future<({String js, String baseUrl})> load(OnlineSource source);
}

class StoredSourceCodeLoader implements SourceCodeLoader {
  const StoredSourceCodeLoader();

  @override
  Future<({String js, String baseUrl})> load(OnlineSource source) async {
    final root = onlineStateDirectory();
    if (root == null) {
      throw const OnlineException(OnlineErrorCode.specUnsupported, 'source directory unavailable');
    }
    final file = File('${root.path}/sources/${source.id}/${source.manifest.sourceFile}');
    try {
      final raw = await file.readAsString();
      return (js: raw, baseUrl: source.manifest.baseUrl);
    } catch (e) {
      throw OnlineException(OnlineErrorCode.specUnsupported, '$e');
    }
  }
}

/// QuickJS 单例运行时 + 同步 DOM 句柄表 + 异步 HTTP 宿主桥。
///
/// 一个源一个对象，但共用一个 runtime；源之间用 `globalThis.__sources[id]`
/// 隔离。调用超时或崩溃后关闭 runtime，下次调用自动重建。
class QuickJsSourceEngine implements SourceEngine {
  QuickJsSourceEngine({
    SourceHttp? http,
    SourceCodeLoader? codeLoader,
    this._prelude,
    this.memoryLimit = 64 * 1024 * 1024,
    this.stackSize = 8 * 1024 * 1024,
    this.callTimeout = const Duration(seconds: 20),
  }) : _http = http ?? SourceHttp(),
       _codeLoader = codeLoader ?? const StoredSourceCodeLoader();

  final SourceHttp _http;
  final SourceCodeLoader _codeLoader;
  final String? _prelude;
  final int memoryLimit;
  final int stackSize;
  final Duration callTimeout;

  FlutterQjs? _engine;
  final SourceDocumentRegistry _documents = SourceDocumentRegistry();
  final Map<String, OnlineSource> _sources = {};
  final Map<String, Future<void>> _loading = {};
  final Map<String, SourceDto> _dtos = {};
  final Map<String, Map<String, Object?>> _sourceData = {};

  bool _disposed = false;
  Future<void> _callQueue = Future<void>.value();

  @override
  Future<void> ensureLoaded(OnlineSource source) {
    if (_sources.containsKey(source.id)) return Future<void>.value();
    final existing = _loading[source.id];
    if (existing != null) return existing;
    final future = _load(source);
    _loading[source.id] = future;
    return future.whenComplete(() => _loading.remove(source.id));
  }

  Future<void> _load(OnlineSource source) async {
    if (_disposed) throw const OnlineException(OnlineErrorCode.crashed, 'engine disposed');
    final code = await _codeLoader.load(source);
    await _ensureRuntime();
    final manifest = source.manifest;
    final id = jsonEncode(source.id);
    final entry = manifest.entryClass;
    final legacy = manifest.runtime == SourceRuntime.comicSource;
    final adapter = legacy ? 'globalThis.__makeLegacyAdapter(__entry)' : '__entry';
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(entry)) {
      throw const OnlineException(OnlineErrorCode.specUnsupported, 'invalid entry class');
    }
    final wrapped =
        '''
(function () {
  try {
    ${code.js}
    globalThis.__sources = globalThis.__sources || {};
    const __entry = new $entry();
    globalThis.__sources[$id] = $adapter;
    const __bound = globalThis.__sources[$id];
    return {
      ok: true,
      key: String(__bound.key || ''),
      name: String(__bound.name || ''),
      version: String(__bound.version || ''),
    };
  } catch (e) {
    return {
      ok: false,
      code: String((e && e.code) || 'SOURCE_CRASHED'),
      message: String((e && e.message) || e),
    };
  }
})()
''';
    final loaded = await _evaluateMap(wrapped, timeout: callTimeout);
    if (loaded['ok'] != true) {
      throw _errorFrom(loaded);
    }
    _sources[source.id] = source;
    _dtos[source.id] = SourceDto(code.baseUrl, requestHeaders: source.manifest.headers);
    if (source.capabilities.contains('init')) {
      try {
        await _callRaw(source, 'init', const {});
      } catch (e) {
        // init 只做 Cookie 预热，失败不阻断浏览。
        debugPrint('online source init failed: $e');
      }
    }
  }

  Future<void> _ensureRuntime() async {
    if (_engine != null) return;
    final engine = FlutterQjs(memoryLimit: memoryLimit, stackSize: stackSize);
    try {
      engine.dispatch();
      final setGlobal = engine.evaluate('(key, value) => { globalThis[key] = value; }');
      if (setGlobal is! JSInvokable) throw StateError('sendMessage injection failed');
      setGlobal(['sendMessage', _onMessage]);
      setGlobal.free();
      final prelude = _prelude ?? await rootBundle.loadString('assets/online/init.js');
      engine.evaluate(prelude, name: '<online-prelude>');
      _engine = engine;
    } catch (e) {
      try {
        engine.close();
      } catch (_) {}
      throw OnlineException(OnlineErrorCode.crashed, 'engine init: $e');
    }
  }

  dynamic _onMessage(dynamic message) {
    if (message is! Map) return null;
    final map = Map<String, dynamic>.from(message);
    switch (map['method']) {
      case 'http':
        return _handleHttp(map);
      case 'html':
        return _documents.handle(map);
      case 'cookie':
        return _handleCookie(map);
      case 'delay':
        return Future<void>.delayed(Duration(milliseconds: (map['time'] as num?)?.toInt() ?? 0));
      case 'convert':
        return _convert(map);
      case 'log':
        debugPrint('online source [${map['level']}]: ${map['content']}');
        return null;
      case 'load_data':
        return _sourceData['${map['key']}']?['${map['data_key']}'];
      case 'save_data':
        (_sourceData['${map['key']}'] ??= {})['${map['data_key']}'] = map['data'];
        return null;
      case 'delete_data':
        _sourceData['${map['key']}']?.remove('${map['data_key']}');
        return null;
      case 'getPlatform':
        return defaultTargetPlatform.name.toLowerCase();
      case 'getLocale':
        return 'zh_CN';
      default:
        return null;
    }
  }

  Future<Map<String, Object?>> _handleHttp(Map<String, dynamic> message) async {
    final source = _sourceById('${message['sourceId'] ?? ''}');
    final active = source ?? (_sources.length == 1 ? _sources.values.first : null);
    if (active == null) {
      return {'error': 'source context missing', 'errorCode': 'SOURCE_CRASHED'};
    }
    final headers = <String, String>{};
    final rawHeaders = message['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        if (entry.key is String && entry.value is String) headers['${entry.key}'] = '${entry.value}';
      }
    }
    final extra = message['extra'];
    final response = await _http.request(
      method: '${message['http_method'] ?? 'GET'}',
      url: '${message['url'] ?? ''}',
      manifest: active.manifest,
      headers: headers,
      data: message['data'],
      bytes: message['bytes'] == true || (extra is Map && extra['bytes'] == true),
      timeoutMs: extra is Map ? (extra['timeoutMs'] as num?)?.toInt() : null,
    );
    return response.toMessage();
  }

  Object? _handleCookie(Map<String, dynamic> message) {
    switch (message['function']) {
      case 'set':
        final cookies = <Map<String, Object?>>[];
        final raw = message['cookies'];
        if (raw is List) {
          for (final cookie in raw) {
            if (cookie is Map) cookies.add(Map<String, Object?>.from(cookie));
          }
        }
        _http.setCookies('${message['url'] ?? ''}', cookies);
        return null;
      case 'get':
        return _http.getCookies('${message['url'] ?? ''}');
    }
    return null;
  }

  Object? _convert(Map<String, dynamic> message) {
    final type = '${message['type'] ?? ''}';
    final value = message['value'];
    final encode = message['isEncode'] == true;
    switch (type) {
      case 'utf8':
        if (encode) return Uint8List.fromList(utf8.encode('$value'));
        if (value is Uint8List) return utf8.decode(value, allowMalformed: true);
        if (value is List<int>) return utf8.decode(value, allowMalformed: true);
        return '$value';
      case 'base64':
        if (encode) return base64Encode(value is Uint8List ? value : utf8.encode('$value'));
        if (value is String) return base64Decode(value);
        return null;
      case 'md5':
        return Uint8List.fromList(md5.convert(_bytes(value)).bytes);
      case 'sha1':
        return Uint8List.fromList(sha1.convert(_bytes(value)).bytes);
      case 'sha256':
        return Uint8List.fromList(sha256.convert(_bytes(value)).bytes);
    }
    return null;
  }

  static List<int> _bytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return value;
    return utf8.encode('$value');
  }

  OnlineSource? _sourceById(String id) {
    for (final entry in _sources.entries) {
      if (entry.key == id) return entry.value;
    }
    return null;
  }

  Future<Map<String, Object?>> _evaluateMap(String expression, {required Duration timeout}) async {
    final dynamic result;
    try {
      result = _engine!.evaluate(expression);
    } catch (e) {
      throw OnlineException(OnlineErrorCode.crashed, '$e');
    }
    try {
      final resolved = result is Future ? await result.timeout(timeout) : result;
      if (resolved is Map) return Map<String, Object?>.from(resolved);
      throw const OnlineException(OnlineErrorCode.parse, 'source returned non-object');
    } on TimeoutException {
      _resetRuntime();
      throw const OnlineException(OnlineErrorCode.timeout, 'source call timeout');
    } on OnlineException {
      rethrow;
    } catch (e) {
      throw OnlineException(OnlineErrorCode.crashed, '$e');
    }
  }

  Future<Map<String, Object?>> _callRaw(OnlineSource source, String capability, Map<String, Object?> args) async {
    if (!_sources.containsKey(source.id)) await ensureLoaded(source);
    final previous = _callQueue;
    final completer = Completer<void>();
    _callQueue = completer.future;
    await previous;
    try {
      return await _callRawSerial(source, capability, args);
    } finally {
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<Map<String, Object?>> _callRawSerial(OnlineSource source, String capability, Map<String, Object?> args) async {
    if (_engine == null || !_sources.containsKey(source.id)) {
      throw const OnlineException(OnlineErrorCode.crashed, 'runtime reset');
    }
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(capability)) {
      throw const OnlineException(OnlineErrorCode.specUnsupported, 'invalid capability');
    }
    final id = jsonEncode(source.id);
    final argsJson = jsonEncode(args);
    final expression =
        '''
(async function () {
  try {
    const s = globalThis.__sources[$id];
    if (!s) throw sourceError('SOURCE_CRASHED', 'source not loaded');
    if (typeof s.$capability !== 'function') throw sourceError('SPEC_UNSUPPORTED', '$capability');
    globalThis.__activeSourceId = $id;
    const value = await s.$capability($argsJson);
    return { ok: true, value: value === undefined ? null : value };
  } catch (e) {
    return {
      ok: false,
      code: String((e && e.code) || 'SOURCE_CRASHED'),
      message: String((e && e.message) || e),
    };
  }
})()
''';
    final result = await _evaluateMap(expression, timeout: callTimeout);
    if (result['ok'] != true) throw _errorFrom(result);
    return {'value': result['value']};
  }

  Future<T> _call<T>(
    OnlineSource source,
    String capability,
    Map<String, Object?> args,
    T Function(Object? raw) parse,
  ) async {
    final result = await _callRaw(source, capability, args);
    return parse(result['value']);
  }

  OnlineException _errorFrom(Map<String, Object?> result) {
    final wire = '${result['code'] ?? 'SOURCE_CRASHED'}';
    final code = OnlineErrorCode.values.firstWhere(
      (item) => item.wireName == wire,
      orElse: () => OnlineErrorCode.crashed,
    );
    final message = '${result['message'] ?? ''}';
    debugPrint('online source error $wire: $message');
    return OnlineException(code, message);
  }

  void _resetRuntime() {
    final engine = _engine;
    _engine = null;
    _sources.clear();
    _dtos.clear();
    _documents.clear();
    if (engine != null) {
      try {
        engine.close();
        engine.port.close();
      } catch (_) {}
    }
  }

  @override
  Future<HomeFeed> explore(OnlineSource source, {required int page}) async {
    return _call(source, 'explore', {'page': page}, (raw) => _dto(source).homeFeed(raw));
  }

  @override
  Future<List<CategoryGroup>> categories(OnlineSource source) async {
    return _call(source, 'categories', const {}, (raw) => _dto(source).categories(raw));
  }

  @override
  Future<List<RankTab>> rankTabs(OnlineSource source) async {
    return _call(source, 'rankTabs', const {}, (raw) => _dto(source).rankTabs(raw));
  }

  @override
  Future<PagedComics> rank(OnlineSource source, {required String tabId, required int page}) async {
    return _call(source, 'rank', {'id': tabId, 'page': page}, (raw) => _dto(source).ranked(raw, page: page));
  }

  @override
  Future<PagedComics> category(OnlineSource source, {required String id, required int page}) async {
    return _call(source, 'category', {'id': id, 'page': page}, (raw) => _dto(source).paged(raw, page: page));
  }

  @override
  Future<PagedComics> search(OnlineSource source, {required String keyword, required int page}) async {
    return _call(source, 'search', {'keyword': keyword, 'page': page}, (raw) => _dto(source).paged(raw, page: page));
  }

  @override
  Future<OnlineComicDetail> loadComicInfo(OnlineSource source, {required String comicId}) async {
    return _call(source, 'loadComicInfo', {'id': comicId}, (raw) => _dto(source).detail(raw));
  }

  @override
  Future<List<ImageLoadingConfig>> loadComicPages(
    OnlineSource source, {
    required String comicId,
    required String chapterId,
  }) async {
    final urls = await _call(source, 'loadComicPages', {
      'id': comicId,
      'chapterId': chapterId,
    }, (raw) => _dto(source).pageUrls(raw));
    if (urls.isEmpty) return const [];
    ImageLoadingConfig config = const ImageLoadingConfig();
    if (source.capabilities.contains('getImageLoadingConfig')) {
      try {
        config = await _call(source, 'getImageLoadingConfig', {
          'url': urls.first,
          'comicId': comicId,
          'chapterId': chapterId,
        }, (raw) => _dto(source).imageConfig(raw));
      } catch (e) {
        debugPrint('online image config failed: $e');
      }
    }
    final headers = config.headers;
    return [for (final url in urls) ImageLoadingConfig(url: url, method: config.method, headers: headers)];
  }

  @override
  Future<ImageLoadingConfig> getImageLoadingConfig(
    OnlineSource source, {
    required String url,
    required String comicId,
    required String chapterId,
  }) async {
    if (!source.capabilities.contains('getImageLoadingConfig')) {
      return ImageLoadingConfig(url: url);
    }
    return _call(source, 'getImageLoadingConfig', {'url': url, 'comicId': comicId, 'chapterId': chapterId}, (raw) {
      final config = _dto(source).imageConfig(raw);
      return ImageLoadingConfig(url: config.url ?? url, method: config.method, headers: config.headers);
    });
  }

  SourceDto _dto(OnlineSource source) => _dtos[source.id] ?? SourceDto(source.manifest.baseUrl);

  @override
  Future<void> unload(String sourceId) async {
    _sources.remove(sourceId);
    _dtos.remove(sourceId);
    if (_engine != null) {
      try {
        _engine!.evaluate('delete globalThis.__sources[${jsonEncode(sourceId)}]');
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _resetRuntime();
  }
}
