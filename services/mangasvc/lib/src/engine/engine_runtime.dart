import 'dart:io';

import 'engine_launch.dart';
import 'supervisor.dart';

/// llama-server 可能在 `/health` 已返回 200 后才报告 Metal 后端不可用。
bool shouldFallbackLlmToCpu(Iterable<String> logs) =>
    logs.any((line) => line.contains('Insufficient Memory') || line.contains('backend is in error state'));

/// 引擎状态机（P0-C1）—— L1 翻译引擎 + L2 大模型，**共用一个开关**（D-012）。
///
/// ## 五态（与原项目 `ServiceState` 同构）
/// ```
/// stopped → starting → running → stopping → stopped
///                ↓
///              error
/// ```
///
/// ## 关键约定
/// - `pid` 归属：引擎由本进程 spawn，能拿到 pid；LLM 也由本进程管，同样有 pid。
/// - `warmed`：HTTP 真应答过才算「预热完成」——**不拿进程存活当预热**。
/// - 状态只在**真实事件**后推进，不预置「假装 running」。
class EngineRuntime {
  EngineRuntime({
    required this.runtimeRoot,
    required this.modelsDir,
    this.healthTimeout = const Duration(seconds: 60),
    this.probeBudget = const Duration(seconds: 90),
  });

  /// L2 执行器探测的**总预算**（默认 90s：模型首次装载可能很慢）。
  final Duration probeBudget;

  /// 引擎运行时根（用户可选，D-015）。
  final String runtimeRoot;

  /// 模型目录（与运行时解耦，D-016）。
  final String modelsDir;

  /// 等待引擎健康应答的时长（首次装载模型可能很慢）。
  final Duration healthTimeout;

  EngineSupervisor? _supervisor;
  EngineSupervisor? _llmSupervisor;

  EngineState _state = EngineState.stopped;
  String? _phase;
  String? _lastError;
  int? _enginePid;
  int? _llmPid;
  int? _enginePort;

  /// 引擎端口（未启动为 null）。队列执行器要用它建客户端。
  int? get port => _enginePort;
  int? _llmPort;
  String? _llmModel;
  bool _llmCpuFallback = false;
  bool _warmed = false;
  final DateTime startedAt = DateTime.now().toUtc();

  /// 最近阶段日志（最多 120 行）。
  final List<String> _stageLog = [];

  EngineState get state => _state;

  void _log(String line) {
    _stageLog.add(line);
    if (_stageLog.length > 120) _stageLog.removeAt(0);
  }

  /// 装好的引擎版本；未装配返回 null。
  ///
  /// 读 `src/version.txt`（安装时写入）。**不猜版本号**：没有就是没有。
  String? get engineVersion {
    final f = File('$runtimeRoot${Platform.pathSeparator}src${Platform.pathSeparator}version.txt');
    if (!f.existsSync()) return null;
    try {
      return f.readAsStringSync().trim();
    } catch (_) {
      return null;
    }
  }

  /// 运行时是否装配齐全（**浅检查**；完整校验见 P0-F6d）。
  bool get isAssembled {
    final src = Directory('$runtimeRoot${Platform.pathSeparator}src');
    // 新布局（D-027）：`python/` 是自带解释器，不再是 `venv/`。
    final python = Directory('$runtimeRoot${Platform.pathSeparator}python');
    final legacyVenv = Directory('$runtimeRoot${Platform.pathSeparator}venv');
    return src.existsSync() && (python.existsSync() || legacyVenv.existsSync());
  }

