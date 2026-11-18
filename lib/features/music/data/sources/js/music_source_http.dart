import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../domain/js_music_source.dart';

/// 源 HTTP 响应 → 宿主桥消息（与漫画源 `toMessage` 同形状，源作者体验一致）。
class MusicSourceHttpResponse {
  const MusicSourceHttpResponse({
    this.status = 0,
    this.headers = const {},
    this.body = '',
    this.bodyBytes = const [],
    this.error,
    this.errorCode,
  });

  final int status;
  final Map<String, List<String>> headers;
  final String body;

  /// 原始字节（`requestBytes` 用；文本路径解码后为空）。
  final List<int> bodyBytes;
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

/// 二进制响应（base64 过桥前的字节）。
class MusicSourceBytesResponse {
  const MusicSourceBytesResponse({this.status = 0, this.body = const [], this.error, this.errorCode});

  final int status;
  final List<int> body;
  final String? error;
  final String? errorCode;
}

/// 音乐源 HTTP 通道：域名白名单、清单默认头、Cookie、限速与超时。
///
/// 与漫画 `SourceHttp` 同一套安全口径（白名单 / 限速 / 大小上限），但不依赖
/// 漫画的清单类型 —— 音乐源用自己的 hosts / headers 字段。
class MusicSourceHttp {
  MusicSourceHttp({Dio? dio, this.maxTextBytes = 4 * 1024 * 1024}) : _dio = dio ?? Dio();

  final Dio _dio;
  final int maxTextBytes;

  /// host → cookie 名值对（按 host 前缀归桶，读时后缀匹配）。
  final Map<String, Map<String, String>> _cookies = {};
  final Map<String, int> _lastRequestAt = {};

  static bool hostAllowed(String host, List<String> hosts) {
    final h = host.toLowerCase();
    for (final pattern in hosts) {
      final p = pattern.toLowerCase().replaceFirst(RegExp(r'^\*\.'), '');
      if (h == p || h.endsWith('.$p')) return true;
    }
    return false;
  }

  void setCookies(String url, List<Map<String, Object?>> cookies) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return;
    final bucket = _cookies.putIfAbsent(host, () => {});
    for (final c in cookies) {
      final name = '${c['name'] ?? ''}';
      if (name.isEmpty) continue;
      bucket[name] = '${c['value'] ?? ''}';
    }
  }

  Map<String, List<String>> getCookies(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    final out = <String, List<String>>{};
    _cookies.forEach((bucketHost, jar) {
      if (host == bucketHost || host.endsWith('.$bucketHost') || bucketHost.endsWith('.$host')) {
        jar.forEach((name, value) => out[name] = [value]);
      }
    });
    return out;
  }

  /// 注入整串登录 Cookie（WebView 登录落盘的那串）到源的主域。
  void setSessionCookie(JsMusicSource source, String cookie) {
    final host = Uri.tryParse(source.manifest.baseUrl)?.host ?? '';
    if (host.isEmpty || cookie.trim().isEmpty) return;
    final bucket = _cookies.putIfAbsent(host, () => {});
    for (final part in cookie.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final name = part.substring(0, i).trim();
      final value = part.substring(i + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      bucket[name] = value;
    }
  }

  /// 清除源主域的会话 Cookie（退出登录 / 凭据失效时用）。
  void clearSessionCookie(JsMusicSource source) {
    final host = Uri.tryParse(source.manifest.baseUrl)?.host ?? '';
    if (host.isNotEmpty) _cookies.remove(host);
  }

  Future<MusicSourceHttpResponse> request({
    required String method,
    required String url,
    required JsMusicSource source,
    Map<String, String> headers = const {},
    Object? data,
    int? timeoutMs,
  }) async {
    final r = await _requestRaw(
      method: method,
      url: url,
      source: source,
      headers: headers,
      data: data,
      timeoutMs: timeoutMs,
    );
    if (r.error != null) return r;
    return MusicSourceHttpResponse(
      status: r.status,
      headers: r.headers,
      // 🔴 必须 utf8.decode：String.fromCharCodes 会把多字节 UTF-8 拆成
      // Latin-1 单字（中文歌名全变乱码），音乐接口响应都是 UTF-8。
      body: utf8.decode(r.bodyBytes, allowMalformed: true),
    );
  }

  /// 二进制响应（咪咕混淆流）：字节原样返回，由源侧解码。
  Future<MusicSourceBytesResponse> requestBytes({
    required String method,
    required String url,
    required JsMusicSource source,
    Map<String, String> headers = const {},
    int? timeoutMs,
  }) async {
    final r = await _requestRaw(method: method, url: url, source: source, headers: headers, timeoutMs: timeoutMs);
    return MusicSourceBytesResponse(status: r.status, body: r.bodyBytes, error: r.error, errorCode: r.errorCode);
  }

  Future<MusicSourceHttpResponse> _requestRaw({
    required String method,
    required String url,
    required JsMusicSource source,
    Map<String, String> headers = const {},
    Object? data,
    int? timeoutMs,
  }) async {
    final uri = Uri.tryParse(url);
    final manifest = source.manifest;
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const MusicSourceHttpResponse(error: 'invalid url', errorCode: 'NETWORK');
    }
    if (!hostAllowed(uri.host, manifest.hosts)) {
      return MusicSourceHttpResponse(error: 'host not allowed: ${uri.host}', errorCode: 'HOST_NOT_ALLOWED');
    }
    final timeout = Duration(milliseconds: (timeoutMs ?? manifest.timeoutMs).clamp(1000, 60000));
    await _rateLimit(source);
    try {
      final mergedHeaders = <String, String>{...manifest.headers, ...headers};
      final cookie = _cookieHeader(uri.host);
      if (cookie.isNotEmpty && !mergedHeaders.keys.any((k) => k.toLowerCase() == 'cookie')) {
        mergedHeaders['Cookie'] = cookie;
      }
      if (!mergedHeaders.keys.any((k) => k.toLowerCase() == 'accept-language')) {
        mergedHeaders['Accept-Language'] = 'zh-CN,zh;q=0.9';
      }
      final response = await _dio.request<List<int>>(
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
      );
      final status = response.statusCode ?? 0;
      final bodyBytes = response.data ?? Uint8List(0);
      if (bodyBytes.length > maxTextBytes) {
        return const MusicSourceHttpResponse(error: 'response too large', errorCode: 'NETWORK');
      }
      return MusicSourceHttpResponse(status: status, headers: response.headers.map, body: '', bodyBytes: bodyBytes);
    } catch (e) {
      return MusicSourceHttpResponse(error: '$e', errorCode: 'NETWORK');
    }
  }

  String _cookieHeader(String host) {
    final parts = <String>[];
    _cookies.forEach((bucketHost, jar) {
      final matched = host == bucketHost || host.endsWith('.$bucketHost') || bucketHost.endsWith('.$host');
      if (!matched) return;
      jar.forEach((name, value) => parts.add('$name=$value'));
    });
    return parts.join('; ');
  }

  Future<void> _rateLimit(JsMusicSource source) async {
    final interval = source.manifest.rateLimitIntervalMs;
    if (interval <= 0) return;
    final key = source.id;
    final last = _lastRequestAt[key];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last != null) {
      final wait = interval - (now - last);
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    }
    _lastRequestAt[key] = DateTime.now().millisecondsSinceEpoch;
  }
}
