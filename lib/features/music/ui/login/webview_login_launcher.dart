import 'package:flutter/foundation.dart';

import '../../data/webview/webview_cookie.dart';
import '../../data/webview/webview_login_config.dart';

/// 打开平台官方登录页并回读 Cookie 的能力抽象。
///
/// 两个实现：
/// · 桌面（macOS / Windows / Linux）：独立子窗口；
/// · 移动（Android / iOS）：全屏推入一个 WebView 页面。
///
/// 抽成接口的原因：两个平台插件的 API 完全不同，而业务层只关心
/// 「打开 → 轮询到 Cookie → 返回是否成功」。
abstract interface class WebviewLoginLauncher {
  /// 打开登录窗口；返回 true 表示已成功拿到登录 Cookie 并完成落盘。
  ///
  /// [onCookies] 每轮拿到 Cookie 时回调；返回 true 时实现应自行关闭窗口。
  Future<bool> open(WebviewLoginConfig config, Future<bool> Function(List<RawWebviewCookie> cookies) onCookies);
}

/// 不支持的平台 / 测试环境：直接返回 false。
class NoopWebviewLoginLauncher implements WebviewLoginLauncher {
  const NoopWebviewLoginLauncher();

  @override
  Future<bool> open(WebviewLoginConfig config, Future<bool> Function(List<RawWebviewCookie> cookies) onCookies) async {
    debugPrint('[music.login] webview login is not available on this platform');
    return false;
  }
}
