import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/window/window_controller.dart';

/// 启动装配收口（AGENTS §3）：桌面 / 移动平台分支与 Fake / 真客户端注入只在这里发生，
/// 业务层不感知平台差异。
Future<void> bootstrap(Widget app) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDesktopWindow();
  await initMobileSystemUi();
  // TODO: 按平台注入本地进程管理与端口探测（桌面）或远程客户端（移动端 / Web）
  runApp(ProviderScope(child: app));
}

/// 移动端系统 UI（Android）：edge-to-edge 沉浸式。
///
/// 设计稿是 Web 稿、未画系统栏；跨端差异按以下口径落地并已在方案中报备：
///   · 状态栏 / 导航栏透明，内容延伸到系统栏下方；
///   · 图标用浅色（深色主题下才可见），由 `SafeArea` 负责内容避让。
///
/// iOS 与 Web 不做系统栏操作（iOS 由 Info.plist 控制，Web 无系统栏）。
Future<void> initMobileSystemUi() async {
  if (isDesktopPlatform || kIsWeb) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0x00000000),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
}
