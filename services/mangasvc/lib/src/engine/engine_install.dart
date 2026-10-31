import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:protocol/protocol.dart';

import 'engine_manifest_entry.dart';
import 'engine_manifests.dart';
import 'engine_manifests_extra.dart';
import 'engine_manifests_mocr.dart';
import 'model_download.dart';
import 'runtime_setup.dart';

/// 当前平台键（与 manifest 的 `platform` 字段同口径）。
String currentPlatformKey() {
  final os = Platform.isMacOS
      ? 'darwin'
      : Platform.isWindows
      ? 'win32'
      : 'linux';
  // Dart 的 Platform.version 不直接给 arm64；用 `Platform.resolvedExecutable` 的架构判断不可靠，
  // 这里用 VM 提供的架构常量。
  final arch = _archKey();
  return '$os-$arch';
}

String _archKey() {
  // 用 `dart:ffi` 的 Abi 判断架构：从 `Platform.version` 里抠字符串是不稳的，
  // 而「装了 x64 的 llama 却在 arm64 上跑」只会得到一句看不懂的启动失败。
  final abi = Abi.current();
  if (abi == Abi.macosArm64 || abi == Abi.linuxArm64 || abi == Abi.windowsArm64) return 'arm64';
  return 'x64';
}

/// 一次安装计划：要下哪些条目。
class EngineInstallPlan {
  const EngineInstallPlan({required this.entries, required this.platformKey, required this.backend});

  final List<EngineManifestEntry> entries;
  final String platformKey;
  final LlamaBackend backend;

  /// 计划总下载体积（MB）。
  double get totalMb => entries.fold(0.0, (a, e) => a + e.sizeMb);
}

/// 按平台 + 后端 + 是否含 nllb 解析计划。
///
/// 🔴 llama 是**按后端挑条目**的：同样的平台，CUDA 与 Vulkan 是两个包，
/// 选错不会报错、只会起来时找不到加速器或直接缺 DLL。
EngineInstallPlan resolveInstallPlan({
  required String platformKey,
  required LlamaBackend backend,
  bool includeNllb = false,
  Set<EnginePart>? parts,
}) {
  final all = <String, EngineManifestEntry>{};
  for (final e in [...kRuntimeManifest, ...kExtraRuntimeManifest, ...kModelManifest, ...kMocrManifest]) {
    all[e.id] = e; // 补充清单同 id 时覆盖生成物（便于修数）
  }

  final picked = <EngineManifestEntry>[];
  void addIf(bool Function(EngineManifestEntry) test) {
    for (final e in all.values) {
      if (test(e) && e.appliesTo(platformKey)) picked.add(e);
    }
  }

  addIf((e) => e.set == 'python');
  addIf((e) => e.set == 'source');

  for (final id in _llamaIdsFor(platformKey, backend)) {
    final e = all[id];
    if (e != null) picked.add(e);
  }

  // mocr 是默认 OCR（D-041 定案），所以随视觉栈一起必装。
  addIf((e) => e.set == 'mocr');
  addIf((e) => e.set == 'visual');
  addIf((e) => e.set == 'llm');
  if (includeNllb) addIf((e) => e.set == 'translation');

  // 按部件过滤：`parts == null` 表示「全部必需件」。
  // 这让「只装运行时做小样验证」与「补下单个部件」共用同一条代码路径。
  final List<EngineManifestEntry> filtered;
  if (parts != null) {
    // 显式指定部件：完全按它来（补下单个部件也走这条路）。
    filtered = picked.where((e) => parts.contains(partOfSet(e.set))).toList();
  } else {
    // 未指定：默认装「必需件」，nllb 只有在显式要求时才带上。
    filtered = includeNllb ? picked : picked.where((e) => e.set != 'translation').toList();
  }

  return EngineInstallPlan(entries: filtered, platformKey: platformKey, backend: backend);
}

