import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol/protocol.dart';

import '../../../core/storage/shell_prefs.dart';
import 'queue_controller.dart';
import '../../../core/storage/paths.dart';
import '../domain/not_ready_state.dart';
import '../domain/platform_caps.dart';
import 'engine_install_controller.dart';

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
    ref.read(engineStartErrorProvider.notifier).set(null);
    try {
      final status = await ref.read(mangaSvcClientProvider).startEngine();
      applyStatus(status);
    } catch (e) {
      // 🔴 不能吞：用户看到的「点了没反应」正是这条信息被丢掉造成的。
      ref.read(engineStartErrorProvider.notifier).set('$e');
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
      // Web / 移动端读到历史遗留的本地来源 → 强制回落 remote（本机跑不了引擎）。
      if (!supportsLocalEngine && parsed.requiresLocalRuntime) return TranslateSource.remote;
      return parsed;
    }
    // Web / 移动端只有远程翻译（本机不跑引擎，D-001 / D-044）。
    return supportsLocalEngine ? TranslateSource.local : TranslateSource.remote;
  }

  void set(TranslateSource value) {
    // Web / 移动端不允许切到需要本机运行时的来源（D-044）。
    if (!supportsLocalEngine && value.requiresLocalRuntime) return;
    state = value;
    persistTranslateSource(value.wire);
  }
}

/// 最近一次「启动引擎」失败的原因（null = 没有失败）。
///
/// 存在的唯一理由：让界面能显示**为什么**起不来，而不是只把按钮变灰。
final engineStartErrorProvider = NotifierProvider<EngineStartErrorNotifier, String?>(EngineStartErrorNotifier.new);

class EngineStartErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? message) => state = message;
}

final translateSourceProvider = NotifierProvider<TranslateSourceNotifier, TranslateSource>(TranslateSourceNotifier.new);

/// 引擎目录是否「看起来装过」。
///
/// 用 `.engine.json` 的存在与否做粗判：它由装配器在成功后被写入。
/// 🔴 这只是**粗判**，不是校验 —— 真正的部件级校验在设置页（`inspectEngine`）。
/// 引导页要的是「该显示未装配还是已装配」，不该为此起子进程。
final modelsInstalledProvider = Provider<bool>((ref) {
  // Web / 移动端没有本地引擎：直接返回 false，不去碰文件系统
  // （Web 上 `File.existsSync()` 会抛 Unsupported operation）。
  if (!supportsLocalEngine) return false;
  // 装配刚完成也要立刻反映，不能等下次冷启动。
  final install = ref.watch(engineInstallProvider);
  if (install.done) return true;
  return File(engineManifestPath(ref.watch(engineRootProvider))).existsSync();
});

/// 完整视图模型 —— UI 直接 watch 它（D-033：接上真实装配状态）。
final notReadyViewProvider = Provider<NotReadyView>((ref) {
  final source = ref.watch(translateSourceProvider);
  final install = ref.watch(engineInstallProvider);

  // 装配中：进度来自服务端；`percent` 为 null 时界面不画百分比（不编造）。
  if (install.running) {
    return NotReadyView(
      state: NotReadyState.downloading,
      engine: EngineRuntimeState.off,
      source: source,
      downloadProgress: install.percent,
      logs: install.logs,
    );
  }
  // 装配失败：把服务端日志直接交给日志组件。
  if (install.error != null) {
    return NotReadyView(
      state: NotReadyState.failed,
      engine: EngineRuntimeState.off,
      source: source,
      logs: install.logs,
    );
  }
  final base = deriveNotReadyView(
    source: source,
    status: null,
    modelsInstalled: ref.watch(modelsInstalledProvider),
    downloadProgress: null,
    logs: const [],
  );
  // 🔴 必须用真实引擎状态覆盖：derive 传的是 `status: null`，其 engine 恒为 off，
  // 会导致顶栏、侧栏圆点、队列横幅全部误报「未启动」。
  return NotReadyView(
    state: base.state,
    engine: ref.watch(engineStateProvider),
    source: base.source,
    downloadProgress: base.downloadProgress,
    failedPhase: base.failedPhase,
    logs: base.logs,
  );
});