  /// 启动引擎 + 大模型。
  ///
  /// 真实进程拉起在 P0-C6（需 Python / llama-server 二进制）。
  /// 当前：**装配不齐就明确报错**，装配齐了也**不假装 running** ——
  /// 让上层如实看到 `error` 或停在 `starting`，由 P0-C6 补真启动。
  Future<void> start() async {
    if (_state == EngineState.starting || _state == EngineState.running) return;
    _state = EngineState.starting;
    _phase = 'L1';
    _lastError = null;
    _log('[engine] starting…');

    if (!isAssembled) {
      _state = EngineState.error;
      _phase = 'L1';
      _lastError = '引擎运行时未装配：$runtimeRoot 缺少 src/ 或 python/';
      _log('[engine] not assembled: $runtimeRoot');
      return;
    }

    // 启动规格是「怎么起」的唯一事实源；缺了就明确报缺，不猜参数。
    final specResult = EngineLaunchSpec.load(runtimeRoot);
    final configuredSpec = specResult.spec;
    if (configuredSpec == null) {
      _state = EngineState.error;
      _phase = 'L1';
      _lastError = specResult.error;
      _log('[engine] ${specResult.error}');
      return;
    }

    // 先启动 LLM，才能把它的真实动态端口注入 executor；否则 executor 会回退到
    // keys.py 的 8080，连上另一个残留进程。引擎端口也必须在 LLM 已占端口后再选，
    // 否则系统可能把 L1+1 分给 LLM，导致 executor 无法 bind。
    _phase = 'L3';
    final llm = await _startLlm();
    final selectedPort = await _selectEnginePort(configuredSpec.port);
    if (selectedPort == null) {
      await _stopLlm();
      _state = EngineState.error;
      _phase = 'L1';
      _lastError = '找不到连续两个空闲端口，无法启动翻译引擎';
      _log('[engine] no free consecutive ports');
      return;
    }
    final spec = configuredSpec.withPort(selectedPort);
    if (selectedPort != configuredSpec.port) {
      _log(
        '[engine] configured ports ${configuredSpec.port}/${configuredSpec.port + 1} occupied; use $selectedPort/${selectedPort + 1}',
      );
    }
    final engineEnvironment = Map<String, String>.of(spec.env);
    final llmPort = _llmPort;
    if (llm != null && llmPort != null) {
      engineEnvironment['SAKURA_API_BASE'] = 'http://127.0.0.1:$llmPort/v1';
    }
    _phase = 'L1';

    final sup = EngineSupervisor(
      processPath: spec.command,
      processArgs: spec.args,
      healthUrl: spec.healthUrl(),
      workingDirectory: runtimeRoot,
      environment: engineEnvironment,
      healthTimeout: healthTimeout,
      // 🔴 引擎输出必须落盘：executor 崩溃的 traceback 只打在 stdout/stderr，
      // 没有文件现场，Broken pipe 这类问题永远查不到根因（D-133）。
      logFile: File('$runtimeRoot${Platform.pathSeparator}engine.log'),
    );
    _supervisor = sup;
    _enginePort = spec.port;

    final healthy = await sup.start();
    _enginePid = sup.pid;
    // 监督器的输出就是「引擎这段时间在做什么」，直接进阶段日志。
    for (final line in sup.log) {
      _log(line);
    }
    if (!healthy) {
      await _stopLlm();
      _state = EngineState.error;
      _phase = 'L1';
      _lastError = '引擎未能在 ${healthTimeout.inSeconds}s 内就绪（健康检查 ${spec.healthUrl()}）';
      return;
    }

    // ── L2：翻译执行器（main.py 自己 spawn 的 port+1 子进程）──────────
    // 启动成功 ≠ 执行器就绪：Broken pipe / 锁死都发生在这一层，
    // 不在这里探，用户要等到「点翻译」才炸。
    _phase = 'L2';
    final executorReady = await _waitExecutorReady(spec.port);
    if (!executorReady) {
      await sup.stop();
      await _stopLlm();
      _state = EngineState.error;
      _phase = 'L2';
      _lastError = '翻译执行器未就绪（${spec.port + 1}；进程可能仍在加载模型）';
      _log('[engine] L2 executor not ready on ${spec.port + 1}');
      return;
    }
    _log('[engine] L2 executor ready on ${spec.port + 1}');

    if (llm == null) {
      // LLM 没起来**不是**整个引擎失败：OCR/检测仍可用，
      // 但翻译会失败 —— 状态保持 running 并明确标注，让上层引导补模型。
      _state = EngineState.running;
      _phase = 'L3';
      _lastError = '大模型后端未就绪（缺 llama-server 或模型权重），翻译不可用';
      _log('[engine] L3 llm backend missing — translation unavailable');
      return;
    }
    _phase = null;
    _state = EngineState.running;
    _warmed = false;
    _log('[engine] ready on ${spec.port}（llm on $_llmPort）');
  }

