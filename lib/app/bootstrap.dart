import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 启动装配收口（AGENTS.md §3）：桌面 / 移动平台分支与 Fake / 真客户端注入只在这里发生，
/// 业务层不感知平台差异。
Future<void> bootstrap(Widget app) async {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: 按平台注入本地进程管理与端口探测（桌面）或远程客户端（移动端，地址来自设置域）
  runApp(ProviderScope(child: app));
}
