import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:protocol/protocol.dart';

import '../server/http.dart';
import 'engine_deps.dart';
import 'engine_install.dart';
import 'engine_client.dart';
import 'engine_runtime.dart';
import 'model_download.dart' as dl;

/// 模型下载协调器（P0-C4 + C6b 接线）—— 按 manifest 逐个文件真实下载。
///
/// ## 为什么必须支持续传
/// 模型数 GB，断网 / 用户暂停后从头再下是不可接受的。`.part` 文件留盘，
/// 下次同一端点带着 `Range` 头继续。
///
/// ## 当前实现边界（P0-C6 前）
/// **不真的下载**：没有模型源 URL 与校验清单时，假装下载会掩盖真实缺口。
/// 这里提供完整的状态机与暂停/续传骨架，`download()` 在拿到真实 URL 前
/// 只推进「准备阶段」，并在状态里如实标记 `notImplemented: true`。
class ModelDownloadCoordinator {
  ModelDownloadCoordinator({required this.modelsDir}) : _downloader = dl.ModelDownloader(modelsDir: modelsDir);

  final String modelsDir;

  DownloadState _state = DownloadState.idle;
  int _percent = 0;
  int _total = 0;
  int _done = 0;
  final List<String> _tail = [];
  final dl.ModelDownloader _downloader;

  DownloadState get state => _state;

  void _log(String line) {
    _tail.add(line);
    if (_tail.length > 120) _tail.removeAt(0);
  }

  /// 开始下载（幂等：已在跑就返回当前状态）。
  ///
  /// 按 `<modelsDir>/manifest.json` 里的 `files[]` 逐个下载：
  /// `{url, dest, sha256?, sizeBytes?}`。缺 manifest 就明确报缺，
  /// **不假装开始下**（否则界面会显示一个永远 0% 的进度条）。
  Future<Map<String, dynamic>> start() async {
    if (_state == DownloadState.running) return view();

    Directory(modelsDir).createSync(recursive: true);
    final manifest = _readManifest();
    if (manifest == null) {
      _state = DownloadState.failed;
      _log('[download] 缺少模型清单：${_manifestPath()}');
      _log('[download] 需要 {"files":[{"url":…,"dest":…,"sha256":…}]}');
      return view();
    }
    if (manifest.isEmpty) {
      _state = DownloadState.failed;
      _log('[download] 模型清单为空：${_manifestPath()}');
      return view();
    }

    _state = DownloadState.running;
    _percent = 0;
    _total = manifest.length;
    _done = 0;
    _log('[download] 开始：${manifest.length} 个文件 → $modelsDir');

    unawaited(_run(manifest));
    return view();
  }

  /// 逐个文件下载；任一失败即停（继续下一个只会浪费带宽）。
  Future<void> _run(List<dl.ManifestFile> files) async {
    var received = 0;
    for (final f in files) {
      if (_state != DownloadState.running) return; // 被暂停
      _log('[download] ${f.dest} ← ${f.url}');
      final r = await _downloader.download(url: f.url, fileName: f.dest, sha256: f.sha256);
      if (!r.ok) {
        _state = DownloadState.failed;
        _log('[download] 失败：${r.error}');
        return;
      }
      received += r.bytes;
      _done++;
      _percent = _total == 0 ? 0 : (_done * 100 ~/ _total);
      _log('[download] 完成 ${f.dest}（${r.bytes} 字节）');
    }
    if (_state == DownloadState.running) {
      _state = DownloadState.done;
      _percent = 100;
      _log('[download] 全部完成，共 $received 字节');
    }
  }

