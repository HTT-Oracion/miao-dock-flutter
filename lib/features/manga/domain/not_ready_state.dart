import 'package:flutter/foundation.dart';
import 'package:protocol/protocol.dart';

/// 启动引导的状态机 —— 对应 D-012。
///
/// ## 为什么是「六态」而不是设计稿的「三页」
/// 设计稿把「欢迎 / 下载 / 服务状态」做成三个独立页面，但它们本质是**同一件事的
/// 不同阶段**。合并成一张卡的六态后：用户始终在「漫画翻译」语境里，侧栏一直在，
/// 随时能去设置排查。
///
/// ## 与服务层的关系
/// 服务（L0）**常驻**，几乎永远 ready。真正会变的是引擎（L1）与大模型（L2）——
/// 两者**共用一个开关**，所以状态机只建模「引擎组」而非两个独立进程。
enum NotReadyState {
  /// 引擎与模型未下载（首次使用）。
  uninstalled,

  /// 正在下载引擎组件与模型。
  downloading,

  /// 已下载、未启动。
  installed,

  /// 正在拉起引擎 + 大模型两个进程。
  starting,

  /// 启动失败（进程起来又退了 / 装载模型失败）。
  failed,

  /// 服务本身异常（L0 挂了）—— 这是唯一会挡住整个漫画模块的形态。
  degraded;

  /// 是否需要一个「主操作」按钮。
  bool get hasPrimaryAction => this != starting;

  /// 是否是「可用但未就绪」—— 此时浏览库 / 看已译 / 投放都仍可用。
  bool get isSoftBlocking => this == uninstalled || this == downloading || this == installed;

  /// 是否必须整块提示（不能只给一条横幅）。
  bool get needsFullCard => this == uninstalled || this == downloading || this == starting || this == failed;
}

/// 翻译来源 —— 三选一（D-012）。
///
/// 从原项目的两种（本地引擎 / 在线 API）重构而来：
///   · [local]    引擎 + LLM 均在本机，全程不出网；
///   · [llm]      引擎在本机（图片仍本机处理），LLM 换成云端 API；
///   · [remote]   本机不下载任何引擎与 LLM，整条链路交给其他端。
///
/// 🔴 **移动端只有 [remote]**：移动端不跑本地服务（AGENTS §2 / D-001）。
enum TranslateSource {
  local('local', true, true, true),
  llm('llm', true, true, true),
  remote('remote', false, false, true);

  const TranslateSource(this.wire, this.needsEngine, this.needsLlm, this.hidesOnRemote);

  /// 契约字面量（服务端 `/translate/settings` 用）。
  final String wire;

  /// 是否需要本机翻译引擎（图片检测 / OCR / 抹字）。
  final bool needsEngine;

  /// 是否需要本机大模型。
  final bool needsLlm;

  /// 是否可以用在「远程」场景。
  final bool hidesOnRemote;

  /// 是否需要下载引擎组件（决定是否走 uninstalled / downloading 态）。
  bool get requiresLocalRuntime => needsEngine || needsLlm;

  static TranslateSource parse(String value) {
    for (final s in TranslateSource.values) {
      if (s.wire == value) return s;
    }
    // 未知值不静默降级成 local：那会让「配错了」看起来像「正常用本机」。
    throw ArgumentError('未知翻译来源：$value');
  }
}

/// 引擎组的生命周期（L1 + L2 合并）。
enum EngineRuntimeState {
  off,
  starting,
  running,
  stopping,
  failed;

  bool get isReady => this == running;

  static EngineRuntimeState fromWire(String? value) => switch (value) {
    'running' => EngineRuntimeState.running,
    'starting' => EngineRuntimeState.starting,
    'stopping' => EngineRuntimeState.stopping,
    'failed' || 'error' => EngineRuntimeState.failed,
    _ => EngineRuntimeState.off,
  };
}

/// 「能否翻译」的四色语义 —— 对应侧栏状态点（D-012）。
///
/// 🔴 为什么不再用「服务已启动」做标识：服务常驻后它永远是绿的，**没有信息量**，
/// 而且会误导（服务绿 ≠ 能翻译）。用户真正关心的是「我现在能不能翻译」。
enum ReadinessLevel {
  /// 绿：服务在且引擎就绪（或来源是远程且地址已配）。
  ready,

  /// 黄：服务在，但引擎未启动。
  partial,

