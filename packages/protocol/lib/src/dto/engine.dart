/// 健康检查与引擎契约 —— 对齐原项目 `HealthResponse` / `EngineStatus` / `ModelDownloadView`。
library;

/// `GET /health` 与 `GET /api/v1/health`。
class HealthResponse {
  const HealthResponse({
    required this.status,
    required this.service,
    required this.version,
    required this.apiVersion,
    required this.sidecar,
    required this.rootDir,
    required this.startedAt,
  });

  /// `ok` / `degraded` / `starting`。
  final String status;
  final String service;
  final String version;
  final String apiVersion;
  final SidecarInfo sidecar;
  final String rootDir;
  final DateTime startedAt;

  bool get isOk => status == 'ok';
}

/// sidecar 视图（9 字段契约的一部分）。
class SidecarInfo {
  const SidecarInfo({required this.state, this.port, this.engine});

  final String state;
  final int? port;
  final String? engine;
}

/// 服务五态 —— 与原项目 `ServiceState` 穷尽映射。
enum ServiceState {
  stopped('stopped'),
  starting('starting'),
  running('running'),
  stopping('stopping'),
  error('error');

  const ServiceState(this.wire);

  final String wire;

  static ServiceState parse(String value) {
    for (final s in ServiceState.values) {
      if (s.wire == value) return s;
    }
    return ServiceState.error;
  }
}

/// `GET /api/v1/engine/status`。
class EngineStatus {
  const EngineStatus({
    required this.engine,
    required this.llm,
    required this.accel,
    required this.warmed,
    required this.config,
    required this.models,
    required this.runtime,
    this.tier,
    this.rawStage,
  });

  final EngineProcess engine;
  final LlmProcess llm;

  /// 引擎分档；null = 尚未探测。
  final EngineTier? tier;

  final String accel;
  final bool warmed;
  final EngineConfig config;
  final ModelStatus models;
  final RuntimeProbe runtime;

  /// 引擎原始阶段名（`seq N: 原话`），只给诊断看，不进插件契约。
  final String? rawStage;
}

/// 引擎进程态。
class EngineProcess {
  const EngineProcess({required this.state, required this.version, this.port, this.pid});

  final String state;
  final String version;
  final int? port;
  final int? pid;
}

/// LLM 进程态。
class LlmProcess {
  const LlmProcess({required this.state, this.model, this.port, this.pid});

  final String state;
  final String? model;
  final int? port;
  final int? pid;
}

/// 引擎分档。
class EngineTier {
  const EngineTier({required this.name, required this.reason});

  final String name;
  final String reason;
}

/// 引擎配置（只声明前端真正读到的字段）。
class EngineConfig {
  const EngineConfig({
    required this.translator,
    required this.targetLang,
    required this.detector,
    required this.ocr,
    required this.inpainter,
    this.fromLang,
    this.detectionSize,
  });

  final String translator;

  /// null = 基线不固定源语言，逐任务按方向下发。
  final String? fromLang;

  final String targetLang;
  final String detector;

  /// null = 未下发（引擎用自身默认），与「下发了 2048」不是一回事。
  final int? detectionSize;

  final String ocr;
  final String inpainter;
}

/// 模型状态。
class ModelStatus {
  const ModelStatus({required this.ready, required this.sets});

  final bool ready;
  final Map<String, ModelSet> sets;
}

/// 一组模型。
class ModelSet {
  const ModelSet({required this.entries, required this.ready});

  /// 条目数；0 = 当前平台没有这一档（**不算缺失**）。
  final int entries;
  final bool ready;
}

/// 运行时就绪探测。
class RuntimeProbe {
  const RuntimeProbe({required this.ready, required this.checks});

  final bool ready;
  final List<RuntimeCheck> checks;
}

/// 单项探测结果。
class RuntimeCheck {
  const RuntimeCheck({required this.name, required this.ok, this.detail});

  final String name;
  final bool ok;
  final String? detail;
}

/// 模型下载视图 —— 🔴 `error` 态必须在：非零退出且盘上无 `.part` 时后端写的就是它。
class ModelDownloadView {
  const ModelDownloadView({
    required this.state,
    required this.running,
    required this.timedOut,
    required this.tail,
    required this.rootDir,
    required this.manifest,
    required this.runner,
    required this.runnerExists,
    this.startedAt,
    this.finishedAt,
    this.exitCode,
    this.percent,
  });

  /// `idle` / `running` / `interrupted` / `done` / `failed` / `error`。
  final String state;

  final bool running;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? exitCode;
  final bool timedOut;

  /// 子进程输出尾巴 —— **原样转发**，不做结构化解析。
  final List<String> tail;

  final String rootDir;
  final String manifest;

  /// 下载/校验执行体路径；[runnerExists] 为 false 时按钮要变灰。
  final String runner;
  final bool runnerExists;

  /// 结构化进度（来自 `--progress-log`）；null = 无真实来源，**不要编造**。
  final double? percent;
}
