/// 有道出网实现（D-053）：表单 POST + 超时。
///
/// ## 为什么不用 dio
/// mangasvc 是**纯 Dart** 服务（要 `dart compile exe` 分发），`dart:io` 已经够用；
/// 多一个依赖就多一份版本约束（`third-party-packages.md` §纪律 3：一次一个目的）。
///
/// ## 超时口径（对齐 miao-dock 的四层）
/// Dart 的 `HttpClient` 只给两层：`connectionTimeout`（连接）与 `idleTimeout`（空闲）。
/// - connect 5s → `connectionTimeout`；
/// - idle 20s → `idleTimeout`；
/// - ttfb / total → 用 `Future.timeout` 卡整次请求（近似，不是逐阶段计时）。
/// 🔴 不能只靠 `idleTimeout`：它管的是「连接空闲」，不是「整个请求」。
library;

import 'dart:convert';
import 'dart:io';

import 'youdao_client.dart';

/// 出网基址（对齐 miao-dock 的 `MIAO_TRANSLATE_YOUDAO_BASE`）。
///
/// 每次调用现读，不缓存：e2e 要在用例之间切到假上游。
String youdaoBaseUrl() {
  final raw = Platform.environment['MIAO_TRANSLATE_YOUDAO_BASE']?.trim() ?? '';
  if (raw.isEmpty) return 'https://openapi.youdao.com';
  return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
}

/// 测试用的 transport 覆盖点；null = 用真实出网。
///
/// 只在这里开一个口子：端点逻辑（取凭证、错误映射、响应结构）能脱离网络被测到，
/// 而生产路径永远走 [makeYoudaoTransport]。
YoudaoTransport? youdaoTransport;

/// 生产用 transport。
YoudaoTransport makeYoudaoTransport({
  Duration connectTimeout = const Duration(seconds: 5),
  Duration idleTimeout = const Duration(seconds: 20),
  Duration totalTimeout = const Duration(seconds: 30),
}) {
  return (String url, Map<String, String> fields) async {
    final client = HttpClient()
      ..connectionTimeout = connectTimeout
      ..idleTimeout = idleTimeout
      // 本地服务调外网：不要被系统代理劫走（与引擎调用同一口径）。
      ..findProxy = (_) => 'DIRECT';
    try {
      final body = Uri(queryParameters: fields).query;
      final req = await client.postUrl(Uri.parse(url));
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      final bytes = utf8.encode(body);
      req.headers.contentLength = bytes.length;
      req.add(bytes);
      final resp = await req.close().timeout(totalTimeout);
      final data = await resp.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk)).timeout(totalTimeout);
      return YoudaoHttpResponse(status: resp.statusCode, body: data);
    } finally {
      client.close(force: true);
    }
  };
}
