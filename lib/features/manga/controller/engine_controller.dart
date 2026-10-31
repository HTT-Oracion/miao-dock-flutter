import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol/protocol.dart';

import '../../../core/storage/shell_prefs.dart';
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

  /// 启动引擎 + 大模型。
  ///
  /// 真实实现走 `POST /engine/status` 轮询；P0-C 接入前这里只把状态推到 starting，
  /// **不假装成功**（调用方接的后端若无引擎，会在下一次轮询回到 failed）。
  Future<void> start() async {
    if (state == EngineRuntimeState.starting) return;
    state = EngineRuntimeState.starting;
    try {
      // P0-C：这里应调用 MangaSvcClient 的引擎启动端点。
      // 当前服务端未实现该端点 → 保持 starting 由轮询回落，不伪造 running。
    } catch (_) {
      state = EngineRuntimeState.failed;
    }
  }

  void stop() => state = EngineRuntimeState.stopping;

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