  /// 红：服务异常。
  broken,

  /// 灰：未配置（远程地址为空 / 来源未选）。
  unconfigured,
}

/// 启动引导的完整视图模型。
@immutable
class NotReadyView {
  const NotReadyView({
    required this.state,
    required this.engine,
    required this.source,
    this.downloadProgress,
    this.failedPhase,
    this.logs = const [],
  });

  final NotReadyState state;
  final EngineRuntimeState engine;
  final TranslateSource source;

  /// 下载进度（0–1）；null = 无真实来源（**不编造百分比**）。
  final double? downloadProgress;

  /// 启动失败卡在哪个阶段（L1 环境 / L2 模型）。
  final String? failedPhase;

  /// 最近日志（用于 LogBox）。
  final List<String> logs;

  /// 是否需要引擎（远程来源不需要）。
  bool get needsLocalEngine => source.requiresLocalRuntime;

  /// 侧栏状态点语义。
  ReadinessLevel get readiness {
    if (state == NotReadyState.degraded) return ReadinessLevel.broken;
    if (!needsLocalEngine) return ReadinessLevel.ready;
    return engine.isReady ? ReadinessLevel.ready : ReadinessLevel.partial;
  }

  /// 是否处于「可以正常使用、只是不能翻译」的状态。
  ///
  /// 远程来源永远可用（翻译交给其他端）；其余看引擎是否就绪。
  bool get canBrowse => state != NotReadyState.degraded;

  /// 是否可以开始翻译。
  bool get canTranslate => state != NotReadyState.degraded && (!needsLocalEngine || engine.isReady);

  NotReadyView copyWith({
    NotReadyState? state,
    EngineRuntimeState? engine,
    TranslateSource? source,
    double? downloadProgress,
    String? failedPhase,
    List<String>? logs,
  }) => NotReadyView(
    state: state ?? this.state,
    engine: engine ?? this.engine,
    source: source ?? this.source,
    downloadProgress: downloadProgress ?? this.downloadProgress,
    failedPhase: failedPhase ?? this.failedPhase,
    logs: logs ?? this.logs,
  );
}

/// 从服务端 `EngineStatus` 推导视图状态。
///
/// 纯函数（不碰 Riverpod / UI），便于单测与反证。
NotReadyView deriveNotReadyView({
  required TranslateSource source,
  required EngineStatus? status,
  required bool modelsInstalled,
  double? downloadProgress,
  List<String> logs = const [],
}) {
  // 远程来源：本机不需要任何运行时，直接可用。
  if (!source.requiresLocalRuntime) {
    return NotReadyView(state: NotReadyState.installed, engine: EngineRuntimeState.running, source: source, logs: logs);
  }

  if (!modelsInstalled) {
    return NotReadyView(
      state: downloadProgress == null ? NotReadyState.uninstalled : NotReadyState.downloading,
      engine: EngineRuntimeState.off,
      source: source,
      downloadProgress: downloadProgress,
      logs: logs,
    );
  }

  final engineState = EngineRuntimeState.fromWire(status?.engine.state);
  final llmState = EngineRuntimeState.fromWire(status?.llm.state);
  // 🔴 引擎组就绪 = 两个进程都 running。只判 engine 会让「LLM 没起来」被当成就绪。
  final bothRunning = engineState == EngineRuntimeState.running && llmState == EngineRuntimeState.running;
  final anyStarting = engineState == EngineRuntimeState.starting || llmState == EngineRuntimeState.starting;
  final anyFailed = engineState == EngineRuntimeState.failed || llmState == EngineRuntimeState.failed;

  final runtimeState = bothRunning
      ? EngineRuntimeState.running
      : anyStarting
      ? EngineRuntimeState.starting
      : anyFailed
      ? EngineRuntimeState.failed
      : EngineRuntimeState.off;

  final state = switch (runtimeState) {
    EngineRuntimeState.running => NotReadyState.installed,
    EngineRuntimeState.starting => NotReadyState.starting,
    EngineRuntimeState.failed => NotReadyState.failed,
    _ => NotReadyState.installed,
  };

  return NotReadyView(
    state: state,
    engine: runtimeState,
    source: source,
    downloadProgress: downloadProgress,
    failedPhase: runtimeState == EngineRuntimeState.failed ? status?.rawStage : null,
    logs: logs,
  );
}
