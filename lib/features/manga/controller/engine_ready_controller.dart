import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/process/service_controller.dart';
import '../../../core/process/service_supervisor.dart';
import '../../../core/storage/paths.dart';
import '../domain/not_ready_state.dart';
import 'engine_controller.dart';
import 'engine_install_controller.dart';

/// 引擎目录的**快检**结果（D-037）。
///
/// 只做纯 IO 的结构判断（毫秒级）；起子进程的深校验属于设置页「校验」按钮。
/// 进漫画模块绝不能用深校验 —— 那要几秒，用户会先看到一个卡住的页面。
enum EnginePresence {
  /// 还没查完。
  checking,

  /// 没有 `.engine.json`：从没装配过。
  absent,

  /// 有痕迹但缺件（装了一半 / 被人删了目录）。
  partial,

  /// 结构齐全。
  complete,
}

/// 快检实现（可覆盖以便测试）。
final enginePresenceProbeProvider = Provider<Future<EnginePresence> Function(String dir)>((ref) => probeEnginePresence);

/// 快检一个引擎目录。
///
/// 判据（全部纯文件系统）：
/// - `.engine.json` 在 → 起码装过；
/// - `python`（解释器）+ `src/manga_translator` + `bin/llama` 在 → 运行时齐；
/// - `src/models/detection` 非空 + `llm/*.gguf` 在 → 权重齐。
/// 缺任一项 → [EnginePresence.partial]（不是 absent：用户看得出「差一点」）。
Future<EnginePresence> probeEnginePresence(String dir) async {
  final sep = Platform.pathSeparator;
  final manifest = File(engineManifestPath(dir));
  if (!manifest.existsSync()) return EnginePresence.absent;

  final py = File(enginePythonPath(dir));
  final pkg = Directory('${engineSrcDir(dir)}${sep}manga_translator');
  final llama = Directory(engineLlamaDir(dir));
  final detect = Directory('${engineModelsDir(dir)}${sep}detection');
  final llm = Directory(engineLlmDir(dir));

  final runtimeOk = py.existsSync() && pkg.existsSync() && llama.existsSync();
  final weightsOk =
      detect.existsSync() &&
      detect.listSync().isNotEmpty &&
      llm.existsSync() &&
      llm.listSync().whereType<File>().any((f) => f.path.toLowerCase().endsWith('.gguf'));

  return runtimeOk && weightsOk ? EnginePresence.complete : EnginePresence.partial;
}

/// 当前生效目录的快检状态。
final enginePresenceProvider = AsyncNotifierProvider<EnginePresenceNotifier, EnginePresence>(
  EnginePresenceNotifier.new,
);

class EnginePresenceNotifier extends AsyncNotifier<EnginePresence> {
  @override
  Future<EnginePresence> build() {
    final probe = ref.watch(enginePresenceProbeProvider);
    return probe(ref.watch(engineRootProvider));
  }

  /// 重新检查（装配完成、导入之后调用）。
  Future<void> refresh() async {
    final probe = ref.read(enginePresenceProbeProvider);
    final dir = ref.read(engineRootProvider);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => probe(dir));
  }
}

/// 漫画模块的**门禁状态**（D-037）。
///
/// 顺序很重要：先看有没有装（文件），再看引擎（进程），最后才放行。
/// 反过来的话，「没装」会被误报成「引擎没起」，用户点「启动引擎」永远失败。
enum MangaGateState {
  /// 正在快检：显示骨架，**不能**先画「未装配」（会闪一下像故障）。
  checking,

  /// 没装或装不全 → 未装配卡。
  notAssembled,

  /// 装配进行中 → 下载中卡（带真实进度）。
  downloading,

  /// 装好了但服务进程异常 → 服务异常卡。
  degraded,

  /// 装好了、引擎未启动 → 已装未启动卡。
  installed,

  /// 引擎启动中。
  starting,

  /// 引擎启动失败。
  failed,

  /// 可以正常使用：直接渲染目标视图。
  ready,
}

/// 由四路信号合成门禁状态（纯函数，便于测试）。
MangaGateState deriveMangaGate({
  required bool presenceLoading,
  required EnginePresence presence,
  required bool installing,
  required bool installError,
  required bool serviceBroken,
  required bool engineRunning,
  required bool engineStarting,
  required bool engineFailed,
  required bool needsLocalEngine,
}) {
  // 远程翻译不依赖本机引擎：装配缺失也不该拦。
  if (!needsLocalEngine) return MangaGateState.ready;

  if (presenceLoading) return MangaGateState.checking;
  if (installing) return MangaGateState.downloading;
  if (installError) return MangaGateState.notAssembled;
  if (presence != EnginePresence.complete) return MangaGateState.notAssembled;

  if (serviceBroken) return MangaGateState.degraded;
  if (engineRunning) return MangaGateState.ready;
  if (engineStarting) return MangaGateState.starting;
  if (engineFailed) return MangaGateState.failed;
  return MangaGateState.installed;
}

/// 门禁状态 provider。
final mangaGateProvider = Provider<MangaGateState>((ref) {
  final source = ref.watch(translateSourceProvider);
  final presence = ref.watch(enginePresenceProvider);
  final install = ref.watch(engineInstallProvider);
  final engine = ref.watch(engineStateProvider);
  final service = ref.watch(serviceStatusProvider);

  return deriveMangaGate(
    presenceLoading: presence.isLoading && !presence.hasValue,
    presence: presence.value ?? EnginePresence.checking,
    installing: install.running,
    installError: install.error != null,
    serviceBroken: service.supported && service.state == ServiceProcessState.failed,
    engineRunning: engine.isReady,
    engineStarting: engine == EngineRuntimeState.starting,
    engineFailed: engine == EngineRuntimeState.failed,
    needsLocalEngine: source.requiresLocalRuntime,
  );
});
