import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/netease_api.dart';
import '../data/webview/kugou_cookie_auth.dart';
import '../data/webview/webview_cookie.dart';
import '../data/webview/webview_login_config.dart';
import '../domain/music_models.dart';
import 'music_auth.dart';
import 'music_session.dart';

/// 登录流程阶段。
///
/// 登录统一走「打开平台官方登录页（WebView）→ 读取 Cookie」：
/// 官方页面在真实浏览器内核里完成登录，不需要我们伪造任何客户端指纹，
/// 也就不触发风控。
enum MusicLoginPhase {
  /// 未开始。
  idle,

  /// 登录窗口已打开，等待用户在官方页面完成登录。
  awaiting,

  /// 已抓到登录 Cookie，正在落盘。
  saving,

  /// 登录成功（窗口可关闭）。
  succeeded,

  /// 用户关闭窗口但没登录成功（取消）。
  cancelled,

  /// 平台不支持，或保存凭据失败。
  failed,
}

@immutable
class MusicLoginState {
  const MusicLoginState({
    this.phase = MusicLoginPhase.idle,
    this.platform = MusicPlatform.netease,
    this.message = '',
    this.nick,
  });

  final MusicLoginPhase phase;
  final MusicPlatform platform;

  /// 诊断标签（UI 映射为 ARB 文案，不直接展示服务端原文）。
  final String message;
  final String? nick;

  bool get busy => phase == MusicLoginPhase.saving;

  /// 是否已经结束（成功 / 取消 / 失败）——UI 据此收尾。
  bool get isFinished =>
      phase == MusicLoginPhase.succeeded || phase == MusicLoginPhase.cancelled || phase == MusicLoginPhase.failed;

  MusicLoginState copyWith({MusicLoginPhase? phase, MusicPlatform? platform, String? message, String? nick}) =>
      MusicLoginState(
        phase: phase ?? this.phase,
        platform: platform ?? this.platform,
        message: message ?? this.message,
        nick: nick ?? this.nick,
      );
}

/// 登录控制器：**只负责状态与落盘**，不直接碰 WebView。
///
/// WebView 由 UI 层（桌面子窗口 / 移动全屏页）驱动，把抓到的 Cookie 交给
/// [submitCookies]；这样控制器可以在没有 WebView 的测试环境里完整验证。
class MusicLoginController extends Notifier<MusicLoginState> {
  /// Cookie 抓取轮询间隔（与 miao-dock 的 2s 同口径）。
  static const pollInterval = Duration(seconds: 2);

  @override
  MusicLoginState build() => const MusicLoginState();

  /// 某个平台是否支持 WebView 登录。
  static bool supports(MusicPlatform platform) => supportsWebviewLogin(platform);

  /// 开始登录：记录目标平台，进入「等待用户在官方页面完成登录」。
  void begin(MusicPlatform platform) {
    if (!supports(platform)) {
      state = MusicLoginState(phase: MusicLoginPhase.failed, platform: platform, message: 'unsupported');
      return;
    }
    state = MusicLoginState(phase: MusicLoginPhase.awaiting, platform: platform);
  }

  /// WebView 轮询到 Cookie 后调用。
  ///
  /// 返回 true 表示「已登录并落盘」，调用方据此关闭登录窗口。
  Future<bool> submitCookies(Iterable<RawWebviewCookie> cookies) async {
    if (state.phase != MusicLoginPhase.awaiting) return false;
    final platform = state.platform;
    final config = webviewLoginConfigs[platform];
    if (config == null) return false;

    final collector = WebviewCookieCollector(config);
    // 酷狗用专用解析：登录票据主要在复合 Cookie KuGoo 里，通用判定漏判
    // （用户实测：窗口里已登录、应用一直等不到）。判定口径与 miao-dock 一致：
    // 有登录态即可收口，播放票据不足时由 warmup 补（见 launcher）。
    final ready = platform == MusicPlatform.kugou
        ? extractKugouCookieAuth(cookies.map((c) => (name: c.name, value: c.value)).toList()).loggedIn
        : collector.hasLogin(cookies);
    if (!ready) return false; // 还没登录完，继续等

    final cookie = collector.collect(cookies);
    if (cookie.isEmpty) return false;

    // 诊断：抓到票据时打印 names 与长度（不含值，避免泄漏凭据）。
    debugPrint(
      '[music.login] ticket hit: platform=$platform len=${cookie.length} '
      'names=${cookies.where((c) => config.ownsDomain(c.domain)).map((c) => c.name).toSet().toList()}',
    );

    state = state.copyWith(phase: MusicLoginPhase.saving);
    try {
      await ref.read(musicAuthProvider.notifier).save(platform, cookie);
    } on MusicCredentialStoreException {
      // 落盘失败：不假装登录成功（重启就掉线，比直接报错更难查）。
      state = state.copyWith(phase: MusicLoginPhase.failed, message: 'credential_store_failed');
      return false;
    }
    ref.read(musicAccountProvider.notifier).login(platform, '');
    state = state.copyWith(phase: MusicLoginPhase.succeeded);
    // 昵称只是展示增强：回读失败不影响登录态（头像兜底显示「?」）。
    unawaited(_fetchNick(platform, cookie));
    return true;
  }

  /// 回读昵称（仅网易云有稳定接口；其它平台留空，头像显示「?」）。
  Future<void> _fetchNick(MusicPlatform platform, String cookie) async {
    if (platform != MusicPlatform.netease) return;
    try {
      final info = await NeteaseApi(cookie: cookie).loginStatus();
      if (info.nick.isEmpty || !ref.mounted) return;
      ref.read(musicAccountProvider.notifier).login(platform, info.nick);
      state = state.copyWith(nick: info.nick);
    } on Object {
      // 拿不到昵称就算了：登录态已经成立。
    }
  }

  /// 用户关闭了登录窗口却仍未登录。
  void cancel() {
    if (state.phase == MusicLoginPhase.succeeded) return;
    if (state.phase == MusicLoginPhase.awaiting) {
      state = state.copyWith(phase: MusicLoginPhase.cancelled);
    }
  }

  void reset() => state = const MusicLoginState();
}

final musicLoginProvider = NotifierProvider<MusicLoginController, MusicLoginState>(MusicLoginController.new);
