import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/shell_prefs.dart';
import '../../../core/net/service_locator.dart';
import '../data/http_manga_svc_client.dart';
import '../domain/not_ready_state.dart';

/// 远程连接配置（D-045）。
///
/// 远程模式下本机**不跑引擎**：手机 / Web / 插件都直连桌面端，所有翻译在对面发生。
/// 地址与令牌持久化到本地偏好 —— 每次打开都要重填是不可接受的。
class RemoteConfig {
  const RemoteConfig({this.baseUrl = '', this.token = ''});

  final String baseUrl;
  final String token;

  bool get configured => baseUrl.trim().isNotEmpty && token.trim().isNotEmpty;

  /// 配置是否**有效**（提交任务前的硬校验）。
  ///
  /// 与 [configured] 的区别：这里还校验地址形态 ——
  /// 只有 token、地址写成 `随便什么` 的配置连不上，应当提前拦下，
  /// 而不是等 HTTP 失败再让任务跑进流水线。
  bool get valid {
    if (token.trim().isEmpty) return false;
    final raw = baseUrl.trim();
    if (raw.isEmpty) return false;
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    final schemeOk = uri.scheme == 'http' || uri.scheme == 'https';
    return schemeOk && uri.host.isNotEmpty;
  }

  RemoteConfig copyWith({String? baseUrl, String? token}) =>
      RemoteConfig(baseUrl: baseUrl ?? this.baseUrl, token: token ?? this.token);
}

final remoteConfigProvider = NotifierProvider<RemoteConfigNotifier, RemoteConfig>(RemoteConfigNotifier.new);

class RemoteConfigNotifier extends Notifier<RemoteConfig> {
  @override
  RemoteConfig build() => RemoteConfig(baseUrl: readRemoteBaseUrl() ?? '', token: readRemoteToken() ?? '');

  /// 保存并落盘（输入框失焦或点「测试连接」时调用都安全）。
  void save({String? baseUrl, String? token}) {
    final next = state.copyWith(baseUrl: baseUrl, token: token);
    if (next.baseUrl != state.baseUrl || next.token != state.token) {
      ref.read(remoteVerificationProvider.notifier).invalidate();
    }
    state = next;
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

/// 远程配置必须在本次会话中显式校验；仅持久化地址与令牌不代表可用。
final remoteVerificationProvider = NotifierProvider<RemoteVerificationNotifier, RemoteVerificationState>(
  RemoteVerificationNotifier.new,
);

/// 最近一次远程校验的失败信息（null = 无 / 已成功）。
///
/// `verify()` 原本把 `RemoteProbe.message` 丢掉了，界面只能说「失败」，
/// 用户不知道是令牌错、地址错还是对面引擎没起（D-138）。
typedef RemoteVerifyFailure = ({RemoteVerifyIssue kind, String? detail});

final remoteVerifyMessageProvider = NotifierProvider<RemoteVerifyMessageNotifier, RemoteVerifyFailure?>(
  RemoteVerifyMessageNotifier.new,
);

class RemoteVerifyMessageNotifier extends Notifier<RemoteVerifyFailure?> {
  @override
  RemoteVerifyFailure? build() => null;

  void set(RemoteVerifyFailure? value) => state = value;
}

class RemoteVerificationNotifier extends Notifier<RemoteVerificationState> {
  int _generation = 0;

  @override
  RemoteVerificationState build() => RemoteVerificationState.unverified;

  void invalidate() {
    _generation += 1;
    state = RemoteVerificationState.unverified;
    ref.read(remoteVerifyMessageProvider.notifier).set(null);
  }

  Future<RemoteProbe?> verify() async {
    final config = ref.read(remoteConfigProvider);
    if (!config.valid) {
      state = RemoteVerificationState.failed;
      ref.read(remoteVerifyMessageProvider.notifier).set((kind: RemoteVerifyIssue.configIncomplete, detail: null));
      return null;
    }

    state = RemoteVerificationState.checking;
    final generation = _generation;
    final probe = await ref.read(remotePingProvider)(config);
    final current = ref.read(remoteConfigProvider);
    if (_generation != generation || current.baseUrl != config.baseUrl || current.token != config.token) {
      state = RemoteVerificationState.unverified;
      return null;
    }
    final ok = probe.ok && probe.engineReady;
    state = ok ? RemoteVerificationState.ready : RemoteVerificationState.failed;
    ref
        .read(remoteVerifyMessageProvider.notifier)
        .set(
          ok
              ? null
              : (
                  kind: probe.ok ? RemoteVerifyIssue.engineNotReady : RemoteVerifyIssue.probeFailed,
                  detail: probe.ok ? null : probe.message,
                ),
        );
    return probe;
  }
}
