import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show md5, sha1, sha256;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_qjs/flutter_qjs.dart';

import '../../../../../core/storage/shell_prefs.dart';
import '../../../domain/js_music_source.dart';
import '../../../domain/music_models.dart';
import '../../../domain/music_login_info.dart';
import '../../../domain/music_source_engine.dart';
import 'music_source_dto.dart';
import 'music_source_http.dart';

/// 从落盘源包读取 JS。测试可替换为内存实现。
abstract interface class MusicSourceCodeLoader {
  Future<String> load(JsMusicSource source);
}

class StoredMusicSourceCodeLoader implements MusicSourceCodeLoader {
  const StoredMusicSourceCodeLoader();

  @override
  Future<String> load(JsMusicSource source) async {
    final root = musicSourceStateDirectory();
    if (root == null) throw StateError('music source directory unavailable');
    final file = File('${root.path}/${source.id}/${source.manifest.sourceFile}');
    try {
      return await file.readAsString();
    } catch (e) {
      throw StateError('source file missing: $e');
    }
  }
}

/// QuickJS 音乐源引擎。
///
/// 宿主桥协议与漫画源一致（http / cookie / delay / convert / log / 数据存取），
/// 但能力组是音乐方法（searchSongs / charts / songUrl / lyrics / ...），prelude
/// 用 `assets/online/music_init.js`（`MusicSourceBase`）。音乐源是纯 JSON API，
/// 不需要 DOM 桥。
class QuickJsMusicSourceEngine implements MusicSourceEngine {
  QuickJsMusicSourceEngine({
    MusicSourceHttp? http,
    MusicSourceCodeLoader? codeLoader,
    this.memoryLimit = 64 * 1024 * 1024,
    this.stackSize = 8 * 1024 * 1024,
    this.callTimeout = const Duration(seconds: 15),
  }) : _http = http ?? MusicSourceHttp(),
       _codeLoader = codeLoader ?? const StoredMusicSourceCodeLoader();

  final MusicSourceHttp _http;
  final MusicSourceCodeLoader _codeLoader;
  final int memoryLimit;
  final int stackSize;
  final Duration callTimeout;

  FlutterQjs? _engine;
  final Map<String, JsMusicSource> _sources = {};
  final Map<String, Map<String, Object?>> _sourceData = {};
  final Map<String, String> _sessionCookies = {};
  bool _disposed = false;
  Future<void> _callQueue = Future<void>.value();

  @override
  Future<void> ensureLoaded(JsMusicSource source) {
    if (_sources.containsKey(source.id)) return Future<void>.value();
    return _load(source);
  }

