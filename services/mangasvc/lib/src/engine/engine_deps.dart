import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 依赖重建（pip）—— 校验里 `deps` 失败后的修复动作（D-028 / D-029）。
///
/// ## 为什么它是「重建」而不是「安装」
/// 依赖装在自带 Python 的 site-packages 里。带一份别人的引擎目录过来时，
/// 依赖可能因为 Python 小版本、架构、平台不同而不可用 —— 这时需要的不是
/// 重下 4 GB 模型，而是**把依赖重新装一遍**。
///
/// ## 镜像优先
/// 官方 PyPI 在部分网络下极慢甚至不可达（实测 `huggingface.co` 直接 000）。
/// 默认走国内镜像，可用参数覆盖。
///
/// ## 体积与耗时**必须提前告知**
/// macOS 只有 CPU/MPS 版 torch（数百 MB 量级）；Windows CUDA 版 torch 约 2.5 GB。
/// 不告知体积，用户会在点了「重建」之后才意识到要下几个 GB。
class EngineDepsInstaller {
  EngineDepsInstaller({required this.engineDir});

  final String engineDir;

  /// 默认镜像（国内优先；按 D-029 定案）。
  static const String defaultIndexUrl = 'https://pypi.tuna.tsinghua.edu.cn/simple';

  final List<String> _log = [];

  /// 最近输出（stdout + stderr，最多 200 行）。
  List<String> get log => List<String>.unmodifiable(_log);

  void _append(String line) {
    final t = line.trimRight();
    if (t.isEmpty) return;
    _log.add(t);
    if (_log.length > 200) _log.removeAt(0);
  }

  /// 重建依赖。
  ///
  /// [indexUrl] 为 null 时用 [defaultIndexUrl]；传空串表示**不指定**（用 pip 默认源）。
  /// [extraIndexUrl] 给 Windows CUDA 版 torch 用（`download.pytorch.org/whl/cu124`）。
  Future<DepsReport> rebuild({
    String? indexUrl,
    String? extraIndexUrl,
    Duration timeout = const Duration(minutes: 30),
    void Function(String line)? onLine,
  }) async {
    final python = enginePythonPathOf(engineDir);
    if (!File(python).existsSync()) {
      _append('[deps] 解释器不存在：$python');
      return DepsReport(ok: false, error: '解释器不存在：$python', log: log);
    }
    final req = File('${engineSrcDirOf(engineDir)}${Platform.pathSeparator}requirements.txt');
    if (!req.existsSync()) {
      _append('[deps] 缺少依赖清单：${req.path}');
      return DepsReport(ok: false, error: '缺少依赖清单：${req.path}', log: log);
    }

    final url = indexUrl ?? defaultIndexUrl;
    final args = <String>[
      '-m', 'pip', 'install',
      '-r', req.path,
      '--disable-pip-version-check',
      '--no-input',
      // 进度条对日志没有价值，还会把日志刷满。
      '--progress-bar', 'off',
      // 🔴 上游 requirements 里有**直连 GitHub** 的依赖
      //   （`pydensecrf@https://github.com/.../master.zip`），
      //   以及一个 github.io 上的额外 wheel 索引。pip 默认 15s 超时太短，
      //   实测会直接失败在「github.com didn't respond within 15 seconds」。
      '--timeout', '60',
      '--retries', '5',
      if (url.isNotEmpty) ...['--index-url', url],
      if (extraIndexUrl != null && extraIndexUrl.isNotEmpty) ...['--extra-index-url', extraIndexUrl],
    ];
    _append('[deps] ${url.isEmpty ? '默认源' : url}');
    _append('[deps] pip 开始（这一步可能要几分钟到数十分钟）');

    try {
      final proc = await Process.start(python, args, workingDirectory: engineSrcDirOf(engineDir));
      Future<void> pump(Stream<List<int>> s) async {
        await for (final line in s.transform(utf8.decoder).transform(const LineSplitter())) {
          _append(line);
          onLine?.call(line);
        }
      }

      final outDone = pump(proc.stdout);
      final errDone = pump(proc.stderr);
      final code = await proc.exitCode.timeout(
        timeout,
        onTimeout: () {
          // 超时要真的把它杀掉：pip 卡在网络上会一直占着进程与临时目录。
          proc.kill(ProcessSignal.sigkill);
          _append('[deps] 超时（${timeout.inMinutes} 分钟），已终止');
          return -1;
        },
      );
      await Future.wait([outDone, errDone]);

      if (code == 0) {
        _append('[deps] ✓ 完成');
        return DepsReport(ok: true, log: log);
      }
      _append('[deps] ✗ pip 退出码 $code');
      return DepsReport(ok: false, error: 'pip 退出码 $code', log: log);
    } on ProcessException catch (e) {
      _append('[deps] 起不了 pip：${e.message}');
      return DepsReport(ok: false, error: e.message, log: log);
    }
  }
}

/// 依赖重建结果。
class DepsReport {
  const DepsReport({required this.ok, required this.log, this.error});

  final bool ok;
  final List<String> log;
  final String? error;

  Map<String, dynamic> toJson() => {'ok': ok, 'error': error, 'tail': log};
}

/// 引擎解释器路径（服务侧，与 App 的 `paths.dart` 同口径）。
///
/// 🔴 服务不能 import `lib/`（不同包），故这几行在这里复刻；
/// 若两处不一致，症状是「App 认为装好了、服务起不来」，很难查。
String enginePythonPathOf(String engineDir) {
  final root = '$engineDir${Platform.pathSeparator}python';
  return Platform.isWindows
      ? '$root${Platform.pathSeparator}python.exe'
      : '$root${Platform.pathSeparator}bin${Platform.pathSeparator}python3';
}

/// 引擎源码目录（服务侧）。
String engineSrcDirOf(String engineDir) => '$engineDir${Platform.pathSeparator}src';
