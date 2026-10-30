import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/window/window_controller.dart';

/// 启动装配收口（AGENTS §3）：桌面 / 移动平台分支与 Fake / 真客户端注入只在这里发生，
/// 业务层不感知平台差异。
Future<void> bootstrap(Widget app) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDesktopWindow();
  // TODO: 按平台注入本地进程管理与端口探测（桌面）或远程客户端（移动端 / Web）
  runApp(ProviderScope(child: app));
}
