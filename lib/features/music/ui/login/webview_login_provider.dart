import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/window/window_controller.dart';
import 'desktop_webview_launcher.dart';
import 'webview_login_launcher.dart';

/// 当前平台的登录窗口实现。
///
/// 桌面（macOS / Windows / Linux）用独立子窗口；移动端由 UI 层推入全屏页
/// （见 `mobile_webview_login_page.dart`），因此这里只负责桌面。
final webviewLoginLauncherProvider = Provider<WebviewLoginLauncher>((ref) {
  if (kIsWeb) return const NoopWebviewLoginLauncher();
  if (isDesktopPlatform) return const DesktopWebviewLoginLauncher();
  return const NoopWebviewLoginLauncher();
});

/// 平台是否具备 WebView 登录能力。
bool supportsWebviewLoginOnCurrentPlatform() {
  if (kIsWeb) return false;
  return true; // 桌面与移动都有实现
}
