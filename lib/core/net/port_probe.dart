import 'dart:async';
import 'dart:io';

/// 端口段探测 —— 对应 P0-A3。
///
/// 原项目契约（`src-tauri/src/mangasvc.rs` / `animesvc.rs`）：
///   · 服务在 **127.0.0.1:5180–5190** 内「先探测再绑定」，先起的占 5180；
///   · 客户端不知道服务落在哪一段，必须**逐端口试**。
///
/// 探测判据不能只看「端口能不能连」：同段可能有别的进程，连上也不回我们的健康检查。
/// 因此判定顺序是：TCP 可达 → `/health` 返回 200 → 响应体 `service` 字段匹配。
class PortProbe {
  const PortProbe({this.start = 5180, this.end = 5190, this.serviceName = 'mangasvc'});

  final int start;
  final int end;

  /// 期望的服务名（`GET /health` 的 `service` 字段）。
  final String serviceName;

  /// 探测到可用服务时的结果。
  ///
  /// `baseUrl` 已带 `/api/v1` 前缀，可直接交给 `MangaSvcHttpClient`。
  static const String apiPath = '/api/v1';

  /// 逐端口探测，返回第一个通过健康检查的 baseUrl；全部失败返回 null。
  ///
  /// 不抛异常：调用方需要区分「服务没起」与「有服务但契约不对」，
  /// 由它按自己的 UI 语义处理（设计稿 §07：失败态与空态分开）。
  Future<String?> discover({
    Duration perPortTimeout = const Duration(milliseconds: 400),
    HttpClient Function()? httpClientFactory,
  }) async {
    for (var port = start; port <= end; port++) {
      final ok = await _probePort(port, perPortTimeout, httpClientFactory);
      if (ok) return 'http://127.0.0.1:$port$apiPath';
    }
    return null;
  }

  /// 单端口探测。
  Future<bool> _probePort(int port, Duration timeout, HttpClient Function()? factory) async {
    final client = (factory ?? HttpClient.new)()..connectionTimeout = timeout;
    try {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port/health'))
          .timeout(timeout, onTimeout: () => throw TimeoutException('connect'));
      final res = await req.close().timeout(timeout);
      if (res.statusCode != HttpStatus.ok) return false;
      final body = await res.transform(const SystemEncoding().decoder).join().timeout(timeout);
      // 契约：`{"service":"mangasvc", ...}`。端口被别的服务占用时这里不匹配。
      return body.contains('"service"') && body.contains(serviceName);
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
