import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol/protocol.dart';

import '../../../core/storage/shell_prefs.dart';
import 'queue_controller.dart';
import '../../../core/window/window_controller.dart';
import '../domain/not_ready_state.dart';

/// 引擎运行状态（L1 + L2 合并，共用一个开关 —— D-012）。
///
/// ## 为什么引擎与 LLM 合并
/// 用户通常不知道自己需要哪个；两个开关只会让「为什么翻译不了」变成猜谜。
/// 一次点击拉起两个进程，任一失败即整组失败。
class EngineNotifier extends Notifier<EngineRuntimeState> {
  @override
  EngineRuntimeState build() => EngineRuntimeState.off;

  /// 启动引擎 + 大模型（共用一个开关，D-012）。
  ///
  /// 走 `POST /api/v1/engine/start`，用返回的 `EngineStatus` 推导状态 ——
  /// **不乐观置 running**：服务端未就绪时如实落 failed。
  Future<void> start() async {
    if (state == EngineRuntimeState.starting) return;
    state = EngineRuntimeState.starting;
    try {
      final status = await ref.read(mangaSvcClientProvider).startEngine();
      applyStatus(status);
    } catch (_) {
      state = EngineRuntimeState.failed;
    }
  }

  /// 停止引擎 + 大模型。
  Future<void> stop() async {
    if (state == EngineRuntimeState.stopping) return;
    state = EngineRuntimeState.stopping;
    try {
      final status = await ref.read(mangaSvcClientProvider).stopEngine();
      applyStatus(status);
    } catch (_) {
      state = EngineRuntimeState.failed;
    }
  }

  /// 从服务端拉一次引擎状态（供轮询调用）。
  Future<void> refreshFromServer() async {
    try {
      applyStatus(await ref.read(mangaSvcClientProvider).getEngineStatus());
    } catch (_) {
      // 拉取失败**不改状态**：网络抖动不该把「运行中」误判成「已停止」。
    }
  }

  /// 由轮询结果更新（服务端 `EngineStatus` 的 engine.state + llm.state 合成）。
  void applyStatus(EngineStatus? status) {
    if (status == null) return;
    final e = EngineRuntimeState.fromWire(status.engine.state);
    final l = EngineRuntimeState.fromWire(status.llm.state);
    // 两个进程都 running 才算就绪（只判一个会把「LLM 没起」当成就绪）。
    if (e == EngineRuntimeState.running && l == EngineRuntimeState.running) {
      state = EngineRuntimeState.running;
    } else if (e == EngineRuntimeState.starting || l == EngineRuntimeState.starting) {
      state = EngineRuntimeState.starting;
    } else if (e == EngineRuntimeState.failed || l == EngineRuntimeState.failed) {
      state = EngineRuntimeState.failed;
    } else {
      state = EngineRuntimeState.off;
    }
  }
}

final engineStateProvider = NotifierProvider<EngineNotifier, EngineRuntimeState>(EngineNotifier.new);

/// 翻译来源（三选一，D-012）。
///
/// 默认值按平台分：桌面 `local`，移动端只能是 `remote`。
class TranslateSourceNotifier extends Notifier<TranslateSource> {
  @override
  TranslateSource build() {
    final saved = readTranslateSource();
    if (saved != null) {
      final parsed = TranslateSource.parse(saved);
      // 移动端读到历史遗留的本地来源 → 强制回落 remote（本机没有运行时）。
      if (!isDesktopPlatform && parsed.requiresLocalRuntime) return TranslateSource.remote;
      return parsed;
    }
    // 移动端只有远程翻译（本机不跑服务，D-001）。
    return isDesktopPlatform ? TranslateSource.local : TranslateSource.remote;
  }

  void set(TranslateSource value) {
    // 移动端不允许切到需要本机运行时的来源。
    if (!isDesktopPlatform && value.requiresLocalRuntime) return;
    state = value;
    persistTranslateSource(value.wire);
  }
}

final translateSourceProvider = NotifierProvider<TranslateSourceNotifier, TranslateSource>(TranslateSourceNotifier.new);

/// 模型是否已装配。
///
/// P0-C 接入前恒为 false —— 这样引导页会稳定停在「未装配」态，
/// 不会因为返回 true 而让用户以为能翻译。
final modelsInstalledProvider = Provider<bool>((ref) => false);

/// 完整视图模型 —— UI 直接 watch 它。
final notReadyViewProvider = Provider<NotReadyView>((ref) {
  return deriveNotReadyView(
    source: ref.watch(translateSourceProvider),
    status: null, // P0-C 接入真实 EngineStatus 后替换
    modelsInstalled: ref.watch(modelsInstalledProvider),
    downloadProgress: null,
    logs: const [],
  );
});
