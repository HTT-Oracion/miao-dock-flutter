import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../domain/online_error.dart';
import '../domain/source_manifest.dart';

/// 宿主替源执行的 HTTP 响应。非 2xx **不在这里抛**：源自己按 status 分支
/// （404 → NOT_FOUND、403 → BLOCKED），宿主只在网络层失败时回 error。
class SourceHttpResponse {
  const SourceHttpResponse({this.status, this.headers = const {}, this.body, this.error, this.errorCode});

  final int? status;
  final Map<String, String> headers;
  final Object? body;
  final String? error;
  final String? errorCode;

  Map<String, Object?> toMessage() => {
    'status': status,
    'headers': headers,
    'body': body,
    if (error != null) 'error': error,
    if (errorCode != null) 'errorCode': errorCode,
  };
}

/// 数据源 HTTP 通道：域名白名单、清单默认头、Cookie、限速、超时与大小上限。
class SourceHttp {
  SourceHttp({Dio? dio, this.maxTextBytes = 4 * 1024 * 1024, this.maxBinaryBytes = 16 * 1024 * 1024})
    : _dio = dio ?? Dio();

  final Dio _dio;
  final int maxTextBytes;
  final int maxBinaryBytes;

  final Map<String, Uint8List> _cookies = {};
  final Map<String, Future<void>> _queues = {};
  final Map<String, int> _lastRequestAt = {};

