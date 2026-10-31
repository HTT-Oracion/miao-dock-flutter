import 'dart:io';

/// 引擎运行时装配（P0-C6a）—— 解包 tar.gz / zip 到运行时目录。
///
/// ## 为什么用系统 `tar` 而不是 Dart 的 archive 包
/// 1. **符号链接**：Python venv 的 `bin/python` 是指向系统解释器的**符号链接**。
///    纯 Dart 解包器普遍把 symlink 当成普通文件写出 —— 解出来的 venv 直接不可用，
///    且症状极隐蔽（文件都在，就是跑不起来）。
/// 2. **可执行位**：`bin/python`、`llama-server` 必须保留 `0755`。
/// 3. **与原项目同口径**：`runtime_setup.rs` / `fetch_models.rs` 都是 `tar -xf`，
///    系统 tar（macOS/Linux 的 tar、Windows 10+ 的 bsdtar）同时认 tar.gz 与 zip。
///
/// 代价：依赖系统 `tar`。测不到就明确报错（含装法），**不静默降级**成"解开了但没用"。
///
/// ## 原子性
/// 先解到临时目录，成功后**才**合并进目标目录。失败时目标目录**完全不动** ——
/// 这样"装配失败"不会留下一半文件、让下次重跑误判为已装配。
class RuntimeSetup {
  const RuntimeSetup();

  /// 解包归档到 [destDir]。
  ///
  /// [stripComponents]：剥掉顶层目录层数，默认 1（归档一般带一个顶层目录）。
  Future<ExtractResult> extract({required String archivePath, required String destDir, int stripComponents = 1}) async {
    final archive = File(archivePath);
    if (!archive.existsSync()) {
      return ExtractResult.failure('归档不存在：$archivePath');
    }
    if (!_isSupportedArchive(archivePath)) {
      return ExtractResult.failure('不支持的归档格式：${_ext(archivePath)}（只支持 .tar.gz / .tgz / .tar / .zip）');
    }

    final tarBin = await _findTar();
    if (tarBin == null) {
      // 不静默失败：没有 tar 就装不了引擎，用户必须知道装什么。
      return ExtractResult.failure('找不到系统 tar（装配引擎必需）。macOS / Linux 自带；Windows 需 10 1803+ 的 bsdtar。');
    }

    final out = Directory(destDir);
    out.createSync(recursive: true);

    // 临时目录放在**同一卷**（destDir 的兄弟），这样最后 rename 是原子且不跨盘复制。
    final tmp = Directory('${destDir}_extracting_${DateTime.now().microsecondsSinceEpoch}');
    tmp.createSync(recursive: true);

    try {
      final args = <String>[
        '-xf',
        archivePath,
        '-C',
        tmp.path,
        if (stripComponents > 0) '--strip-components=$stripComponents',
      ];
      final result = await Process.run(tarBin, args);
      if (result.exitCode != 0) {
        final stderr = '${result.stderr}'.trim();
        return ExtractResult.failure('解包失败（退出码 ${result.exitCode}）${stderr.isEmpty ? '' : '：$stderr'}');
      }

      // 解出来是空的 ⇒ 大概率 strip 层数不对（顶层目录多于 1 层）。
      // 这类失败如果放过，用户会看到"装配成功"但引擎永远起不来。
      final entries = tmp.listSync();
      if (entries.isEmpty) {
        return ExtractResult.failure('解包后目录为空（stripComponents=$stripComponents 可能过多，归档顶层结构与此不符）');
      }

      _mergeInto(tmp, out);
      return ExtractResult.success(entries.length);
    } on ProcessException catch (e) {
      return ExtractResult.failure('起 tar 失败：${e.message}（需系统 tar / bsdtar）');
    } finally {
      // 无论成败都清临时目录；out 只在 _mergeInto 成功时被动过。
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {
          // 清理失败不影响结果判定，留痕由调用方日志承担。
        }
      }
    }
  }

  /// 把 [tmp] 里的顶层条目移进 [out]（覆盖同名）。
  ///
  /// 用 rename 而非 copy：同一文件系统内 rename 是常数时间，
  /// 而运行时动辄数百 MB，复制会白白多花几秒并短暂占用双倍磁盘。
  void _mergeInto(Directory tmp, Directory out) {
    // 🔴 `followLinks: false` 是必须的：默认 true 会把符号链接**解引用**成 File，
    //    而 File.renameSync 内部会先 existsSync（跟随链接）——一旦链接目标已被先移走
    //    （venv 里的 python-link → python 正是这种情形），就抛
    //    PathNotFoundException: No such file or directory。
    for (final entity in tmp.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final target = '${out.path}${Platform.pathSeparator}$name';
      _removeIfExists(target);
      switch (entity) {
        case Link():
          entity.renameSync(target);
        case Directory():
          entity.renameSync(target);
        case File():
          entity.renameSync(target);
        default:
          entity.renameSync(target);
      }
    }
  }

  /// 删掉已存在的同名目标（覆盖语义）。
  ///
  /// `followLinks: false` 同样必要：同名目标是符号链接时要删**链接本身**，
  /// 而不是删它指向的东西。
  void _removeIfExists(String path) {
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.directory:
        Directory(path).deleteSync(recursive: true);
      case FileSystemEntityType.link:
        Link(path).deleteSync();
      default:
        File(path).deleteSync();
    }
  }

  static bool _isSupportedArchive(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.tar.gz') || lower.endsWith('.tgz') || lower.endsWith('.tar') || lower.endsWith('.zip');
  }

  static String _ext(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.indexOf('.');
    return dot < 0 ? name : name.substring(dot);
  }

  /// 找可用的 tar。优先 `tar`（PATH），Windows 上再试 System32 下的绝对路径。
  static Future<String?> _findTar() async {
    for (final candidate in <String>['tar', if (Platform.isWindows) r'C:\Windows\System32\tar.exe']) {
      try {
        final r = await Process.run(candidate, ['--version']);
        // bsdtar 的 --version 退出码也是 0；GNU tar 同样。
        if (r.exitCode == 0) return candidate;
      } catch (_) {
        // 继续试下一个
      }
    }
    return null;
  }
}

/// 解包结果。
class ExtractResult {
  const ExtractResult._({required this.ok, this.entryCount = 0, this.error});

  const ExtractResult.success(int entryCount) : this._(ok: true, entryCount: entryCount);

  const ExtractResult.failure(String error) : this._(ok: false, error: error);

  final bool ok;

  /// 顶层条目数（成功时）。
  final int entryCount;

  /// 失败原因（失败时）。
  final String? error;
}
