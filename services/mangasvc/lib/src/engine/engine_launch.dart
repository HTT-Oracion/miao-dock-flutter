import 'dart:convert';
import 'dart:io';

/// 引擎启动规格（P0-C6 接线）—— 从 `<runtimeRoot>/launch.json` 读取。
///
/// ## 为什么要一份文件而不是写死在代码里
/// 引擎的可执行文件、参数、健康路径随版本与平台变化（Python 脚本 / 打包二进制 /
/// 不同 venv 布局）。写死会在换版本时静默失效；读文件则把「怎么起」变成**可诊断的数据**——
/// 起不来时能直接指出是哪一项缺了。
///
/// 格式：
/// ```json
/// {
///   "command": "venv/bin/python",
///   "args": ["-m", "manga_translator.server", "--port", "5190"],
///   "healthPath": "/health",
///   "port": 5190
/// }
/// ```
/// `command` 相对 [runtimeRoot]；`port` 用于拼健康地址。
class EngineLaunchSpec {
  const EngineLaunchSpec({
    required this.command,
    required this.args,
    required this.healthPath,
    required this.port,
    this.env = const {},
  });

  final String command;
  final List<String> args;
  final String healthPath;
  final int port;

  /// 启动时注入的环境变量（`launch.json` 的 `env` 字段）。
  final Map<String, String> env;

  String healthUrl() => 'http://127.0.0.1:$port$healthPath';

  /// 读规格。失败时返回**带原因**的错误，不返回 null 了事 ——
  /// 「起不来」时用户最需要知道的是缺什么。
  static LaunchSpecResult load(String runtimeRoot) {
    final file = File('$runtimeRoot${Platform.pathSeparator}launch.json');
    if (!file.existsSync()) {
      return LaunchSpecResult.failure('缺少启动规格：${file.path}（需要 command / args / healthPath / port）');
    }
    Map<String, dynamic> m;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        return LaunchSpecResult.failure('启动规格不是 JSON 对象：${file.path}');
      }
      m = decoded;
    } catch (e) {
      return LaunchSpecResult.failure('启动规格不是合法 JSON：${file.path}（$e）');
    }

    final command = m['command'];
    final healthPath = m['healthPath'];
    final port = m['port'];
    if (command is! String || command.isEmpty) {
      return LaunchSpecResult.failure('启动规格缺 command');
    }
    if (healthPath is! String || healthPath.isEmpty) {
      return LaunchSpecResult.failure('启动规格缺 healthPath');
    }
    if (port is! int || port <= 0 || port > 65535) {
      return LaunchSpecResult.failure('启动规格的 port 非法：$port');
    }
    final rawArgs = m['args'];
    final args = <String>[if (rawArgs is List) ...rawArgs.map((e) => e.toString())];

    // env 是可选字段：老规格（没有该字段）按空处理，保持向后兼容。
    final rawEnv = m['env'];
    final env = <String, String>{
      if (rawEnv is Map)
        for (final e in rawEnv.entries) e.key.toString(): e.value.toString(),
    };

    // command 已解析成绝对路径 ⇒ 不存在必须现在报错，而不是等 spawn 抛一个笼统的失败。
    final resolved = _resolve(runtimeRoot, command);
    if (!File(resolved).existsSync()) {
      return LaunchSpecResult.failure('启动规格指向的可执行文件不存在：$resolved');
    }

    return LaunchSpecResult.success(
      EngineLaunchSpec(command: resolved, args: args, healthPath: healthPath, port: port, env: env),
    );
  }

  static String _resolve(String root, String command) {
    if (command.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(command)) return command;
    return '$root${Platform.pathSeparator}$command';
  }
}

/// 规格读取结果。
class LaunchSpecResult {
  const LaunchSpecResult._({this.spec, this.error});

  const LaunchSpecResult.success(EngineLaunchSpec spec) : this._(spec: spec);

  const LaunchSpecResult.failure(String error) : this._(error: error);

  final EngineLaunchSpec? spec;
  final String? error;

  bool get ok => spec != null;
}
