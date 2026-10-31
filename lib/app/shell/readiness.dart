import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/process/service_controller.dart';
import '../../core/process/service_supervisor.dart';
import '../../features/manga/controller/engine_controller.dart';
import '../../features/manga/domain/not_ready_state.dart';

/// 侧栏状态点的**综合**就绪度（P0-D3）。
///
/// ## 为什么要在 `lib/app/` 层合成
/// 它同时依赖「服务进程」（core）与「引擎 / 翻译来源」（features）——
/// 让任一侧去 import 另一侧都会破坏分层（AGENTS §3：core 不得 import features）。
///
/// ## 判定顺序（先硬后软）
/// 1. 服务进程失败 → 红：整个漫画模块都不可用，此时引擎状态无意义；
/// 2. 服务未托管（移动端）→ 用引擎 / 来源的判定；
/// 3. 其余 → 引擎就绪度。
final shellReadinessProvider = Provider<ReadinessLevel>((ref) {
  final service = ref.watch(serviceStatusProvider);
  if (service.supported && service.state == ServiceProcessState.failed) {
    return ReadinessLevel.broken;
  }
  return ref.watch(notReadyViewProvider).readiness;
});
