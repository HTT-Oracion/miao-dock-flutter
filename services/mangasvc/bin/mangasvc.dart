import 'dart:io';

import 'package:mangasvc/src/server/server.dart';

/// mangasvc 入口：参数解析与启动装配。
///
/// 参数：
///   `--engine <mock|real>`  引擎模式（默认 mock，服务自测不需要 Python）
///   `--root <dir>`          落盘根目录（默认 `~/MiaoDock/library`）
///   `--port <n>`            固定端口（默认在 5180–5190 探测）
///   `--state <dir>`         服务状态目录（令牌 / 隐藏清单）；默认 `<root>/../state`
///                           🔴 必须与库根分开：库根是用户成果目录，状态是产品数据
///   `--no-token`            关闭 `X-Box-Token` 校验（**仅开发/自测**）
///   `--print-token`         就绪后额外打印令牌（父进程接管用）
///
/// 就绪信号：stdout 打印 `mangasvc listening on 127.0.0.1:<port>`，
/// 父进程据此判定可以开始请求。
Future<void> main(List<String> args) async {
  final engine = _arg(args, '--engine') ?? 'mock';
  final root = _arg(args, '--root');
  final state = _arg(args, '--state');
  final fixedPort = int.tryParse(_arg(args, '--port') ?? '');
  final noToken = args.contains('--no-token');
  final printToken = args.contains('--print-token');

  final server = MangaSvcServer(
    portStart: fixedPort ?? 5180,
    portEnd: fixedPort ?? 5190,
    rootDir: root,
    stateDir: state,
    engineMode: engine,
    requireToken: !noToken,
  );

  final port = await server.start();
  stdout.writeln(readyLine(port));
  if (printToken && server.token != null) {
    stdout.writeln('mangasvc token ${server.token}');
  }
  await stdout.flush();

  // 优雅退出：Ctrl+C / SIGTERM 时关服务，不留半开连接。
  ProcessSignal.sigint.watch().listen((_) async {
    await server.stop();
    exit(0);
  });
}

/// 取 `--key value` 形式的值；缺省返回 null。
String? _arg(List<String> args, String key) {
  final i = args.indexOf(key);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}
