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

/// 远程翻译配置的本次会话校验状态。
enum RemoteVerificationState {
  unverified,
  checking,
  ready,
  failed;

  bool get isReady => this == ready;
}

/// 合成引擎与 LLM 的真实可翻译状态。
EngineRuntimeState deriveEngineGroupState(EngineRuntimeState engine, EngineRuntimeState llm) {
  if (engine.isReady && llm.isReady) return EngineRuntimeState.running;
  if (engine == EngineRuntimeState.starting || llm == EngineRuntimeState.starting) {
    return EngineRuntimeState.starting;
  }
  if (engine == EngineRuntimeState.failed || llm == EngineRuntimeState.failed) {
    return EngineRuntimeState.failed;
  }
  if (engine == EngineRuntimeState.stopping || llm == EngineRuntimeState.stopping) {
    return EngineRuntimeState.stopping;
  }
  return EngineRuntimeState.off;
}

/// 「能否翻译」的四色语义 —— 对应侧栏状态点（D-012）。
///
/// 🔴 为什么不再用「服务已启动」做标识：服务常驻后它永远是绿的，**没有信息量**，
/// 而且会误导（服务绿 ≠ 能翻译）。用户真正关心的是「我现在能不能翻译」。
enum ReadinessLevel {
  /// 绿：本地引擎与 LLM 均就绪，或远程配置已校验通过。
  ready,

  /// 黄：服务在，但引擎未启动。
  partial,

  /// 红：服务异常。
  broken,

  /// 灰：未配置（远程地址为空 / 来源未选）。
  unconfigured,
}

/// 远程校验失败的种类（**不携带文案**：中文由 UI 层查 ARB）。
enum RemoteVerifyIssue {
  /// 令牌或地址没填完整（本地校验就没过）。
  configIncomplete,

  /// 能连上，但对面引擎没就绪。
  engineNotReady,

  /// 探测本身失败（连不上 / 令牌错）。
  probeFailed,
}

/// 启动引导的完整视图模型。
@immutable
class NotReadyView {
  const NotReadyView({
    required this.state,
    required this.engine,
    required this.source,
    this.remoteVerification = RemoteVerificationState.unverified,
    this.remoteFailure,
    this.downloadProgress,
    this.failedPhase,
    this.logs = const [],
  });

  final NotReadyState state;
  final EngineRuntimeState engine;
  final TranslateSource source;
  final RemoteVerificationState remoteVerification;

  /// 远程校验失败的**结构化**信息（文案由 UI 层查 ARB）；成功或未校验为 null。
  final ({RemoteVerifyIssue kind, String? detail})? remoteFailure;

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
    if (!needsLocalEngine) {
      return remoteVerification.isReady ? ReadinessLevel.ready : ReadinessLevel.broken;
    }
    return engine.isReady ? ReadinessLevel.ready : ReadinessLevel.partial;
  }

  /// 是否处于「可以正常使用、只是不能翻译」的状态。
  ///
  /// 远程来源须先校验配置；其余看引擎与 LLM 是否都就绪。
  bool get canBrowse => state != NotReadyState.degraded;

  /// 是否可以开始翻译。
  bool get canTranslate =>
      state != NotReadyState.degraded && (needsLocalEngine ? engine.isReady : remoteVerification.isReady);

  NotReadyView copyWith({
    NotReadyState? state,
    EngineRuntimeState? engine,
    TranslateSource? source,
    RemoteVerificationState? remoteVerification,
    ({RemoteVerifyIssue kind, String? detail})? remoteFailure,
    double? downloadProgress,
    String? failedPhase,
    List<String>? logs,
  }) => NotReadyView(
    state: state ?? this.state,
    engine: engine ?? this.engine,
    source: source ?? this.source,
    remoteVerification: remoteVerification ?? this.remoteVerification,
    remoteFailure: remoteFailure ?? this.remoteFailure,
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
  RemoteVerificationState remoteVerification = RemoteVerificationState.unverified,
}) {
  // 远程来源不需要本机运行时，但必须由用户显式校验远程配置。
  if (!source.requiresLocalRuntime) {
    return NotReadyView(
      state: NotReadyState.installed,
      engine: EngineRuntimeState.off,
      source: source,
      remoteVerification: remoteVerification,
      logs: logs,
    );
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
  final runtimeState = deriveEngineGroupState(engineState, llmState);

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