/// 后端 → llama 条目 id（CUDA 需要额外 cudart）。
List<String> _llamaIdsFor(String platform, LlamaBackend backend) {
  final isWin = platform.startsWith('win32');
  final isLinux = platform.startsWith('linux');
  final isArm = platform.endsWith('arm64');

  if (!isWin && !isLinux) {
    // macOS 只有一种构建（自带 Metal），后端概念不适用。
    return [platform == 'darwin-x64' ? 'llama_cpp_macos_x64' : 'llama_cpp_macos_arm64'];
  }

  return switch (backend) {
    // Linux 本期不在功能范围内（D-027 定案）：即便选了 CUDA 也退回 CPU，
    // 而不是返回一个清单里不存在的 id —— 后者会让安装「静默少装 llama」。
    LlamaBackend.cuda12 =>
      isWin
          ? ['llama_cpp_win_cuda_x64', 'cudart_win_cuda_x64']
          : [isArm ? 'llama_cpp_linux_arm64' : 'llama_cpp_linux_x64'],
    LlamaBackend.vulkan =>
      isWin
          ? [isArm ? 'llama_cpp_win_vulkan_arm64' : 'llama_cpp_win_vulkan_x64']
          : [isArm ? 'llama_cpp_linux_vulkan_arm64' : 'llama_cpp_linux_vulkan_x64'],
    // auto 在调用前应已解析成具体后端；落到这里按 CPU 处理（最保守、任何机器可用）。
    LlamaBackend.auto || LlamaBackend.cpu =>
      isWin
          ? [isArm ? 'llama_cpp_win_cpu_arm64' : 'llama_cpp_win_cpu_x64']
          : [isArm ? 'llama_cpp_linux_arm64' : 'llama_cpp_linux_x64'],
  };
}

/// 安装进度。
class InstallProgress {
  const InstallProgress({
    required this.index,
    required this.total,
    required this.entryId,
    required this.phase,
    this.percent,
  });

  final int index;
  final int total;
  final String entryId;

  /// `download` / `extract`。
  final String phase;

  /// 单个条目的下载进度（0–1）；无真实来源时 null。
  final double? percent;
}

/// 安装结果。
class InstallReport {
  const InstallReport({required this.ok, required this.logs, this.error});

  final bool ok;
  final List<String> logs;
  final String? error;
}

/// 装配引擎目录：按计划下载 → 解包/落盘 → 写 `.engine.json`。
///
/// ## 为什么归档留在 `.download-cache`
/// 解包失败（例如系统 tar 缺失）时，用户重试不必重下几十 MB；
/// 也让「换后端」只重下 llama 一个包。归档**不参与**部件校验。
class EngineInstaller {
  EngineInstaller({
    required this.engineDir,
    ModelDownloader Function(String dir)? downloaderFactory,
    RuntimeSetup runtimeSetup = const RuntimeSetup(),
  }) : _downloaderFactory = downloaderFactory ?? ((dir) => ModelDownloader(modelsDir: dir)),
       _setup = runtimeSetup;

  final String engineDir;
  final ModelDownloader Function(String dir) _downloaderFactory;
  final RuntimeSetup _setup;

  final List<String> _logs = [];

  void _log(String line) => _logs.add(line);

  String _abs(String rel) => longPathOf('$engineDir${Platform.pathSeparator}$rel', isWindows: Platform.isWindows);

  Future<InstallReport> install(EngineInstallPlan plan, {void Function(InstallProgress p)? onProgress}) async {
    final sep = Platform.pathSeparator;
    _log('[install] 平台 ${plan.platformKey} · 后端 ${plan.backend.id} · ${plan.entries.length} 个条目');

    for (final (i, e) in plan.entries.indexed) {
      final isArchive = e.extractTo != null;
      // 归档落在 .download-cache；普通文件按前缀映射落到最终位置。
      final targetRel = isArchive
          ? '.download-cache$sep${e.dest.replaceAll('/', sep).split(sep).last}'
          : mapManifestDest(e.dest).replaceAll('/', sep);
      final targetAbs = _abs(targetRel);
      final dir = File(targetAbs).parent;
      dir.createSync(recursive: true);

      onProgress?.call(InstallProgress(index: i, total: plan.entries.length, entryId: e.id, phase: 'download'));
      _log('[install] ↓ $e.id → $targetRel');

      final downloader = _downloaderFactory(dir.path);
      // 网络抖动是常态（实测 0.2 MB 的小文件也会超时）：可重试错误退避重试，
      // 已下的 `.part` 会在下一次尝试里续传，不会从头再来。
      var r = await _downloadWithRetry(downloader, e, targetAbs.split(sep).last, onProgress, i, plan);

      if (!r.ok) {
        _log('[install] ✗ ${e.id} 下载失败：${r.error}');
        return InstallReport(ok: false, logs: List.of(_logs), error: r.error);
      }

      if (isArchive) {
        final outRel = mapManifestExtractTo(e.extractTo!).replaceAll('/', sep);
        onProgress?.call(InstallProgress(index: i, total: plan.entries.length, entryId: e.id, phase: 'extract'));
        _log('[install] ⇡ ${e.id} → $outRel');
        final x = await _setup.extract(
          archivePath: targetAbs,
          destDir: _abs(outRel),
          stripComponents: e.extractStrip ?? 1,
        );
        if (!x.ok) {
          _log('[install] ✗ ${e.id} 解包失败：${x.error}');
          return InstallReport(ok: false, logs: List.of(_logs), error: x.error);
        }
      }
    }

    // mocr 走 HF 缓存布局：`from_pretrained` 需要 `refs/main` 才能定位到 snapshot。
    if (plan.entries.any((e) => e.set == 'mocr')) {
      final refs = File(_abs('.hf${sep}hub${sep}models--kha-white--manga-ocr-base${sep}refs${sep}main'));
      refs.parent.createSync(recursive: true);
      refs.writeAsStringSync('$mocrRepoRevision\n');
      _log('[install] 写入 HF refs/main（${mocrRepoRevision.substring(0, 8)}）');
    }
    _writeManifest(plan, sep);
    await _writeLaunchSpec(sep);
    _log('[install] ✓ 装配完成');
    return InstallReport(ok: true, logs: List.of(_logs));
  }

