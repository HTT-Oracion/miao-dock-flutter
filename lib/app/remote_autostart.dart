import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/manga/controller/engine_controller.dart';
import '../features/manga/controller/remote_controller.dart';
import '../features/manga/domain/not_ready_state.dart';

/// 启动时自动校验远程配置（D-165）。
///
/// ## 为什么挂在 App 外层
/// 与 [EngineAutoStart] 同一个理由：远程配置「本次会话是否可用」是启动后就要成立的
/// 事实，与用户先打开哪个页面无关。放在门禁卡里，就变成「进漫画模块才校验」——
/// 用户看到的仍是「请先校验远程配置 + 一个需要点的按钮」。
///
/// ## 只跑一次，且只在能校验的时候跑
/// - 本地来源没有「远程」这回事，直接跳过；
/// - 配置不完整时**不**探测：`verify()` 会立刻落 failed，首次打开的用户先看到一屏
///   红色「失败」，而真正该做的是去设置填地址与令牌；
/// - 失败不自动重试：对面离线时每次重建都发一轮探测就是探测风暴，重试交给卡片按钮。
class RemoteAutoVerify extends ConsumerStatefulWidget {
  const RemoteAutoVerify({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RemoteAutoVerify> createState() => _RemoteAutoVerifyState();
}

class _RemoteAutoVerifyState extends ConsumerState<RemoteAutoVerify> {
  var _ran = false;

  @override
  void initState() {
    super.initState();
    // 首帧之后再跑：此刻容器已就绪，也不拖慢启动。
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeVerify());
  }

  Future<void> _maybeVerify() async {
    if (_ran || !mounted) return;
    _ran = true;
    if (ref.read(translateSourceProvider) != TranslateSource.remote) return;
    if (ref.read(remoteVerificationProvider) != RemoteVerificationState.unverified) return;
    if (!ref.read(remoteConfigProvider).valid) return;
    await ref.read(remoteVerificationProvider.notifier).verify();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