  /// 等执行器（port+1）就绪：`manga_translator shared` 起来后才有 /openapi.json。
  Future<bool> _waitExecutorReady(int enginePort) async {
    final deadline = DateTime.now().add(probeBudget);
    final url = 'http://127.0.0.1:${enginePort + 1}/openapi.json';
    while (DateTime.now().isBefore(deadline)) {
      if (await EngineSupervisor.probeHealth(url, timeout: const Duration(seconds: 2))) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// L1 与 L2 固定使用相邻端口；启动前必须同时空闲，不能把旧进程的 200 当成本次就绪。
  Future<int?> _selectEnginePort(int preferred) async {
    if (await _portPairAvailable(preferred)) return preferred;
    for (var i = 0; i < 30; i++) {
      final first = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final candidate = first.port;
      if (candidate >= 65535) {
        await first.close();
        continue;
      }
      ServerSocket? second;
      try {
        second = await ServerSocket.bind(InternetAddress.loopbackIPv4, candidate + 1);
        return candidate;
      } on SocketException {
        // 下一轮重新让系统分配候选端口。
      } finally {
        await second?.close();
        await first.close();
      }
    }
    return null;
  }

  Future<bool> _portPairAvailable(int port) async {
    if (port >= 65535) return false;
    ServerSocket? first;
    ServerSocket? second;
    try {
      first = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      second = await ServerSocket.bind(InternetAddress.loopbackIPv4, port + 1);
      return true;
    } on SocketException {
      return false;
    } finally {
      await second?.close();
      await first?.close();
    }
  }

  /// 挑一个系统分发的空闲端口（绑定后立即释放——存在竞态，可接受）。
  Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// 启动 LLM 后端（llama-server + Sakura 权重）。
  ///
  /// 返回 null = 后端不可用（缺二进制或缺权重）——**如实返回**，
  /// 不假装启动成功让用户等到翻译时才炸。
  /// 成功则记录 [_llmPort]/[_llmPid] 并把 `SAKURA_API_BASE` 指向它。
  Future<EngineSupervisor?> _startLlm() async {
    _llmCpuFallback = false;
    final sep = Platform.pathSeparator;
    // 🔴 二进制与权重的候选路径要覆盖两种实际布局：
    // - 安装器产物：`bin/llama/llama-b11417/llama-server` + `models/sakura/*.gguf`
    // - 手动引擎目录（实测）：`bin/llama/llama-server` + `llm/*.gguf`
    // 只认一种会让 L3 永远「缺文件」—— 即便用户的引擎是完整的（D-136 实锤）。
    final llamaCandidates = [
      '$runtimeRoot${sep}bin${sep}llama${sep}llama-b11417${sep}llama-server',
      '$runtimeRoot${sep}bin${sep}llama${sep}llama-server',
    ];
    File? llama;
    for (final path in llamaCandidates) {
      final f = File(path);
      if (f.existsSync()) {
        llama = f;
        break;
      }
    }
    if (llama == null) {
      _log('[engine] L3 缺 llama-server：试过 ${llamaCandidates.join(' , ')}');
      return null;
    }
    final modelCandidates = ['$runtimeRoot${sep}models${sep}sakura', '$runtimeRoot${sep}llm'];
    File? gguf;
    for (final dirPath in modelCandidates) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync()) {
        if (f is File && f.path.endsWith('.gguf')) {
          gguf = f;
          break;
        }
      }
      if (gguf != null) break;
    }
    if (gguf == null) {
      _log('[engine] L3 缺 Sakura 权重：试过 ${modelCandidates.join(' , ')}（到设置页「下载模型」补齐）');
      return null;
    }

    final port = await _freePort();
    EngineSupervisor supervisorFor(int gpuLayers) => EngineSupervisor(
      processPath: llama!.path,
      processArgs: ['-m', gguf!.path, '--port', '$port', '-c', '4096', '-ngl', '$gpuLayers'],
      healthUrl: 'http://127.0.0.1:$port/health',
      healthTimeout: const Duration(seconds: 60),
      logFile: File('$runtimeRoot${Platform.pathSeparator}llama.log'),
    );

    var sup = supervisorFor(99);
    var ok = await sup.start();
    for (final line in sup.log) {
      _log('[llama] $line');
    }
    final metalOutOfMemory = shouldFallbackLlmToCpu(sup.log);
    if (ok && metalOutOfMemory) {
      _log('[engine] L3 Metal 显存不足，改用 CPU 重试');
      await sup.stop();
      sup = supervisorFor(0);
      ok = await sup.start();
      _llmCpuFallback = ok;
      for (final line in sup.log) {
        _log('[llama-cpu] $line');
      }
    }
    if (!ok) {
      await sup.stop();
      return null;
    }
    _llmSupervisor = sup;
    _llmPort = port;
    _llmPid = sup.pid;
    _llmModel = gguf.uri.pathSegments.last;
    _log('[engine] L3 llm ready on $port（$_llmModel）');
    return sup;
  }

  Future<void> _stopLlm() async {
    final supervisor = _llmSupervisor;
    if (supervisor != null) await supervisor.stop();
    _llmSupervisor = null;
    _llmPid = null;
    _llmPort = null;
    _llmModel = null;
    _llmCpuFallback = false;
  }