  /// 带重试的下载（最多 3 次，退避 1s/2s）。
  ///
  /// 网络抖动是常态（实测 0.2 MB 的小文件也会超时）：可重试错误退避重试，
  /// 已下的 `.part` 会在下一次尝试里续传，不会从头再来。
  Future<DownloadResult> _downloadWithRetry(
    ModelDownloader downloader,
    EngineManifestEntry e,
    String fileName,
    void Function(InstallProgress)? onProgress,
    int i,
    EngineInstallPlan plan,
  ) async {
    Future<DownloadResult> once() => downloader.download(
      url: e.url,
      fileName: fileName,
      sha256: e.sha256,
      onProgress: (received, total) => onProgress?.call(
        InstallProgress(
          index: i,
          total: plan.entries.length,
          entryId: e.id,
          phase: 'download',
          percent: (total == null || total <= 0) ? null : received / total,
        ),
      ),
    );

    var attempt = 0;
    var r = await once();
    while (!r.ok && r.retryable && attempt < 2) {
      attempt++;
      final backoff = Duration(seconds: attempt);
      _log('[install] ↻ ${e.id} 重试 $attempt（${backoff.inSeconds}s 后，断点续传）');
      await Future<void>.delayed(backoff);
      r = await once();
    }
    return r;
  }

  /// 写 `launch.json`（D-030）—— 引擎「怎么起」的唯一事实源。
  ///
  /// ## 为什么是 `server/main.py` 而不是 `-m manga_translator`
  /// HTTP API（`/translate/image/stream`）在 `server/main.py` 里；
  /// `manga_translator shared` 是它**自己 spawn 的翻译子进程**，API 在那边不存在。
  ///
  /// ## 健康检查为什么用 `/openapi.json`
  /// FastAPI 默认提供，不需要改上游；`/health` 在上游并不存在。
  ///
  /// ## 端口为什么现挑
  /// 写死会与「端口段探测」冲突；挑一个空闲端口记进来，重启时才可复现。
  Future<void> _writeLaunchSpec(String sep) async {
    final port = await _freePort();
    final pythonRel = Platform.isWindows
        ? 'python$sep'
              'python.exe'
        : 'python$sep'
              'bin${sep}python3';
    final data = {
      'command': pythonRel,
      'args': ['server${sep}main.py', '--host', '127.0.0.1', '--port', '$port', '--start-instance'],
      'healthPath': '/openapi.json',
      'port': port,
      // 模型目录**不在这里传**：上游不支持（D-030），模型直接放在 src/models。
      //
      // 🔴 mocr 权重走 HF 缓存：必须把 HF_HOME 指到引擎目录内，否则
      // `MangaOcr()` 会去 `~/.cache/huggingface` 找不到就**静默联网下载**。
      // OFFLINE=1 是保险丝：宁可报错，也不要悄悄联网。
      'env': {'HF_HOME': _abs('.hf'), 'HF_HUB_OFFLINE': '1', 'TRANSFORMERS_OFFLINE': '1'},
    };
    File(_abs('launch.json')).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    _log('[install] 写入 launch.json（端口 $port）');
  }

  /// 找一个空闲端口（绑定 0 让系统分配，随即释放）。
  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  /// 写 `.engine.json`：给「校验」与「换后端」判断现状用。
  void _writeManifest(EngineInstallPlan plan, String sep) {
    final file = File(_abs('.engine.json'));
    file.parent.createSync(recursive: true);
    final data = {
      'schema': 1,
      'platformKey': plan.platformKey,
      'llamaBackend': plan.backend.id,
      'installedAt': DateTime.now().toUtc().toIso8601String(),
      // 条目 id + sha256：换后端/换版本时用得上，也是「装了什么」的唯一记录。
      'entries': [
        for (final e in plan.entries) {'id': e.id, 'sha256': e.sha256, 'set': e.set},
      ],
    };
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  }
}
