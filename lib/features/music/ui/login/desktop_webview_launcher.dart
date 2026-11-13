import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';

import '../../data/webview/kugou_cookie_auth.dart';
import '../../data/webview/webview_cookie.dart';
import '../../domain/music_models.dart';
import '../../data/webview/webview_login_config.dart';
import 'webview_login_launcher.dart';

/// 桌面端：开一个**独立子窗口**加载平台官方登录页，并轮询 Cookie。
///
/// 与 miao-dock `open_netease_login_window` 同一套流程：
/// 开窗 → 每 2 秒读一次 Cookie → 抓到登录票据就落盘并关窗 → 5 分钟超时。
class DesktopWebviewLoginLauncher implements WebviewLoginLauncher {
  const DesktopWebviewLoginLauncher();

  /// 窗口尺寸（对齐 miao-dock 的 940×760）。
  static const _width = 940;
  static const _height = 760;

  /// 最长等待时间（miao-dock 是 150 次 × 2 秒）。
  static const _timeout = Duration(minutes: 5);

  /// Cookie 轮询间隔。
  static const _pollInterval = Duration(seconds: 2);

  @override
  Future<bool> open(WebviewLoginConfig config, Future<bool> Function(List<RawWebviewCookie> cookies) onCookies) async {
    // Windows 可能缺 WebView2 运行时，先探测再开窗，避免抛异常给用户。
    if (!await WebviewWindow.isWebviewAvailable()) {
      debugPrint('[music.login] webview runtime is not available');
      return false;
    }

    // 🔴 开窗前必须清空 WebView 的全部浏览数据（Cookie / localStorage）：
    // 否则上一次登录的账号还留在 WebView 里，下一轮开窗会在 2 秒内被「自动登录」
    // 顶掉 —— 用户没做任何操作，也没机会换成别的账号（miao-dock 同口径：
    // open_*_login_window 里先 clear_all_browsing_data 再导航）。
    await WebviewWindow.clearAll();

    final webview = await WebviewWindow.create(
      configuration: CreateConfiguration(windowWidth: _width, windowHeight: _height, title: config.title),
    );

    var loggedIn = false;
    var warmupStarted = false;
    var pollCount = 0;
    Timer? poller;
    final closed = Completer<void>();

    // 窗口关闭（用户点 X 或我们主动 close）时结束等待。
    unawaited(
      webview.onClose.then((_) {
        if (!closed.isCompleted) closed.complete();
      }),
    );

    await webview.launch(config.url);

    poller = Timer.periodic(_pollInterval, (_) async {
      if (closed.isCompleted || loggedIn) return;
      try {
        final raw = <RawWebviewCookie>[];
        // 来源一：原生 Cookie 存储（WKWebView httpCookieStore）。
        try {
          final cookies = await webview.getAllCookies();
          for (final c in cookies) {
            raw.add(RawWebviewCookie(name: c.name, value: c.value, domain: c.domain));
          }
        } on Object catch (e) {
          debugPrint('[music.login] native cookies failed: $e');
        }
        // 来源二：页面 `document.cookie`。
        // 🔴 两个来源都要读：WKWebView 的 httpCookieStore 与页面 JS 的 document.cookie
        // 不是同一份存储，某些登录流程（尤其 SPA）只写 JS 层，只读原生会一直拿不到票据。
        try {
          final docCookie = await webview.evaluateJavaScript(
            'document.cookie.split("; ").filter(function(s){return s.indexOf("=")>0;})'
            '.map(function(s){var i=s.indexOf("=");return {name:s.slice(0,i),value:s.slice(i+1)};})',
          );
          if (docCookie is List) {
            for (final item in docCookie) {
              if (item is! Map) continue;
              final name = '${item['name'] ?? ''}';
              final value = '${item['value'] ?? ''}';
              if (name.isEmpty || value.isEmpty) continue;
              // JS 层拿不到 domain，按配置的主域记账。
              raw.add(RawWebviewCookie(name: name, value: value, domain: config.cookieDomains.first));
            }
          }
        } on Object catch (e) {
          debugPrint('[music.login] document.cookie failed: $e');
        }
        // 诊断：每 5 拍打一次，能直接看出「原生有没有 cookie / 域名是什么」。
        pollCount++;
        if (pollCount % 5 == 1) {
          debugPrint(
            '[music.login] poll#$pollCount cookies=${raw.length} '
            'names=${raw.map((e) => e.name).take(12).toList()} '
            'domains=${raw.map((e) => e.domain).toSet().take(6).toList()}',
          );
        }
        if (raw.isEmpty) return;
        // 酷狗 warmup（对齐 miao-dock）：有登录态但缺播放票据（token）时，
        // 导航到个人中心触发更多 Cookie 写入，否则拿到的是"半张票"。
        if (config.platform == MusicPlatform.kugou && config.warmupUrl != null && !warmupStarted) {
          final auth = extractKugouCookieAuth(raw.map((c) => (name: c.name, value: c.value)).toList());
          if (auth.loggedIn && !auth.playbackReady) {
            warmupStarted = true;
            debugPrint('[music.login] kugou warmup: navigate to user center');
            await webview.launch(config.warmupUrl!);
            return;
          }
        }
        if (await onCookies(raw)) {
          loggedIn = true;
          poller?.cancel();
          // 抓到票据：先落盘成功再关窗，避免关窗后 cookie 丢失。
          await webview.close();
          if (!closed.isCompleted) closed.complete();
        }
      } on Object catch (e) {
        // 窗口可能在读取过程中被关闭，按「继续等」处理。
        debugPrint('[music.login] read cookies failed: $e');
      }
    });

    // 超时兜底：到点就关，不无限挂着。
    final timeout = Timer(_timeout, () async {
      if (closed.isCompleted) return;
      poller?.cancel();
      await webview.close();
      if (!closed.isCompleted) closed.complete();
    });

    await closed.future;
    poller.cancel();
    timeout.cancel();
    return loggedIn;
  }
}
