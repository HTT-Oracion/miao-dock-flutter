import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// 当前是否为桌面平台（自绘标题栏 / 本地服务进程的前提）；Web / 移动端为 false。
final bool isDesktopPlatform = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// 是否渲染自绘窗控（设计稿 G Top 的 WinCtl）：Windows / Linux 自绘；macOS 保留原生红绿灯。
final bool showWindowControls = isDesktopPlatform && !Platform.isMacOS;

/// macOS 原生红绿灯叠在自绘标题栏左侧，标题栏需为其预留宽度。
final bool isMacosPlatform = isDesktopPlatform && Platform.isMacOS;

/// 桌面窗口装配：无边框标题栏 + 自绘窗控。Web / 移动端直接跳过；
/// 主入口经 bootstrap 调用（平台收口见 AGENTS §3）。
Future<void> initDesktopWindow() async {
  if (!isDesktopPlatform) return;
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1440, 900),
      minimumSize: Size(980, 640),
      center: true,
      title: '喵坞 MiaoDock',
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.show();
    },
  );
}