  /// 源仓库 / 单源清单下载不受 manifest 白名单限制，但仍限制大小与协议。
  Future<({int status, String body})> fetchRemoteText(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 20),
    int maxBytes = 512 * 1024,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw const OnlineException(OnlineErrorCode.network, 'invalid url');
    }
    try {
      final response = await _dio
          .get<List<int>>(
            url,
            options: Options(
              responseType: ResponseType.bytes,
              followRedirects: true,
              validateStatus: (_) => true,
              headers: {...headers, 'Accept': 'application/json,text/plain,*/*'},
              receiveTimeout: timeout,
              sendTimeout: timeout,
            ),
          )
          .timeout(timeout);
      final data = response.data ?? const <int>[];
      if (data.length > maxBytes) {
        throw OnlineException(OnlineErrorCode.http, 'response too large: ${data.length}');
      }
      return (status: response.statusCode ?? 0, body: _decodeUtf8(Uint8List.fromList(data)));
    } on OnlineException {
      rethrow;
    } on DioException catch (e) {
      throw OnlineException(_mapDio(e), e.message ?? '${e.type}');
    } catch (e) {
      throw OnlineException(OnlineErrorCode.network, '$e');
    }
  }

  Future<Uint8List> fetchRemoteBytes(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 20),
    int maxBytes = 1024 * 1024,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw const OnlineException(OnlineErrorCode.network, 'invalid url');
    }
    try {
      final response = await _dio
          .get<List<int>>(
            url,
            options: Options(
              responseType: ResponseType.bytes,
              followRedirects: true,
              validateStatus: (_) => true,
              headers: headers,
              receiveTimeout: timeout,
              sendTimeout: timeout,
            ),
          )
          .timeout(timeout);
      if ((response.statusCode ?? 0) < 200 || (response.statusCode ?? 0) >= 300) {
        throw OnlineException(OnlineErrorCode.http, 'status ${response.statusCode}');
      }
      final data = response.data ?? const <int>[];
      if (data.length > maxBytes) {
        throw OnlineException(OnlineErrorCode.http, 'response too large: ${data.length}');
      }
      return Uint8List.fromList(data);
    } on OnlineException {
      rethrow;
    } on DioException catch (e) {
      throw OnlineException(_mapDio(e), e.message ?? '${e.type}');
    } catch (e) {
      throw OnlineException(OnlineErrorCode.network, '$e');
    }
  }

  Future<SourceHttpResponse> request({
    required String method,
    required String url,
    required SourceManifest manifest,
    Map<String, String> headers = const {},
    Object? data,
    bool bytes = false,
    int? timeoutMs,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const SourceHttpResponse(error: 'invalid url', errorCode: 'NETWORK');
    }
    if (!hostAllowed(uri.host, manifest.hosts)) {
      return SourceHttpResponse(error: 'host not allowed: ${uri.host}', errorCode: 'HOST_NOT_ALLOWED');
    }
    final timeout = Duration(milliseconds: (timeoutMs ?? manifest.timeoutMs).clamp(1000, 60000));
    await _rateLimit(manifest);
    try {
      final mergedHeaders = <String, String>{...manifest.headers, ...headers};
      final cookie = _cookieHeader(uri.host);
      if (cookie.isNotEmpty && !mergedHeaders.keys.any((key) => key.toLowerCase() == 'cookie')) {
        mergedHeaders['Cookie'] = cookie;
      }
      if (!mergedHeaders.keys.any((key) => key.toLowerCase() == 'accept-language')) {
        mergedHeaders['Accept-Language'] = 'zh-CN,zh;q=0.9';
      }
      final response = await _dio
          .request<List<int>>(
            url,
            data: data,
            options: Options(
              method: method.toUpperCase(),
              responseType: ResponseType.bytes,
              followRedirects: true,
              validateStatus: (_) => true,
              headers: mergedHeaders,
              receiveTimeout: timeout,
              sendTimeout: timeout,
            ),
          )
          .timeout(timeout);
      final responseBytes = Uint8List.fromList(response.data ?? const <int>[]);
      final limit = bytes ? maxBinaryBytes : maxTextBytes;
      if (responseBytes.length > limit) {
        return SourceHttpResponse(
          status: response.statusCode,
          error: 'response too large: ${responseBytes.length}',
          errorCode: 'HTTP_ERROR',
        );
      }
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) => responseHeaders[name.toLowerCase()] = values.join(','));
      return SourceHttpResponse(
        status: response.statusCode,
        headers: responseHeaders,
        body: bytes ? responseBytes : _decodeUtf8(responseBytes),
      );
    } on DioException catch (e) {
      return SourceHttpResponse(error: e.message ?? '${e.type}', errorCode: _mapDio(e).wireName);
    } catch (e) {
      return SourceHttpResponse(error: '$e', errorCode: 'NETWORK');
    }
  }

  void setCookies(String url, List<Map<String, Object?>> cookies) {
    final host = Uri.tryParse(url)?.host ?? '';
    for (final cookie in cookies) {
      final name = '${cookie['name'] ?? ''}';
      final value = '${cookie['value'] ?? ''}';
      if (name.isEmpty) continue;
      final domain = '${cookie['domain'] ?? host}'.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
      final key = '$domain\n$name';
      if (value.isEmpty) {
        _cookies.remove(key);
      } else {
        _cookies[key] = Uint8List.fromList('$name=$value'.codeUnits);
      }
    }
  }

  List<Map<String, Object?>> getCookies(String url) {
    final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
    final result = <Map<String, Object?>>[];
    for (final entry in _cookies.entries) {
      final domain = entry.key.split('\n').first;
      if (host == domain || host.endsWith('.$domain')) {
        final pair = String.fromCharCodes(entry.value).split('=');
        result.add({'name': pair.first, 'value': pair.skip(1).join('='), 'domain': domain});
      }
    }
    return result;
  }

  void clearCookies() => _cookies.clear();

  String _cookieHeader(String host) {
    final values = <String>[];
    for (final entry in _cookies.entries) {
      final domain = entry.key.split('\n').first;
      if (host == domain || host.endsWith('.$domain')) {
        values.add(String.fromCharCodes(entry.value));
      }
    }
    return values.join('; ');
  }

  Future<void> _rateLimit(SourceManifest manifest) {
    final previous = _queues[manifest.id] ?? Future<void>.value();
    final completer = Completer<void>();
    _queues[manifest.id] = completer.future;
    Future<void> run() async {
      final last = _lastRequestAt[manifest.id] ?? 0;
      final wait = manifest.rateLimitIntervalMs - (DateTime.now().millisecondsSinceEpoch - last);
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      _lastRequestAt[manifest.id] = DateTime.now().millisecondsSinceEpoch;
    }

    final result = previous.then((_) => run()).whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    });
    return result;
  }

  static bool hostAllowed(String host, List<String> patterns) {
    final normalized = host.toLowerCase();
    for (final pattern in patterns) {
      final value = pattern.toLowerCase();
      if (value.startsWith('*.')) {
        final suffix = value.substring(2);
        if (normalized == suffix || normalized.endsWith('.$suffix')) return true;
      } else if (normalized == value) {
        return true;
      }
    }
    return false;
  }

  static OnlineErrorCode _mapDio(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => OnlineErrorCode.timeout,
      DioExceptionType.badCertificate => OnlineErrorCode.network,
      _ => OnlineErrorCode.network,
    };
  }

  static String _decodeUtf8(Uint8List bytes) {
    try {
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }
}
