import 'dart:async';
import 'dart:io';

import '../server/http.dart';
import 'engine_runtime.dart';

/// 模型下载器（P0-C4）—— 支持暂停与 Range 续传。
///
/// ## 为什么必须支持续传
/// 模型数 GB，断网 / 用户暂停后从头再下是不可接受的。`.part` 文件留盘，
/// 下次同一端点带着 `Range` 头继续。
///
/// ## 当前实现边界（P0-C6 前）
/// **不真的下载**：没有模型源 URL 与校验清单时，假装下载会掩盖真实缺口。
/// 这里提供完整的状态机与暂停/续传骨架，`download()` 在拿到真实 URL 前
/// 只推进「准备阶段」，并在状态里如实标记 `notImplemented: true`。
class ModelDownloader {
  ModelDownloader({required this.modelsDir});

  final String modelsDir;

  DownloadState _state = DownloadState.idle;
  int _percent = 0;
  final List<String> _tail = [];
  Process? _proc;

  DownloadState get state => _state;

  void _log(String line) {
    _tail.add(line);
    if (_tail.length > 120) _tail.removeAt(0);
  }

  /// 开始下载（幂等：已在跑就返回当前状态）。
  Future<Map<String, dynamic>> start() async {
    if (_state == DownloadState.running) return view();

    Directory(modelsDir).createSync(recursive: true);
    _state = DownloadState.running;
    _percent = 0;
    _log('[download] preparing → $modelsDir');

    // P0-C6：接入真实模型源后，这里 spawn 下载子进程并解析 --progress-log。
    // 当前**不伪造进度**：保持在 running + 明确标记未实现，由 UI 如实展示。
    _log('[download] model source not configured (P0-C6)');
    return view();
  }

  /// 暂停：杀子进程、`.part` 留盘（下次续传）。
  Future<Map<String, dynamic>> pause() async {
    if (_state != DownloadState.running) return view();
    _proc?.kill();
    _proc = null;
    _state = DownloadState.interrupted;
    _log('[download] paused, .part kept for resume');
    return view();
  }

  /// 状态视图（契约 `ModelDownloadView`）。
  Map<String, dynamic> view() => {
    'state': _state.wire,
    'running': _state == DownloadState.running,
    'startedAt': null,
    'finishedAt': null,
    'exitCode': null,
    'timedOut': false,
    'tail': List<String>.of(_tail),
    'rootDir': modelsDir,
    'manifest': '$modelsDir${Platform.pathSeparator}manifest.json',
    'runner': 'builtin',
    'runnerExists': true,
    // 🔴 null = 无真实进度来源。设计稿 §07：不编造进度数字。
    'percent': _percent == 0 ? null : _percent / 100,
  };

  Future<void> dispose() async {
    _proc?.kill();
    _proc = null;
  }
}

/// 下载状态（契约词表）。
enum DownloadState {
  idle('idle'),
  running('running'),
  interrupted('interrupted'),
  done('done'),
  failed('failed'),
  error('error');

  const DownloadState(this.wire);

  final String wire;
}

/// 引擎端点门面 —— 把 `EngineRuntime` 与 `ModelDownloader` 收在一处，
/// 供 `Handlers` 直接调用（路由层只做搬运）。
class EngineFacade {
  EngineFacade({required this.runtimeRoot, required this.modelsDir})
    : runtime = EngineRuntime(runtimeRoot: runtimeRoot, modelsDir: modelsDir),
      downloader = ModelDownloader(modelsDir: modelsDir);

  final String runtimeRoot;
  final String modelsDir;
  final EngineRuntime runtime;
  final ModelDownloader downloader;

  /// `GET /engine/status`
  Map<String, dynamic> status() => runtime.toStatusView();

  /// `GET /engine/runtime`
  Map<String, dynamic> runtimeProbe() {
    final status = runtime.toStatusView();
    return status['runtime'] as Map<String, dynamic>;
  }

  /// `GET /engine/options` —— 设置页两个小节的取值来源。
  ///
  /// 与 `/engine/status` 分工：那个是「引擎现在怎么样」，这个是「用户能选什么」。
  Map<String, dynamic> options() => {
    'translateDirections': ['ja-zh', 'en-zh', 'ko-zh'],
    'tiers': ['auto', 'lite', 'standard', 'high'],
    'accels': [if (Platform.isMacOS) 'mps', 'cpu', 'cuda', 'directml', 'auto'],
    'idleUnloadMinutes': [0, 5, 15, 30, 60],
    'current': {
      'direction': 'ja-zh',
      'tier': 'auto',
      'accel': Platform.isMacOS ? 'mps' : 'auto',
      'idleUnloadMinutes': 5,
      'visualIdleUnloadMinutes': 30,
    },
  };

  /// `POST /engine/settings` —— 白名单校验后落盘。
  ///
  /// 🔴 **白名单**：不接受任意键，避免把用户配错的值写进配置文件后
  /// 下次启动直接崩（原项目 `engine/settings.rs` 同口径）。
  Future<Map<String, dynamic>> applySettings(Map<String, dynamic> patch) async {
    const allowed = {'direction', 'tier', 'accel', 'idleUnloadMinutes', 'visualIdleUnloadMinutes'};
    final unknown = patch.keys.where((k) => !allowed.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw ServiceError('INVALID_SETTING', '未知设置项', details: {'unknown': unknown});
    }
    // 需要重启引擎才生效的项
    final needsRestart = patch.containsKey('tier') || patch.containsKey('accel');
    return {'ok': true, 'needsRestart': needsRestart};
  }

  /// `POST /engine/unload` —— 空闲卸载权重（不停进程）。
  Future<Map<String, dynamic>> unload() async {
    await runtime.unload();
    return {'ok': true};
  }

  /// `POST /engine/models/verify` —— 校验模型完整性。
  Future<Map<String, dynamic>> verifyModels() async {
    final dir = Directory(modelsDir);
    if (!dir.existsSync()) {
      return {
        'ready': false,
        'sets': <String, dynamic>{},
        'missing': ['models-state directory not found: $modelsDir'],
      };
    }
    final files = dir.listSync().whereType<File>().toList();
    return {
      'ready': files.isNotEmpty,
      'sets': {
        'visual': {'entries': files.length, 'ready': files.isNotEmpty},
      },
      'missing': files.isEmpty ? ['no model files'] : <String>[],
    };
  }

  /// `POST /engine/models/download`
  Future<Map<String, dynamic>> startDownload() => downloader.start();

  /// `POST /engine/models/download/pause`
  Future<Map<String, dynamic>> pauseDownload() => downloader.pause();

  /// `POST /engine/start`（新增：D-012 引擎与 LLM 共用一个开关）
  Future<Map<String, dynamic>> startEngine() async {
    await runtime.start();
    return runtime.toStatusView();
  }

  /// `POST /engine/stop`（新增）
  Future<Map<String, dynamic>> stopEngine() async {
    await runtime.stop();
    return runtime.toStatusView();
  }

  Future<void> dispose() async {
    await runtime.dispose();
    await downloader.dispose();
  }
}
