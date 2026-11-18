import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/webview/webview_cookie.dart';
import '../../data/webview/webview_login_config.dart';

/// 移动端 WebView 登录页：**全屏推入**，内嵌平台官方登录页。
///
/// 移动端没有「独立子窗口」的概念，正确形态是一个带返回的整页：
/// 顶部标题栏（标题 + 关闭）→ WebView → 底部加载进度条。
/// 用户完成登录后自动关闭，返回 true。
class MobileWebviewLoginPage extends StatefulWidget {
  const MobileWebviewLoginPage({super.key, required this.config, required this.onCookies});

  final WebviewLoginConfig config;

  /// 每轮 Cookie 回调；返回 true 表示已登录，页面自行关闭。
  final Future<bool> Function(List<RawWebviewCookie> cookies) onCookies;

  @override
  State<MobileWebviewLoginPage> createState() => _MobileWebviewLoginPageState();
}

class _MobileWebviewLoginPageState extends State<MobileWebviewLoginPage> {
  late final WebViewController _controller;
  late final WebViewCookieManager _cookieManager;

  /// Cookie 轮询定时器（与桌面端同为 2 秒，避免高频读 WebView）。
  Timer? _poller;
  bool _loading = true;
  bool _done = false;
  bool _warmupStarted = false;

  @override
  void initState() {
    super.initState();
    _cookieManager = WebViewCookieManager();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 官方登录页在移动端会按 UA 决定 H5/PC 版；给标准手机 UA 拿到移动版表单。
      ..setUserAgent(_mobileUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
            // 页面跳转时读一次：登录成功后平台通常会有一次跳转。
            unawaited(_pollCookies());
          },
          onPageFinished: (_) async {
            if (mounted) setState(() => _loading = false);
            await _pollCookies();
          },
        ),
      );

    // 🔴 先清 Cookie 再导航（顺序与 miao-dock 一致）：反过来会把刚加载页面写入的
    // 会话/CSRF Cookie 一起清掉，登录流程可能因此拿不到完整票据。
    unawaited(_startFromCleanState());
    _poller = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_pollCookies()));
  }

  Future<void> _startFromCleanState() async {
    try {
      await _cookieManager.clearCookies();
    } on Object {
      // 清理失败不阻断登录：最坏是沿用上一次的 WebView Cookie。
    }
    if (!mounted) return;
    await _controller.loadRequest(Uri.parse(widget.config.url));
  }

  static const _mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  /// 读取当前 WebView 在**本平台域名**下的 Cookie，交给上层判定。
  Future<void> _pollCookies() async {
    if (_done || !mounted) return;
    try {
      final raw = <RawWebviewCookie>[];
      // `getCookies` 需要具体域名：用配置里的主域逐个查（子域靠后缀匹配收口）。
      for (final domain in widget.config.cookieDomains) {
        try {
          final cookies = await _cookieManager.getCookies(domain: Uri.parse('https://$domain'));
          for (final c in cookies) {
            raw.add(RawWebviewCookie(name: c.name, value: c.value, domain: domain));
          }
        } on Object {
          // 某些域名没有 Cookie 属正常情况，继续查下一个。
        }
      }
      if (raw.isEmpty) return;
      // warmup 泛化（对齐 miao-dock）：有登录态但登录票据未集齐时，
      // 导航到源声明的 warmup 页触发更多 Cookie 写入，否则拿到的是"半张票"。
      if (widget.config.warmupUrl != null && !_warmupStarted) {
        final jar = <String, String>{};
        for (final c in raw) {
          jar.putIfAbsent(c.name, () => c.value);
        }
        final anyTicket = widget.config.loginCookieNames.any((n) => (jar[n] ?? '').isNotEmpty);
        final allTickets = widget.config.loginCookieNames.every((n) => (jar[n] ?? '').isNotEmpty);
        if (anyTicket && !allTickets) {
          _warmupStarted = true;
          await _controller.loadRequest(Uri.parse(widget.config.warmupUrl!));
          return;
        }
      }
      final loggedIn = await widget.onCookies(raw);
      if (!loggedIn || !mounted) return;
      _done = true;
      _poller?.cancel();
      Navigator.of(context).maybePop(true);
    } on Object {
      // 页面切换中读取失败属正常，下一拍继续。
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        // 用户主动返回：清理 Cookie，避免下次打开带着旧登录态。
        if (didPop) unawaited(_cookieManager.clearCookies());
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        appBar: AppBar(
          backgroundColor: palette.panel,
          elevation: 0,
          title: Text(
            widget.config.title,
            style: TextStyle(fontSize: AppFont.px14, color: palette.ink),
          ),
          leading: IconButton(
            icon: Icon(LucideIcons.x, size: 18, color: palette.ink2),
            tooltip: l10n.actionCancel,
            onPressed: () => Navigator.of(context).maybePop(false),
          ),
          bottom: _loading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2, backgroundColor: palette.line, color: palette.acc),
                )
              : null,
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
