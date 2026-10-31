import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../manga/controller/engine_controller.dart';
import '../../manga/domain/not_ready_state.dart';
import '../../manga/controller/queue_controller.dart';

/// 引擎设置项（C2 白名单内的键）。
class EngineSettings {
  const EngineSettings({
    this.direction = 'ja-zh',
    this.tier = 'auto',
    this.accel = 'auto',
    this.idleUnloadMinutes = 5,
    this.visualIdleUnloadMinutes = 30,
  });

  final String direction;
  final String tier;
  final String accel;
  final int idleUnloadMinutes;
  final int visualIdleUnloadMinutes;

  EngineSettings copyWith({
    String? direction,
    String? tier,
    String? accel,
    int? idleUnloadMinutes,
    int? visualIdleUnloadMinutes,
  }) => EngineSettings(
    direction: direction ?? this.direction,
    tier: tier ?? this.tier,
    accel: accel ?? this.accel,
    idleUnloadMinutes: idleUnloadMinutes ?? this.idleUnloadMinutes,
    visualIdleUnloadMinutes: visualIdleUnloadMinutes ?? this.visualIdleUnloadMinutes,
  );
}

/// 引擎设置状态。
final engineSettingsProvider = NotifierProvider<EngineSettingsNotifier, EngineSettings>(EngineSettingsNotifier.new);

class EngineSettingsNotifier extends Notifier<EngineSettings> {
  @override
  EngineSettings build() {
    // 从服务端 options 的 current 初始化；拉取失败保持默认值（设置页仍可用）。
    _loadFromServer();
    return const EngineSettings();
  }

  Future<void> _loadFromServer() async {
    try {
      final opts = await ref.read(mangaSvcClientProvider).getEngineOptions();
      final current = opts['current'];
      if (current is! Map) return;
      state = state.copyWith(
        direction: current['direction'] is String ? current['direction'] as String : null,
        tier: current['tier'] is String ? current['tier'] as String : null,
        accel: current['accel'] is String ? current['accel'] as String : null,
        idleUnloadMinutes: current['idleUnloadMinutes'] is num ? (current['idleUnloadMinutes'] as num).toInt() : null,
        visualIdleUnloadMinutes: current['visualIdleUnloadMinutes'] is num
            ? (current['visualIdleUnloadMinutes'] as num).toInt()
            : null,
      );
    } catch (_) {
      // 服务不可达时保持本地默认；设置页仍可浏览（不是所有项都要服务在线）。
    }
  }

  /// 保存单项设置：走服务端白名单校验，成功后更新本地视图。
  ///
  /// 返回 `needsRestart` —— 改 tier / accel 需要重启引擎才生效（C2 契约）。
  Future<bool> save({String? tier, String? accel, int? idleUnloadMinutes}) async {
    final patch = <String, dynamic>{'tier': ?tier, 'accel': ?accel, 'idleUnloadMinutes': ?idleUnloadMinutes};
    final needsRestart = await ref.read(mangaSvcClientProvider).setEngineSettings(patch);
    if (tier != null) state = state.copyWith(tier: tier);
    if (accel != null) state = state.copyWith(accel: accel);
    if (idleUnloadMinutes != null) state = state.copyWith(idleUnloadMinutes: idleUnloadMinutes);
    return needsRestart;
  }
}

/// 引擎状态轮询（设置页打开时每 1.5s 拉一次，与原项目同节奏）。
final engineStatusPollProvider = StreamProvider<EngineRuntimeState>((ref) {
  final controller = StreamController<EngineRuntimeState>();
  Timer? timer;
  Future<void> tick() async {
    try {
      await ref.read(engineStateProvider.notifier).refreshFromServer();
    } catch (_) {}
    controller.add(ref.read(engineStateProvider));
  }

  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });

  tick();
  timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => tick());
  return controller.stream;
});
