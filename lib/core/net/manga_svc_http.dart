import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:protocol/protocol.dart';

/// mangasvc 的 HTTP 传输层 —— 对应 P0-A2。
///
/// 职责边界：**只做搬运与错误归口**，不做业务判断。
///   · 拼 URL、注入令牌、超时；
///   · 把 HTTP / 网络 / 契约解析失败统一收敛成 [MangaSvcException]；
///   · 把错误信封 `{error:{code,message,details}}` 解析成 [ApiError]。
///
/// 不做的事：不缓存、不重试业务错误、不把空响应伪造成空列表。
class MangaSvcHttpClient {
  MangaSvcHttpClient({
    required String baseUrl,
    String? token,
    Dio? dio,
    HttpClientAdapter? adapter,
    Duration connectTimeout = const Duration(seconds: 3),
    Duration receiveTimeout = const Duration(seconds: 20),
  }) : _token = token,
       _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: connectTimeout,
           receiveTimeout: receiveTimeout,
           // 自己处理状态码：非 2xx 也要读错误信封。
           validateStatus: (_) => true,
           headers: {
             'Accept': 'application/json',
             if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
           },
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  final Dio _dio;
  String? _token;

  /// 当前 baseUrl（端口探测后会被更新）。
  String get baseUrl => _dio.options.baseUrl;

  /// 当前令牌（诊断 / 断言用）。
  String? get token => _token;

  /// 改端口（探测到新端口时调用）。
  void updateBaseUrl(String value) => _dio.options.baseUrl = value;

  /// 令牌（配对后更新）。
  void updateToken(String? value) {
    _token = value;
    if (value == null || value.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $value';
    }
  }

  Future<Map<String, dynamic>> getJson(String path, {Map<String, dynamic>? query}) async {
    return _request(() => _dio.get<dynamic>(path, queryParameters: query));
  }

  Future<Map<String, dynamic>> postJson(String path, {Object? body}) async {
    return _request(() => _dio.post<dynamic>(path, data: body));
  }

  Future<Map<String, dynamic>> deleteJson(String path, {Object? body}) async {
    return _request(() => _dio.delete<dynamic>(path, data: body));
  }

  /// 取原始字节（封面 / 原图）。
  Future<List<int>?> getBytes(String path) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes, headers: {'Accept': '*/*'}),
      );
      final status = res.statusCode ?? 0;
      if (status == 404) return null; // 无封面不是错误
      if (status >= 200 && status < 300) return res.data ?? const [];
      throw _toException(res, null);
    } on DioException catch (e) {
      throw _fromDioException(e);
    }
  }

  /// SSE 流。实现方按 `event:` / `data:` 分帧，这里只负责拿到原始行流。
  Stream<String> getEventLines(String path) async* {
    final response = await _dio.get<ResponseBody>(
      path,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
        receiveTimeout: Duration.zero, // 长连接不设接收超时
      ),
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw _toException(response, null);
    }
    final body = response.data;
    if (body == null) return;
    yield* body.stream.cast<List<int>>().transform(_lineDecoder());
  }

  Future<Map<String, dynamic>> _request(Future<Response<dynamic>> Function() send) async {
    try {
      final res = await send();
      final status = res.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        return _asJsonMap(res.data, status);
      }
      throw _toException(res, null);
    } on DioException catch (e) {
      throw _fromDioException(e);
    }
  }

  /// 响应体 → JSON 对象。
  ///
  /// dio 对 `application/json` 的响应会**自动反序列化**，但在部分 Content-Type
  /// （缺 charset、或 `text/plain`）下会原样返回 String —— 两种情况都要能处理，
  /// 否则正常响应会被误判成协议错误。
  Map<String, dynamic> _asJsonMap(dynamic data, int status) {
    if (data == null) return const {};
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      if (data.isEmpty) return const {};
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // 落到下面的协议错误
      }
    }
    throw MangaSvcException(
      kind: MangaSvcErrorKind.protocol,
      message: '期望 JSON 对象，实际得到 ${data.runtimeType}',
      statusCode: status,
    );
  }

  /// 非 2xx → 解析错误信封。
  MangaSvcException _toException(Response<dynamic> res, Object? _) {
    final status = res.statusCode ?? 0;
    final envelope = _parseEnvelope(res.data);
    final kind = switch (status) {
      401 || 403 => MangaSvcErrorKind.unauthorized,
      408 || 504 => MangaSvcErrorKind.timeout,
      _ => MangaSvcErrorKind.apiError,
    };
    return MangaSvcException(
      kind: kind,
      message: envelope?.message ?? 'HTTP $status',
      statusCode: status,
      apiError: envelope,
    );
  }

  MangaSvcException _fromDioException(DioException e) {
    final kind = switch (e.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.badCertificate => MangaSvcErrorKind.unreachable,
      DioExceptionType.receiveTimeout || DioExceptionType.sendTimeout => MangaSvcErrorKind.timeout,
      DioExceptionType.badResponse => MangaSvcErrorKind.apiError,
      _ => MangaSvcErrorKind.unknown,
    };
    return MangaSvcException(kind: kind, message: e.message ?? e.toString());
  }

  /// 解析 `{ "error": { code, message, details } }`；不合形状返回 null。
  ApiError? _parseEnvelope(dynamic data) {
    final map = data is String ? _tryDecode(data) : data;
    if (map is! Map) return null;
    final error = map['error'];
    if (error is! Map) return null;
    final code = error['code'];
    if (code is! String) return null;
    final message = error['message'];
    final details = error['details'];
    return ApiError(
      code: code,
      message: message is String ? message : '',
      details: details is Map ? Map<String, dynamic>.from(details) : null,
    );
  }
}

/// 尝试把字符串解析成 Map；失败返回 null。
Map<dynamic, dynamic>? _tryDecode(String raw) {
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// 把字节流按行解码为字符串（SSE 用）。
///
/// 不用 `utf8.decoder` + `LineSplitter` 组合：多字节字符可能跨 chunk 断裂，
/// 这里按字节累积、遇 `\n` 才解码，保证中文阶段名不被截断成乱码。
StreamTransformer<List<int>, String> _lineDecoder() {
  return StreamTransformer<List<int>, String>.fromBind((Stream<List<int>> stream) async* {
    final buffer = <int>[];
    await for (final chunk in stream) {
      for (final byte in chunk) {
        if (byte == 0x0A) {
          if (buffer.isNotEmpty && buffer.last == 0x0D) buffer.removeLast();
          yield utf8.decode(buffer, allowMalformed: true);
          buffer.clear();
        } else {
          buffer.add(byte);
        }
      }
    }
    if (buffer.isNotEmpty) yield utf8.decode(buffer, allowMalformed: true);
  });
}
