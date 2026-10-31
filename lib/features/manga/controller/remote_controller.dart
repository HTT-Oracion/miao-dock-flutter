import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/shell_prefs.dart';
import '../../../core/net/service_locator.dart';
import '../data/http_manga_svc_client.dart';

/// 远程连接配置（D-045）。
///
/// 远程模式下本机**不跑引擎**：手机 / Web / 插件都直连桌面端，所有翻译在对面发生。
/// 地址与令牌持久化到本地偏好 —— 每次打开都要重填是不可接受的。
class RemoteConfig {
  const RemoteConfig({this.baseUrl = '', this.token = ''});

  final String baseUrl;
  final String token;

  bool get configured => baseUrl.trim().isNotEmpty && token.trim().isNotEmpty;

  RemoteConfig copyWith({String? baseUrl, String? token}) =>
      RemoteConfig(baseUrl: baseUrl ?? this.baseUrl, token: token ?? this.token);
}

final remoteConfigProvider = NotifierProvider<RemoteConfigNotifier, RemoteConfig>(RemoteConfigNotifier.new);

class RemoteConfigNotifier extends Notifier<RemoteConfig> {
  @override
  RemoteConfig build() => RemoteConfig(baseUrl: readRemoteBaseUrl() ?? '', token: readRemoteToken() ?? '');

  /// 保存并落盘（输入框失焦或点「测试连接」时调用都安全）。
  void save({String? baseUrl, String? token}) {
    state = state.copyWith(baseUrl: baseUrl, token: token);
    if (baseUrl != null) persistRemoteBaseUrl(baseUrl.trim());
    if (token != null) persistRemoteToken(token.trim());
  }
}

/// 连接测试结果（三件事：能连上 / 令牌对 / 对面引擎起没起）。
class RemoteProbe {
  const RemoteProbe({required this.ok, required this.message, this.engineReady = false, this.platform = ''});

  final bool ok;
  final String message;
  final bool engineReady;
  final String platform;
}

/// 探测远程服务。
///
/// 用 `/api/v1/ping` 而不是 `/health`：后者不校验令牌，只能证明「服务在」，
/// 证明不了「令牌对」——而远程场景下这两件事都必须确认。
final remotePingProvider = Provider<Future<RemoteProbe> Function(RemoteConfig)>(
  (ref) => (cfg) async {
    try {
      final client = HttpMangaSvcClient(RemoteServiceLocator(baseUrl: cfg.baseUrl.trim(), token: cfg.token.trim()));
      final r = await client.ping();
      return RemoteProbe(
        ok: true,
        message: 'ok',
        engineReady: r['engineReady'] == true,
        platform: '${r['platform'] ?? ''}',
      );
    } catch (e) {
      return RemoteProbe(ok: false, message: '$e');
    }
  },
);
