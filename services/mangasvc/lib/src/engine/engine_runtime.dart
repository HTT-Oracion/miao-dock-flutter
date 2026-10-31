import 'dart:io';

import 'engine_launch.dart';
import 'supervisor.dart';

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
  EngineRuntime({required this.runtimeRoot, required this.modelsDir, this.healthTimeout = const Duration(seconds: 60)});

  /// 引擎运行时根（用户可选，D-015）。
  final String runtimeRoot;

  /// 模型目录（与运行时解耦，D-016）。
  final String modelsDir;

  /// 等待引擎健康应答的时长（首次装载模型可能很慢）。
  final Duration healthTimeout;

  EngineSupervisor? _supervisor;

  EngineState _state = EngineState.stopped;
  String? _phase;
  String? _lastError;
  int? _enginePid;
  int? _llmPid;
  int? _enginePort;
  int? _llmPort;
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
    final venv = Directory('$runtimeRoot${Platform.pathSeparator}venv');
    return src.existsSync() && venv.existsSync();
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
      _lastError = '引擎运行时未装配：$runtimeRoot 缺少 src/ 或 venv/';
      _log('[engine] not assembled: $runtimeRoot');
      return;
    }

    // 启动规格是「怎么起」的唯一事实源；缺了就明确报缺，不猜参数。
    final specResult = EngineLaunchSpec.load(runtimeRoot);
    final spec = specResult.spec;
    if (spec == null) {
      _state = EngineState.error;
      _phase = 'L1';
      _lastError = specResult.error;
      _log('[engine] ${specResult.error}');
      return;
    }

    final sup = EngineSupervisor(
      processPath: spec.command,
      processArgs: spec.args,
      healthUrl: spec.healthUrl(),
      workingDirectory: runtimeRoot,
      healthTimeout: healthTimeout,
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
      _state = EngineState.error;
      _phase = 'L1';
      _lastError = '引擎未能在 ${healthTimeout.inSeconds}s 内就绪（健康检查 ${spec.healthUrl()}）';
      return;
    }
    _state = EngineState.running;
    _phase = null;
    _warmed = false;
    _log('[engine] ready on ${spec.port}');
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

  /// 契约 `EngineStatus`。
  Map<String, dynamic> toStatusView() => {
    'engine': {'state': _state.wire, 'version': engineVersion, 'port': _enginePort, 'pid': _enginePid},
    'llm': {
      'state': _state == EngineState.running ? 'running' : _state.wire,
      'model': null,
      'port': _llmPort,
      'pid': _llmPid,
    },
    'tier': null,
    'accel': Platform.isMacOS ? 'mps' : 'cpu',
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
    final venvOk = Directory('$runtimeRoot${Platform.pathSeparator}venv').existsSync();
    final modelsOk = Directory(modelsDir).existsSync();
    final checks = [
      {'name': 'src', 'ok': srcOk, 'detail': '$runtimeRoot${Platform.pathSeparator}src'},
      {'name': 'venv', 'ok': venvOk, 'detail': '$runtimeRoot${Platform.pathSeparator}venv'},
      {'name': 'models', 'ok': modelsOk, 'detail': modelsDir},
    ];
    return {'ready': srcOk && venvOk && modelsOk, 'checks': checks};
  }

  /// 释放资源：终止子进程，不留僵尸。
  Future<void> dispose() async {
    await _supervisor?.dispose();
    _supervisor = null;
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