  /// 停止（主动停止：监督器不会把它当崩溃重启）。
  Future<void> stop() async {
    if (_state == EngineState.stopped) return;
    _state = EngineState.stopping;
    _log('[engine] stopping…');
    final sup = _supervisor;
    if (sup != null) {
      await sup.stop();
      for (final line in sup.log) {
        _log(line);
      }
      _supervisor = null;
    }
    await _stopLlm();
    _state = EngineState.stopped;
    _phase = null;
    _enginePid = null;
    _llmPid = null;
    _enginePort = null;
    _llmPort = null;
    _warmed = false;
    _log('[engine] stopped');
  }

  /// 空闲卸载（释放显存）：只卸载权重，不停进程。
  Future<void> unload() async {
    // P0-C6：调 llama-server 的卸载端点。
    _warmed = false;
    _log('[engine] unloaded weights');
  }

  /// 测试专用：跳过真实进程把状态置为 running（L3 语义断言用）。
  void markRunningForTest() {
    _state = EngineState.running;
  }

  /// 契约 `EngineStatus`。
  Map<String, dynamic> toStatusView() => {
    'engine': {'state': _state.wire, 'version': engineVersion, 'port': _enginePort, 'pid': _enginePid},
    'llm': {
      // 🔴 LLM 状态**不能**照抄引擎整体状态：L3 缺权重时引擎仍是 running
      // （OCR 可用），但翻译不可用 —— 照抄会让 UI 以为全部就绪（D-134 遗留）。
      'state': _llmPid != null ? 'running' : (_state == EngineState.error ? 'failed' : 'off'),
      'model': _llmModel,
      'port': _llmPort,
      'pid': _llmPid,
    },
    'tier': null,
    'accel': Platform.isMacOS && !_llmCpuFallback ? 'mps' : 'cpu',
    'warmed': _warmed,
    'config': {
      'translator': 'manga-image-translator',
      'fromLang': null,
      'targetLang': 'zh',
      'detector': 'default',
      'detectionSize': null,
      'ocr': 'default',
      'inpainter': 'default',
    },
    'models': _modelsView(),
    'runtime': _runtimeView(),
    'stage': _phase,
    'lastError': _lastError,
    'recentStageLog': List<String>.of(_stageLog),
  };

  /// 模型就绪视图。
  Map<String, dynamic> _modelsView() {
    final dir = Directory(modelsDir);
    final exists = dir.existsSync();
    final entries = exists ? dir.listSync().whereType<File>().length : 0;
    final ready = exists && entries > 0;
    return {
      'ready': ready,
      'sets': {
        'visual': {'entries': entries, 'ready': ready},
        'llm': {'entries': ready ? 1 : 0, 'ready': ready},
      },
    };
  }

  /// 运行时就绪探测（逐项独立报真伪）。
  Map<String, dynamic> _runtimeView() {
    final srcOk = Directory('$runtimeRoot${Platform.pathSeparator}src').existsSync();
    final pythonOk =
        Directory('$runtimeRoot${Platform.pathSeparator}python').existsSync() ||
        Directory('$runtimeRoot${Platform.pathSeparator}venv').existsSync();
    // 模型在 `src/models`（D-031），不在 `<engine>/models`。
    // 两套布局都认：新布局模型在 `src/models`（D-031），旧布局在 `<engine>/models`。
    final modelsOk =
        Directory('$runtimeRoot${Platform.pathSeparator}src${Platform.pathSeparator}models').existsSync() ||
        Directory(modelsDir).existsSync();
    final checks = [
      {'name': 'src', 'ok': srcOk, 'detail': '$runtimeRoot${Platform.pathSeparator}src'},
      {'name': 'python', 'ok': pythonOk, 'detail': '$runtimeRoot${Platform.pathSeparator}python'},
      {'name': 'models', 'ok': modelsOk, 'detail': modelsDir},
    ];
    return {'ready': srcOk && pythonOk && modelsOk, 'checks': checks};
  }

  /// 释放资源：终止子进程，不留僵尸。
  Future<void> dispose() async {
    await _supervisor?.dispose();
    _supervisor = null;
    await _stopLlm();
  }
}

/// 引擎五态（契约词表）。
enum EngineState {
  stopped('stopped'),
  starting('starting'),
  running('running'),
  stopping('stopping'),
  error('error');

  const EngineState(this.wire);

  final String wire;
}
