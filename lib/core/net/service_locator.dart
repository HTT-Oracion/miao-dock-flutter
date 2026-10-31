import 'package:protocol/protocol.dart';

import 'manga_svc_http.dart';
import 'port_probe.dart';

/// 服务定位与鉴权 —— 对应 P0-A3 + P0-A4。
///
/// ## 职责
/// 1. **定位**：桌面端走端口段探测（5180–5190）；移动端 / Web 端用设置域里手动配置的地址。
/// 2. **鉴权**：带上配对令牌；401 时把错误如实上报（**不静默重试**，否则用户看到的是空列表）。
/// 3. **缓存**：定位成功后记住 baseUrl，避免每次请求都扫一遍端口。
///
/// ## 平台差异的收口点
/// AGENTS §3 要求「平台差异只在 bootstrap 收口」。本类被 bootstrap 注入具体实现，
/// 业务层只依赖 [ServiceLocator] 接口，不判断平台。
abstract class ServiceLocator {
  /// 取得可用客户端；失败抛 [MangaSvcException]（`unreachable` / `unauthorized`）。
  Future<MangaSvcHttpClient> client();
}

/// 桌面端：端口段探测 + 令牌。
class LocalServiceLocator implements ServiceLocator {
  LocalServiceLocator({
    this.probe = const PortProbe(),
    this.token,
    MangaSvcHttpClient Function(String baseUrl, String? token)? factory,
  }) : _factory = factory ?? ((baseUrl, token) => MangaSvcHttpClient(baseUrl: baseUrl, token: token));

  final PortProbe probe;
  final MangaSvcHttpClient Function(String baseUrl, String? token) _factory;

  /// 配对令牌；null = 无令牌（服务端未启用鉴权时允许）。
  String? token;

  MangaSvcHttpClient? _cached;

  /// 已定位到的 baseUrl（诊断用）。
  String? get resolvedBaseUrl => _cached?.baseUrl;

  @override
  Future<MangaSvcHttpClient> client() async {
    final cached = _cached;
    if (cached != null) return cached;
    final baseUrl = await probe.discover();
    if (baseUrl == null) {
      throw const MangaSvcException(kind: MangaSvcErrorKind.unreachable, message: '未在 5180–5190 找到 mangasvc（服务可能未启动）');
    }
    return _cached = _factory(baseUrl, token);
  }

  /// 令牌变更后重建客户端（下次请求生效）。
  void updateToken(String? value) {
    token = value;
    _cached?.updateToken(value);
  }

  /// 丢弃缓存，强制下次重新探测（服务重启后调用）。
  void invalidate() => _cached = null;
}

/// 移动端 / Web 端：连手动配置的桌面端地址。
class RemoteServiceLocator implements ServiceLocator {
  RemoteServiceLocator({
    required this.baseUrl,
    this.token,
    MangaSvcHttpClient Function(String baseUrl, String? token)? factory,
  }) : _factory = factory ?? ((baseUrl, token) => MangaSvcHttpClient(baseUrl: baseUrl, token: token));

  /// 设置域里配置的地址（形如 `http://192.168.1.10:5180`）。
  ///
  /// 自动补 `/api/v1`：用户只填 `host:port` 也能用。
  final String baseUrl;
  final String? token;

  final MangaSvcHttpClient Function(String baseUrl, String? token) _factory;

  MangaSvcHttpClient? _cached;

  @override
  Future<MangaSvcHttpClient> client() async {
    if (baseUrl.trim().isEmpty) {
      throw const MangaSvcException(kind: MangaSvcErrorKind.unreachable, message: '未配置桌面端服务地址（见 设置 → 翻译服务）');
    }
    return _cached ??= _factory(_normalize(baseUrl), token);
  }

  /// 补齐协议与 `/api/v1` 前缀。
  static String _normalize(String raw) {
    var url = raw.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/api/v1')) return url;
    return '$url/api/v1';
  }
}