  Future<void> _load(JsMusicSource source) async {
    if (_disposed) throw StateError('engine disposed');
    final js = await _codeLoader.load(source);
    await _ensureRuntime();
    final manifest = source.manifest;
    final entry = manifest.entryClass;
    if (RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(entry) == false) {
      throw StateError('invalid entry class');
    }
    final id = jsonEncode(source.id);
    final wrapped =
        '''
(function () {
  try {
    $js
    globalThis.__musicSources = globalThis.__musicSources || {};
    globalThis.__musicSources[$id] = new $entry();
    const s = globalThis.__musicSources[$id];
    return {
      ok: true,
      key: String(s.key || ''),
      name: String(s.name || ''),
      version: String(s.version || ''),
    };
  } catch (e) {
    return { ok: false, code: String((e && e.code) || 'SOURCE_CRASHED'), message: String((e && e.message) || e) };
  }
})()
''';
    final loaded = await _evaluateMap(wrapped);
    if (loaded['ok'] != true) throw MusicSourceException('${loaded['code']}', '${loaded['message']}');
    _sources[source.id] = source;
    if (source.capabilities.contains('init')) {
      try {
        await _callRaw(source, 'init', const {});
      } catch (e) {
        debugPrint('music source init failed: $e');
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
      final prelude = await rootBundle.loadString('assets/online/music_init.js');
      engine.evaluate(prelude, name: '<music-prelude>');
      _engine = engine;
    } catch (e) {
      try {
        engine.close();
      } catch (_) {}
      throw StateError('music engine init: $e');
    }
  }

  /// 宿主桥：与漫画源同名同义，源作者的迁移成本为零。
  dynamic _onMessage(dynamic message) {
    if (message is! Map) return null;
    final map = Map<String, dynamic>.from(message);
    switch (map['method']) {
      case 'http':
        return _handleHttp(map);
      case 'cookie':
        return _handleCookie(map);
      case 'delay':
        return Future<void>.delayed(Duration(milliseconds: (map['time'] as num?)?.toInt() ?? 0));
      case 'convert':
        return _convert(map);
      case 'log':
        debugPrint('music source [${map['level']}]: ${map['content']}');
        return null;
      case 'load_data':
        return _sourceData['${map['key']}']?['${map['data_key']}'];
      case 'save_data':
        (_sourceData['${map['key']}'] ??= {})['${map['data_key']}'] = map['data'];
        return null;
      case 'delete_data':
        _sourceData['${map['key']}']?.remove('${map['data_key']}');
        return null;
      case 'session':
        // 登录 Cookie 原串透传：酷狗等平台把票据当 URL 参数用（不是 Cookie 头），
        // Cookie 罐按域名隔离带不到网关域 —— 源自己解析后拼参数。
        return _sessionCookies['${map['sourceId'] ?? ''}'] ??
            (_sources.length == 1 ? _sessionCookies[_sources.keys.first] : null);
      case 'getPlatform':
        return defaultTargetPlatform.name.toLowerCase();
      default:
        return null;
    }
  }

  Future<Map<String, Object?>> _handleHttp(Map<String, dynamic> message) async {
    final source = _activeSource('${message['sourceId'] ?? ''}');
    if (source == null) {
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
    final wantBytes = extra is Map && extra['bytes'] == true;
    if (wantBytes) {
      // 二进制响应（咪咕混淆流）：base64 过桥，源侧解码后自行处理。
      final bytes = await _http.requestBytes(
        method: '${message['http_method'] ?? 'GET'}',
        url: '${message['url'] ?? ''}',
        source: source,
        headers: headers,
      );
      if (bytes.error != null) {
        return {'error': bytes.error, 'errorCode': bytes.errorCode, 'status': bytes.status};
      }
      return {
        'status': bytes.status,
        'body': '',
        'bodyBase64': base64Encode(bytes.body),
        'headers': <String, List<String>>{},
      };
    }
    final response = await _http.request(
      method: '${message['http_method'] ?? 'GET'}',
      url: '${message['url'] ?? ''}',
      source: source,
      headers: headers,
      data: message['data'],
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
    switch (type) {
      case 'utf8':
        if (message['isEncode'] == true) return utf8.encode('$value');
        if (value is List<int>) return utf8.decode(value, allowMalformed: true);
        return '$value';
      case 'base64':
        if (message['isEncode'] == true) return base64Encode(_bytes(value));
        if (value is String) return base64Decode(value);
        return null;
      case 'md5':
        return md5Hex(_bytes(value));
      case 'sha1':
        return sha1Hex(_bytes(value));
      case 'sha256':
        return sha256Hex(_bytes(value));
    }
    return null;
  }

  /// md5 / sha1 / sha256 hex —— 音乐签名算法（酷狗 / QQ）的基础件。
  /// 用 package:crypto 在宿主侧算好（QuickJS 里跑哈希既慢又不必要的复杂）。
  static String md5Hex(List<int> bytes) => md5.convert(bytes).toString();
  static String sha1Hex(List<int> bytes) => sha1.convert(bytes).toString();
  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  static List<int> _bytes(Object? value) {
    if (value is List<int>) return value;
    return utf8.encode('$value');
  }

  JsMusicSource? _activeSource(String hinted) {
    final byId = _sources[hinted];
    if (byId != null) return byId;
    if (_sources.length == 1) return _sources.values.first;
    return null;
  }

  Future<Map<String, Object?>> _evaluateMap(String expression) async {
    final dynamic result;
    try {
      result = _engine!.evaluate(expression);
    } catch (e) {
      _resetRuntime();
      throw MusicSourceException('SOURCE_CRASHED', '$e');
    }
    try {
      final resolved = result is Future ? await result.timeout(callTimeout) : result;
      if (resolved is Map) return Map<String, Object?>.from(resolved);
      throw const MusicSourceException('PARSE', 'source returned non-object');
    } on TimeoutException {
      _resetRuntime();
      throw const MusicSourceException('TIMEOUT', 'source call timeout');
    } on MusicSourceException {
      rethrow;
    } catch (e) {
      _resetRuntime();
      throw MusicSourceException('SOURCE_CRASHED', '$e');
    }
  }

  Future<Map<String, Object?>> _callRaw(JsMusicSource source, String capability, Map<String, Object?> args) async {
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

  Future<Map<String, Object?>> _callRawSerial(
    JsMusicSource source,
    String capability,
    Map<String, Object?> args,
  ) async {
    if (_engine == null || !_sources.containsKey(source.id)) {
      throw const MusicSourceException('SOURCE_CRASHED', 'runtime reset');
    }
    if (RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(capability) == false) {
      throw const MusicSourceException('SPEC_UNSUPPORTED', 'invalid capability');
    }
    final id = jsonEncode(source.id);
    final argsJson = jsonEncode(args);
    final expression =
        '''
(async function () {
  try {
    const s = globalThis.__musicSources[$id];
    if (!s) throw sourceError('SOURCE_CRASHED', 'source not loaded');
    if (typeof s.$capability !== 'function') throw sourceError('SPEC_UNSUPPORTED', '$capability');
    globalThis.__activeMusicSourceId = $id;
    const value = await s.$capability($argsJson);
    return { ok: true, value: value === undefined ? null : value };
  } catch (e) {
    return { ok: false, code: String((e && e.code) || 'SOURCE_CRASHED'), message: String((e && e.message) || e) };
  }
})()
''';
    final result = await _evaluateMap(expression);
    if (result['ok'] != true) {
      throw MusicSourceException('${result['code'] ?? 'SOURCE_CRASHED'}', '${result['message'] ?? ''}');
    }
    return {'value': result['value']};
  }

  Future<T> _call<T>(
    JsMusicSource source,
    String capability,
    Map<String, Object?> args,
    T Function(Object? raw) parse,
  ) async {
    try {
      final result = await _callRaw(source, capability, args);
      _succeed(source);
      return parse(result['value']);
    } on Object {
      _fail(source);
      rethrow;
    }
  }

  void _succeed(JsMusicSource source) {
    _sources[source.id] = source.withSuccess();
  }

  void _fail(JsMusicSource source) {
    _sources[source.id] = source.withFailure();
  }

  void _resetRuntime() {
    final engine = _engine;
    _engine = null;
    _sources.clear();
    _sourceData.clear();
    if (engine != null) {
      try {
        engine.close();
        engine.port.close();
      } catch (_) {}
    }
  }

  @override
  Future<MusicLoginInfo?> loginInfo(JsMusicSource source) async {
    if (source.capabilities.contains('loginInfo') == false) return null;
    final raw = await _call(source, 'loginInfo', const {}, (r) => r);
    if (raw is! Map) return null;
    return MusicLoginInfo(loggedIn: raw['loggedIn'] == true, nick: '${raw['nick'] ?? ''}');
  }

  @override
  Future<void> setSessionCookie(JsMusicSource source, String cookie) async {
    await ensureLoaded(source);
    _sessionCookies[source.id] = cookie;
    _http.setSessionCookie(source, cookie);
  }

  @override
  Future<List<MusicSong>> searchSongs(
    JsMusicSource source, {
    required String keyword,
    int limit = 30,
    int offset = 0,
  }) async {
    final raw = await _call(source, 'searchSongs', {'keyword': keyword, 'limit': limit, 'offset': offset}, (r) => r);
    return _dto(platformId: source.platformId).songs(raw);
  }

  @override
  Future<List<MusicPlaylist>> searchPlaylists(JsMusicSource source, {required String keyword, int limit = 12}) async {
    final raw = await _call(source, 'searchPlaylists', {'keyword': keyword, 'limit': limit}, (r) => r);
    return _dto(platformId: source.platformId).playlists(raw);
  }

  @override
  Future<List<MusicChart>> charts(JsMusicSource source) async {
    final raw = await _call(source, 'charts', const {}, (r) => r);
    return _dto(platformId: source.platformId).charts(raw);
  }

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> chartDetail(JsMusicSource source, {required String id}) async {
    final raw = await _call(source, 'chartDetail', {'id': id}, (r) => r);
    return _dto(platformId: source.platformId).detail(raw);
  }

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(
    JsMusicSource source, {
    required String id,
  }) async {
    final raw = await _call(source, 'playlistDetail', {'id': id}, (r) => r);
    return _dto(platformId: source.platformId).detail(raw);
  }

  @override
  Future<SongLyrics> lyrics(JsMusicSource source, {required MusicSong song}) async {
    final raw = await _call(source, 'lyrics', {'id': song.id, 'mediaId': song.mediaId ?? song.id}, (r) => r);
    return _dto(platformId: source.platformId).lyrics(raw);
  }

  @override
  Future<String?> songUrl(JsMusicSource source, {required MusicSong song, required QualityTier quality}) async {
    final raw = await _call(source, 'songUrl', {
      'id': song.id,
      'mediaId': song.mediaId ?? song.id,
      'quality': quality.name,
    }, (r) => r);
    if (raw is Map) return (raw['url'] as String?)?.trim().isEmpty == false ? raw['url'] as String : null;
    if (raw is String && raw.isNotEmpty) return raw;
    return null;
  }

  @override
  Future<List<MusicSong>> dailySongs(JsMusicSource source) async {
    if (source.capabilities.contains('dailySongs') == false) return const [];
    final raw = await _call(source, 'dailySongs', const {}, (r) => r);
    return _dto(platformId: source.platformId).songs(raw);
  }

  @override
  Future<List<MusicComment>> comments(
    JsMusicSource source, {
    required String songId,
    int limit = 20,
    int offset = 0,
  }) async {
    if (source.capabilities.contains('comments') == false) return const [];
    final raw = await _call(source, 'comments', {'songId': songId, 'limit': limit, 'offset': offset}, (r) => r);
    return _dto(platformId: source.platformId).comments(raw);
  }

  @override
  Future<List<MusicPlaylist>> recommendedPlaylists(JsMusicSource source, {int limit = 6}) async {
    if (source.capabilities.contains('recommendedPlaylists') == false) return const [];
    final raw = await _call(source, 'recommendedPlaylists', {'limit': limit}, (r) => r);
    return _dto(platformId: source.platformId).playlists(raw);
  }

  @override
  Future<List<MusicPlaylist>> userPlaylists(JsMusicSource source) async {
    if (source.capabilities.contains('userPlaylists') == false) return const [];
    final raw = await _call(source, 'userPlaylists', const {}, (r) => r);
    return _dto(platformId: source.platformId).playlists(raw);
  }

  @override
  Future<void> unload(String sourceId) async {
    _sources.remove(sourceId);
    if (_engine != null) {
      try {
        _engine!.evaluate('delete globalThis.__musicSources[${jsonEncode(sourceId)}]');
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _resetRuntime();
  }

  MusicSourceDto _dto({required String platformId}) => MusicSourceDto(platformId: platformId);
}

/// 引擎错误（code 与漫画源同枚举口径：NETWORK / TIMEOUT / PARSE / SPEC_UNSUPPORTED /
/// HOST_NOT_ALLOWED / SOURCE_CRASHED）。
class MusicSourceException implements Exception {
  const MusicSourceException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'MusicSourceException($code): $message';
}
