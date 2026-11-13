import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/webview/webview_cookie.dart';
import '../domain/js_music_source.dart';
import '../domain/music_source_manifest.dart';
import 'music_providers.dart';
import '../data/webview/webview_login_config.dart';
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
  const MusicLoginState({this.phase = MusicLoginPhase.idle, this.platformId = 'netease', this.message = '', this.nick});

  final MusicLoginPhase phase;

  /// 目标平台 id（字符串身份）。
  final String platformId;

  /// 诊断标签（UI 映射为 ARB 文案，不直接展示服务端原文）。
  final String message;
  final String? nick;

  bool get busy => phase == MusicLoginPhase.saving;

  /// 是否已经结束（成功 / 取消 / 失败）——UI 据此收尾。
  bool get isFinished =>
      phase == MusicLoginPhase.succeeded || phase == MusicLoginPhase.cancelled || phase == MusicLoginPhase.failed;

  MusicLoginState copyWith({MusicLoginPhase? phase, String? platformId, String? message, String? nick}) =>
      MusicLoginState(
        phase: phase ?? this.phase,
        platformId: platformId ?? this.platformId,
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
  /// 该平台是否有 WebView 登录配置（内置四平台静态表 / 新平台的源内声明）。
  static bool supports(String platformId, {MusicSourceLoginConfig? declared}) =>
      supportsWebviewLogin(platformId, declared: declared);

  /// 找平台对应的源声明登录配置（registry 内查）。
  MusicSourceLoginConfig? _declaredLogin(String platformId) {
    for (final candidate in ref.read(jsMusicSourceRegistryProvider)) {
      if (candidate.isAvailable && candidate.platformId == platformId) {
        return candidate.manifest.login;
      }
    }
    return null;
  }

  /// 开始登录：记录目标平台，进入「等待用户在官方页面完成登录」。
  void begin(String platformId) {
    if (!supports(platformId, declared: _declaredLogin(platformId))) {
      state = MusicLoginState(phase: MusicLoginPhase.failed, platformId: platformId, message: 'unsupported');
      return;
    }
    state = MusicLoginState(phase: MusicLoginPhase.awaiting, platformId: platformId);
  }

  /// WebView 轮询到 Cookie 后调用。
  ///
  /// 返回 true 表示「已登录并落盘」，调用方据此关闭登录窗口。
  Future<bool> submitCookies(Iterable<RawWebviewCookie> cookies) async {
    if (state.phase != MusicLoginPhase.awaiting) return false;
    final platformId = state.platformId;
    final config = loginConfigFor(platformId, declared: _declaredLogin(platformId));
    if (config == null) return false;

    final collector = WebviewCookieCollector(config);
    // 酷狗用专用解析：登录票据主要在复合 Cookie KuGoo 里，通用判定漏判
    // （用户实测：窗口里已登录、应用一直等不到）。判定口径与 miao-dock 一致：
    // 有登录态即可收口，播放票据不足时由 warmup 补（见 launcher）。
    // ready 判定泛化：登录票据名**任一出现**即视为已登录（对齐 miao-dock logged_in）。
    // 酷狗的 KuGoo 复合票据由 loginCookieNames 覆盖（token,userid）—— 名单在配置里。
    final ready = collector.hasLogin(cookies);
    if (!ready) return false; // 还没登录完，继续等

    final cookie = collector.collect(cookies);
    if (cookie.isEmpty) return false;

    // 诊断：抓到票据时打印 names 与长度（不含值，避免泄漏凭据）。
    debugPrint(
      '[music.login] ticket hit: platform=$platformId len=${cookie.length} '
      'names=${cookies.where((c) => config.ownsDomain(c.domain)).map((c) => c.name).toSet().toList()}',
    );

    state = state.copyWith(phase: MusicLoginPhase.saving);
    try {
      await ref.read(musicAuthProvider.notifier).save(platformId, cookie);
    } on MusicCredentialStoreException {
      // 落盘失败：不假装登录成功（重启就掉线，比直接报错更难查）。
      state = state.copyWith(phase: MusicLoginPhase.failed, message: 'credential_store_failed');
      return false;
    }
    ref.read(musicAccountProvider.notifier).login(platformId, '');
    state = state.copyWith(phase: MusicLoginPhase.succeeded);
    // 昵称只是展示增强：回读失败不影响登录态（头像兜底显示「?」）。
    unawaited(_fetchNick(platformId, cookie));
    return true;
  }

  /// 回读昵称：走当前平台的 JS 源 `loginInfo` 能力（Cookie 先注入引擎）。
  /// 源未声明该能力 / 无该平台源时跳过（头像显示「?」）。
  Future<void> _fetchNick(String platformId, String cookie) async {
    try {
      JsMusicSource? source;
      for (final candidate in ref.read(jsMusicSourceRegistryProvider)) {
        if (candidate.isAvailable && candidate.platformId == platformId) {
          source = candidate;
          break;
        }
      }
      if (source == null || source.capabilities.contains('loginInfo') == false) return;
      final engine = ref.read(musicSourceEngineProvider);
      await engine.setSessionCookie(source, cookie);
      final info = await engine.loginInfo(source);
      if (info == null || !info.loggedIn || info.nick.isEmpty || !ref.mounted) return;
      ref.read(musicAccountProvider.notifier).login(platformId, info.nick);
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