  /// 读模型清单；不存在或格式不对返回 null。
  List<dl.ManifestFile>? _readManifest() {
    final f = File(_manifestPath());
    if (!f.existsSync()) return null;
    try {
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return null;
      final files = decoded['files'];
      if (files is! List) return null;
      final out = <dl.ManifestFile>[];
      for (final e in files) {
        if (e is! Map) continue;
        final url = e['url'];
        final dest = e['dest'];
        if (url is! String || dest is! String) continue;
        out.add(dl.ManifestFile(url: url, dest: dest, sha256: e['sha256'] is String ? e['sha256'] as String : null));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  String _manifestPath() => '$modelsDir${Platform.pathSeparator}manifest.json';

  /// 暂停：断连接、`.part` 留盘（下次从断点续传）。
  Future<Map<String, dynamic>> pause() async {
    if (_state != DownloadState.running) return view();
    _downloader.cancel();
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
    // 🔴 只有真的下过（_total > 0）才报百分比；其余为 null —— 设计稿 §07 不编造进度。
    'percent': _total == 0 ? null : _percent / 100,
    'total': _total,
    'done': _done,
  };

  Future<void> dispose() async {
    _downloader.cancel();
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

/// 引擎端点门面 —— 把 `EngineRuntime` 与下载协调器收在一处，
/// 供 `Handlers` 直接调用（路由层只做搬运）。
class EngineFacade {
  EngineFacade({
    required this.runtimeRoot,
    required this.modelsDir,
    Duration healthTimeout = const Duration(seconds: 60),
  }) : runtime = EngineRuntime(runtimeRoot: runtimeRoot, modelsDir: modelsDir, healthTimeout: healthTimeout),
       downloader = ModelDownloadCoordinator(modelsDir: modelsDir);

  final String runtimeRoot;
  final String modelsDir;
  final EngineRuntime runtime;

  /// 把一张图交给引擎翻译（队列执行器用）。
  ///
  /// 引擎没起时**抛错**而不是返回 null：调用方才好把「引擎未就绪」如实写进任务失败原因。
  Future<Uint8List> translateImage(
    Uint8List bytes, {
    Duration readyTimeout = const Duration(seconds: 90),
    void Function(String line)? onStage,
  }) async {
    // 引擎可能正在启动：**等它就绪**，而不是让这一页直接失败。
    // 用户点完「启动引擎」立刻点翻译是常见操作，立刻失败会显得功能坏了。
    final deadline = DateTime.now().add(readyTimeout);
    while (runtime.port == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final port = runtime.port;
    if (port == null) {
      throw StateError('引擎未启动（等待 ${readyTimeout.inSeconds}s 仍无可用端口）');
    }
    final client = EngineClient(host: '127.0.0.1', port: port);
    final out = await client.translateImage(bytes);
    // 阶段信息进回调（翻译日志要显示流水线各步骤，D-077）。
    for (final line in out.stageLines) {
      onStage?.call(line);
    }
    if (!out.ok || out.image == null) {
      throw StateError(out.error?.message ?? '引擎翻译失败（无错误信息）');
    }
    return out.image!;
  }

  final ModelDownloadCoordinator downloader;

  // 装配状态（单实例：同一时刻只允许一次装配）。
  bool _installing = false;
  bool? _installOk;
  String? _installError;
  InstallProgress? _installProgress;
  EngineInstallPlan? _installPlan;
  List<String> _installLog = [];

  bool _rebuildingDeps = false;
  bool? _depsOk;
  String? _depsError;
  List<String> _depsTail = [];

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

  /// `POST /engine/install`（D-027）—— 按平台 + 后端装配整个引擎目录。
  ///
  /// 立刻返回，装配在后台跑；进度经 [installStatus] 轮询。
  /// **不接受「已经装着就别装」的短路**：换后端时正是要重跑一次。
  Future<Map<String, dynamic>> startInstall({
    required String engineDir,
    LlamaBackend backend = LlamaBackend.auto,
    bool includeNllb = false,
    Set<EnginePart>? parts,
  }) async {
    if (_installing) return installStatus();
    _installing = true;
    _installLog = [];
    _installError = null;
    _installProgress = null;

    _installPlan = resolveInstallPlan(
      platformKey: currentPlatformKey(),
      backend: backend,
      includeNllb: includeNllb,
      parts: parts,
    );
    final installer = EngineInstaller(engineDir: engineDir);
    final plan = _installPlan!;
    unawaited(() async {
      final r = await installer.install(plan, onProgress: (p) => _installProgress = p);
      _installLog = r.logs;
      _installError = r.error;
      _installOk = r.ok;
      _installing = false;
    }());
    return installStatus();
  }

  /// `GET /engine/install` —— 装配进度。
  Map<String, dynamic> installStatus() {
    final p = _installProgress;
    return {
      'state': _installing ? 'running' : (_installError != null ? 'failed' : (_installOk == null ? 'idle' : 'done')),
      'running': _installing,
      'index': p?.index ?? 0,
      'total': p?.total ?? 0,
      'entryId': p?.entryId,
      'phase': p?.phase,
      // null = 没有真实进度来源（不编造百分比）。
      'percent': p?.percent,
      'error': _installError,
      'tail': List<String>.of(_installLog),
      // 逐条目状态：设计稿的下载卡是「一列文件 + 每行进度条」，
      // 只给一个总百分比与稿子不符。
      'entries': _installEntries(),
    };
  }

  /// `POST /engine/deps/rebuild`（D-029）—— 用 pip 重建依赖，国内镜像优先。
  Future<Map<String, dynamic>> startDepsRebuild({required String engineDir, String? indexUrl}) async {
    if (_rebuildingDeps) return depsStatus();
    _rebuildingDeps = true;
    _depsOk = null;
    _depsError = null;
    _depsTail = [];
    unawaited(() async {
      final r = await EngineDepsInstaller(engineDir: engineDir).rebuild(indexUrl: indexUrl);
      _depsOk = r.ok;
      _depsError = r.error;
      _depsTail = r.log;
      _rebuildingDeps = false;
    }());
    return depsStatus();
  }

  /// `GET /engine/deps` —— 依赖重建进度。
  Map<String, dynamic> depsStatus() => {
    'state': _rebuildingDeps ? 'running' : (_depsError != null ? 'failed' : (_depsOk == null ? 'idle' : 'done')),
    'running': _rebuildingDeps,
    'error': _depsError,
    'tail': List<String>.of(_depsTail),
  };

  /// 逐条目状态（done / running / waiting）。
  List<Map<String, dynamic>> _installEntries() {
    final plan = _installPlan;
    if (plan == null) return const [];
    final cur = _installProgress?.index ?? -1;
    final curPercent = _installProgress?.percent;
    return [
      for (final (i, e) in plan.entries.indexed)
        {
          'id': e.id,
          'set': e.set,
          'sizeMb': double.parse(e.sizeMb.toStringAsFixed(1)),
          'state': i < cur
              ? 'done'
              : i == cur
              ? (_installing ? 'running' : (_installError != null ? 'failed' : 'done'))
              : 'waiting',
          'percent': i == cur ? curPercent : (i < cur ? 1.0 : null),
        },
    ];
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
