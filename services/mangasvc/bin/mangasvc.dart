import 'dart:io';

/// mangasvc 入口：参数解析与启动装配。
/// `--engine mock` 起 B 级替身（服务自测不需要 Python，见 AGENTS.md §3）。
void main(List<String> args) {
  final engine = _engineArg(args);
  // TODO: server/ 在 127.0.0.1:5180–5190 端口段绑定；engine/mock/ 提供假引擎端点
  stderr.writeln('mangasvc: 骨架占位，engine=$engine');
}

String _engineArg(List<String> args) {
  final i = args.indexOf('--engine');
  if (i < 0 || i + 1 >= args.length) return 'real';
  return args[i + 1];
}
