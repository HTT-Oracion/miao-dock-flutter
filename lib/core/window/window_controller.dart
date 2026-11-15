import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/tokens.dart';

/// 当前是否为桌面平台（自绘标题栏 / 本地服务进程的前提）；Web / 移动端为 false。
final bool isDesktopPlatform = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// 是否渲染自绘窗控（设计稿 G Top 的 WinCtl）：Windows / Linux 自绘；macOS 保留原生红绿灯。
final bool showWindowControls = !kIsWeb && isDesktopPlatform && !Platform.isMacOS;

/// macOS 原生红绿灯叠在自绘标题栏左侧，标题栏需为其预留宽度。
final bool isMacosPlatform = !kIsWeb && isDesktopPlatform && Platform.isMacOS;

/// 窗口标题 —— 系统窗口管理器在 `runApp` 之前就要用它，此时还没有 `BuildContext`，
/// 因此不能走 ARB。应用内标题（`MaterialApp.onGenerateTitle`）仍走 l10n。
///
/// 这条是 D-006 棘轮的**显式豁免**：系统级字符串，非业务文案。
const String appWindowTitle = '喵坞 MiaoDock';

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
      title: appWindowTitle,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.show();
    },
  );
}

/// 阅读器专注模式（应用级全屏 + 不渲染壳层）的**顶部让位**高度。
///
/// - **已真全屏**（`setFullScreen` 成功）：系统标题栏 / 红绿灯全部隐藏，
///   让位 0 —— 否则顶部会多一条 28px 空白。
/// - **未全屏**（全屏失败退化成普通窗口 / 用户手动退出全屏）：
///   - macOS：`TitleBarStyle.hidden` 只是隐藏标题栏，原生红绿灯仍**叠在客户区左上角**，
///     必须让出 [AppMetrics.macTrafficLightBand]，否则会压住阅读器顶栏；
///   - Windows / Linux：`WM_NCCALCSIZE` 把客户区铺满窗口，无系统控件叠在上面，让位 0。
///
/// 抽成「按平台 + 全屏状态」的纯函数：真机平台不可注入，测试里才能覆盖四种组合。
double readerFocusTopInset({required bool macos, required bool fullscreen}) {
  if (fullscreen) return 0;
  return macos ? AppMetrics.macTrafficLightBand : 0;
}

/// 窗控「最大化 / 还原」按钮该做什么（纯函数，便于测试四种状态）。
///
/// 🔴 顺序不能颠倒：**先看全屏**。
/// Windows 全屏（`setFullScreen(true)`）时窗口并不处于「最大化」状态，
/// 只调 `unmaximize()` 无效，用户看到的就是「点了没反应、退不出全屏」。
/// 这也是原生插件的既有行为：`Maximize()` 在 `showCmd == SW_MAXIMIZE` 时
/// 直接返回，所以对已最大化的窗口再调 `maximize()` 同样是空操作。
enum WindowToggleAction { exitFullScreen, unmaximize, maximize }

WindowToggleAction windowToggleAction({required bool fullscreen, required bool maximized}) {
  if (fullscreen) return WindowToggleAction.exitFullScreen;
  if (maximized) return WindowToggleAction.unmaximize;
  return WindowToggleAction.maximize;
}
