import 'dart:io';

/// `mangasvc` 的启动方式解析（P0-D1）。
///
/// ## 为什么需要「解析」而不是写死一条命令
/// 开发期是 `dart run services/mangasvc/bin/mangasvc.dart`，发布期是随包分发的
/// `dart compile exe` 产物。把两者写在一起必然在某一侧失效；而且失效方式是
/// **静默的**（应用起来了、只是永远连不上服务）。
///
/// 解析顺序（命中即用）：
/// 1. `--dart-define=MIAO_SERVICE_BIN=<绝对路径>` —— 排障 / 自定义部署；
/// 2. 与当前可执行文件**同目录**的 `mangasvc`（发布包布局）；
/// 3. 工作目录下有 `services/mangasvc/bin/mangasvc.dart`（开发期 `flutter run`）。
///
/// 都找不到时返回带**候选清单**的失败原因 —— 用户需要知道去哪儿放二进制。
class ServiceLaunchPlan {
  const ServiceLaunchPlan({
    required this.executable,
    required this.args,
    required this.workingDirectory,
    required this.origin,
  });

  final String executable;
  final List<String> args;
  final String? workingDirectory;

  /// 命中的解析来源，用于诊断输出。
  final String origin;

  /// 解析失败原因（含所有尝试过的路径）。
  static String? lastError;

  /// 解析启动计划；失败返回 null 并把原因写入 [lastError]。
  static ServiceLaunchPlan? resolve({String? forcedBin, String? overrideBin, Directory? cwd}) {
    lastError = null;
    final tried = <String>[];

    // 1) 显式指定
    final forced = forcedBin ?? overrideBin;
    if (forced != null && forced.isNotEmpty) {
      final f = File(forced);
      if (f.existsSync()) {
        return ServiceLaunchPlan(
          executable: f.path,
          // 必须让服务打印令牌，否则应用拿不到、每个请求 403。
          args: const ['--print-token'],
          workingDirectory: f.parent.path,
          origin: 'dart-define/env',
        );
      }
      tried.add('$forced（显式指定但不存在）');
    }

    // 2) 与 App 可执行文件同目录（发布包）
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    final bundled = '$exeDir${sep}mangasvc${Platform.isWindows ? '.exe' : ''}';
    if (File(bundled).existsSync()) {
      return ServiceLaunchPlan(
        executable: bundled,
        // 🔴 打包分支同样必须打印令牌：日志里的 `bundled → 端口 5180`
        // 说明实际走的就是这条，漏了它整条鉴权链就是断的。
        args: const ['--print-token'],
        workingDirectory: exeDir,
        origin: 'bundled',
      );
    }
    tried.add(bundled);

    // 3) 开发期：源码 + dart run
    //
    // 🔴 不能只看 `Directory.current`：`flutter run -d macos` 起的 App，
    //    工作目录并不是项目根（实测是 `/`），于是开发期永远「找不到服务」。
    //    这里同时从 App 二进制所在目录**向上找**项目根 —— 构建产物在
    //    `build/macos/Build/Products/Debug/*.app/Contents/MacOS/`，向上几层就是根。
    final base = (cwd ?? Directory.current).path;
    final devScript = '${sep}services${sep}mangasvc${sep}bin${sep}mangasvc.dart';
    final candidates = <String>['$base$devScript', ..._ancestorCandidates(exeDir, devScript)];
    String? script;
    for (final c in candidates) {
      if (File(c).existsSync()) {
        script = c;
        break;
      }
    }
    if (script != null) {
      final dart = resolveDartExecutable();
      return ServiceLaunchPlan(
        executable: dart,
        // `--print-token`：应用必须拿到服务生成的令牌，否则每个请求都 403。
        args: ['run', script, '--print-token'],
        // script = <root>/services/mangasvc/bin/mangasvc.dart ⇒ 上溯 4 层到项目根
        workingDirectory: File(script).parent.parent.parent.parent.path,
        origin: 'dev-source',
      );
    }
    tried.addAll(candidates);

    lastError =
        '找不到 mangasvc 可执行文件。已尝试：\n  ${tried.join('\n  ')}\n'
        '发布包应把 mangasvc 放在 App 同目录；开发期需在项目根目录运行。';
    return null;
  }

  /// 从 [start] 向上逐层拼出候选脚本路径（最多 8 层）。
  static List<String> _ancestorCandidates(String start, String devScript) {
    final out = <String>[];
    var dir = start;
    for (var i = 0; i < 8; i++) {
      final parent = File(dir).parent.path;
      if (parent == dir) break;
      dir = parent;
      out.add('$dir$devScript');
    }
    return out;
  }

  /// 定位 dart 可执行文件（开发期 `dart run` 用）。
  ///
  /// 🔴 **不能用 `Platform.resolvedExecutable`**：在真实 App 里它是**应用自己的二进制**
  /// （`miao_dock_flutter.app/Contents/MacOS/...`），根本不是 dart，
  /// 用它去 `run` 脚本只会得到「找不到命令」。
  /// 优先 `FLUTTER_ROOT` 下的 SDK dart（与 App 同一套 SDK），其次 PATH。
  static String resolveDartExecutable() {
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null && root.isNotEmpty) {
      final suffix = Platform.isWindows ? 'dart.exe' : 'dart';
      final candidate =
          '$root${Platform.pathSeparator}bin${Platform.pathSeparator}cache'
          '${Platform.pathSeparator}dart-sdk${Platform.pathSeparator}bin${Platform.pathSeparator}$suffix';
      if (File(candidate).existsSync()) return candidate;
    }
    final exe = Platform.resolvedExecutable;
    if (exe.endsWith('dart') || exe.endsWith('dart.exe')) return exe;
    // 交给 PATH（Flutter 桌面 App 从 Finder 启动时 PATH 可能不含 dart，故放在最后）。
    return 'dart';
  }
}
