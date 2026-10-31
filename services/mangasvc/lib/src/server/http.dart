/// 响应构造与错误信封 —— 全服务统一在这里出 JSON，避免各处手拼。
///
/// 错误信封形状（契约）：`{"error":{"code":"...","message":"...","details":{...}}}`
library;

import 'dart:convert';
import 'dart:io';

/// 服务端错误（业务层抛它，路由层转信封）。
class ServiceError implements Exception {
  const ServiceError(this.code, this.message, {this.details = const {}, this.status = 400});

  /// 机器可读错误码，如 `INVALID_IMAGE`。
  final String code;

  /// 面向开发者的说明（中文）；**UI 不直接展示**，按 code 映射 ARB。
  final String message;

  final Map<String, dynamic> details;
  final int status;

  @override
  String toString() => 'ServiceError($code): $message';
}

/// 写 JSON 响应。
Future<void> writeJson(HttpResponse res, int status, Object? body) async {
  final bytes = utf8.encode(jsonEncode(body));
  res.statusCode = status;
  res.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
  res.headers.contentLength = bytes.length;
  res.add(bytes);
  await res.close();
}

/// 写错误信封。
Future<void> writeError(HttpResponse res, ServiceError e) => writeJson(res, e.status, {
  'error': {'code': e.code, 'message': e.message, 'details': e.details},
});

/// 写通用错误。
Future<void> writeErrorCode(HttpResponse res, int status, String code, String message) => writeJson(res, status, {
  'error': {'code': code, 'message': message, 'details': <String, dynamic>{}},
});

/// 读请求体并解析 JSON 对象；空体返回空 map，非法 JSON 抛 [ServiceError]。
Future<Map<String, dynamic>> readJsonBody(HttpRequest req, {int maxBytes = 32 * 1024 * 1024}) async {
  final chunks = <int>[];
  var total = 0;
  await for (final chunk in req) {
    total += chunk.length;
    if (total > maxBytes) {
      throw ServiceError('BODY_TOO_LARGE', '请求体过大', details: {'limitBytes': maxBytes}, status: 413);
    }
    chunks.addAll(chunk);
  }
  if (chunks.isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(utf8.decode(chunks));
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw ServiceError('INVALID_JSON', '请求体必须是 JSON 对象');
  } on ServiceError {
    rethrow;
  } catch (e) {
    throw ServiceError('INVALID_JSON', '请求体不是合法 JSON：$e', details: {'bytes': chunks.length});
  }
}

/// ISO-8601 UTC 时间串（契约里所有时间字段的格式）。
String isoNow() => DateTime.now().toUtc().toIso8601String();

/// 把 [DateTime] 转契约时间串；null 原样返回 null。
String? isoOf(DateTime? t) => t?.toUtc().toIso8601String();
