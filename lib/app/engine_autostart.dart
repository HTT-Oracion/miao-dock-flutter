import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/shell_prefs.dart';
import '../core/window/window_controller.dart';
import '../features/manga/controller/engine_controller.dart';
import '../features/manga/controller/engine_install_controller.dart';
import '../features/manga/controller/engine_ready_controller.dart';
import '../features/manga/domain/not_ready_state.dart';

/// 启动应用时按设置自动起引擎（D-039）。
///
/// ## 为什么在 App 外层而不是某个页面里
/// 需求是「启动应用就起」，与用户先看到哪个页面无关。
/// 放在页面里会变成「先进入某页才起」，行为依赖导航，不可预期。
///
/// ## 只在桌面端、且装配完整时动手
/// - 移动端不跑本地服务（AGENTS §2）；
/// - 装配不完整时启动只会失败，徒增一条错误状态。
class EngineAutoStart extends ConsumerStatefulWidget {
  const EngineAutoStart({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EngineAutoStart> createState() => _EngineAutoStartState();
}

class _EngineAutoStartState extends ConsumerState<EngineAutoStart> {
  var _ran = false;

  @override
  void initState() {
    super.initState();
    // 等首帧之后再跑：此刻 ProviderScope 已就绪，也不会拖慢启动。
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  Future<void> _maybeStart() async {
    if (_ran || !isDesktopPlatform) return;
    _ran = true;
    if (!readAutoStartEngine()) return;

    // 装配不完整就别起：只会得到一条「启动失败」。
    final presence = await probeEnginePresence(ref.read(engineRootProvider));
    if (!mounted || presence != EnginePresence.complete) return;
    if (ref.read(engineStateProvider) != EngineRuntimeState.off) return;

    await ref.read(engineStateProvider.notifier).start();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
