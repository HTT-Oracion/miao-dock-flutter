import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/webview/webview_cookie.dart';
import '../domain/js_music_source.dart';
import '../domain/music_login_info.dart';
import '../domain/music_source_manifest.dart';
import 'music_providers.dart';
import '../data/webview/webview_login_config.dart';
import 'music_auth.dart';
import 'music_session.dart';

/// 登录流程阶段。
///
/// 登录统一走「打开平台官方登录页（WebView）→ 读取 Cookie → 源内校验 → 落盘」：
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

/// 源内登录态校验结果（[MusicLoginController] 内部用）。
enum _ProbeKind {
  /// 源未声明 `loginInfo` 能力（旧副本）——退回票据集判据「全到齐」。
  unsupported,

  /// 校验调用失败（网络 / 引擎异常）——不能据此判失效。
  error,

  /// 源确认 Cookie 有效。
  valid,

  /// 源明确判定 Cookie 还不足以登录（半张票 / 未完成登录）。
  incomplete,

  /// 同一串 Cookie 刚校验过，本轮不重复打接口。
  throttled,
}

/// 登录控制器：**只负责状态、校验与落盘**，不直接碰 WebView。
///
/// WebView 由 UI 层（桌面子窗口 / 移动全屏页）驱动，把抓到的 Cookie 交给
/// [submitCookies]；这样控制器可以在没有 WebView 的测试环境里完整验证。
///
/// ## 为什么收口要「源内校验」而不是「票据名任一出现」
/// miao-dock（Rust）各平台是按**播放/登录票据是否齐全**收口的：网易云要
/// MUSIC_U、酷狗要 userid+token、QQ 要 uin+music_key、咪咕要 queryUserInfo
/// 校验通过。旧实现「loginCookieNames 任一出现即落盘」会存下半张票（尤其
/// QQ 的 uin 先于 qm_keyst 下发），重启回读判失效 → 清凭据，用户看到的就是
/// 「登录成功、重启掉线」。现在平台逻辑在 JS 源里，判据也交给源：
/// Cookie 注入引擎 → 源 `loginInfo` 回 `loggedIn=true` 才落盘。
class MusicLoginController extends Notifier<MusicLoginState> {
  /// Cookie 抓取轮询间隔（与 miao-dock 的 2s 同口径）。
  static const pollInterval = Duration(seconds: 2);

  /// 同一串 Cookie 明确「未完成登录」后的重新校验间隔。
  ///
  /// 用于兜住接口瞬时异常（风控 / 网络抖动）：Cookie 没变时不必每拍都打接口，
  /// 但也不能永久钉死为未登录。
  static const probeRetryInterval = Duration(seconds: 30);

  String? _probePlatform;
  String? _probeCookie;
  DateTime? _probeAt;

  /// 落盘/校验在途标记：移动端三处触发（onPageStarted / onPageFinished / 2s Timer）
  /// 可能并发进入 submitCookies，非原子会造成重复 probe / 重复 save。
  bool _submitting = false;

  @override
  MusicLoginState build() => const MusicLoginState();

  /// 某个平台是否支持 WebView 登录。
  /// 该平台是否有 WebView 登录配置（内置四平台静态表 / 新平台的源内声明）。
  static bool supports(String platformId, {MusicSourceLoginConfig? declared}) =>
      supportsWebviewLogin(platformId, declared: declared);

  /// 找平台对应的已导入源（registry 内查）。
  JsMusicSource? _sourceFor(String platformId) {
    for (final candidate in ref.read(jsMusicSourceRegistryProvider)) {
      if (candidate.isAvailable && candidate.platformId == platformId) return candidate;
    }
    return null;
  }

  /// 找平台对应的源声明登录配置（registry 内查）。
  MusicSourceLoginConfig? _declaredLogin(String platformId) => _sourceFor(platformId)?.manifest.login;

  /// 开始登录：记录目标平台，进入「等待用户在官方页面完成登录」。
  void begin(String platformId) {
    if (!supports(platformId, declared: _declaredLogin(platformId))) {
      state = MusicLoginState(phase: MusicLoginPhase.failed, platformId: platformId, message: 'unsupported');
      return;
    }
    _resetProbeCache();
    state = MusicLoginState(phase: MusicLoginPhase.awaiting, platformId: platformId);
  }

  /// WebView 轮询到 Cookie 后调用。
  ///
  /// 返回 true 表示「已登录并落盘」，调用方据此关闭登录窗口。
  Future<bool> submitCookies(Iterable<RawWebviewCookie> cookies) async {
    // 🔴 并发保护：phase 在第一个 await 前尚未变 saving，仅靠 phase 判断拦不住
    // 移动端三处回调的同时进入（会重复 probe / 重复落盘）。
    if (_submitting || state.phase != MusicLoginPhase.awaiting) return false;
    _submitting = true;
    try {
      return await _submit(cookies);
    } finally {
      _submitting = false;
    }
  }

  Future<bool> _submit(Iterable<RawWebviewCookie> cookies) async {
    final platformId = state.platformId;
    final config = loginConfigFor(platformId, declared: _declaredLogin(platformId));
    if (config == null) return false;

    final collector = WebviewCookieCollector(config);
    final cookie = collector.collect(cookies);
    if (cookie.isEmpty) return false;

    final source = _sourceFor(platformId);
    final canValidate = source != null && source.capabilities.contains('loginInfo');
    // 旧源（副本早于 loginInfo 能力）：退回票据集判据，但要求**全到齐** ——
    // 任一票据就落盘会存半张票（重启回读判失效后清凭据）。旧源最坏是登录窗
    // 不自动关（5 分钟超时），比「假登录、重启掉线」可接受。
    if (!canValidate) {
      if (!collector.hasAllTickets(cookies)) return false;
      return _commit(platformId, cookie, null);
    }

    final probe = await _probe(platformId, source, cookie);
    switch (probe.kind) {
      case _ProbeKind.valid:
        return _commit(platformId, cookie, probe.info);
      case _ProbeKind.unsupported:
        // 走到这里说明能力位/退出瞬间不一致：退回票据集判据（要求全到齐）。
        if (!collector.hasAllTickets(cookies)) return false;
        return _commit(platformId, cookie, null);
      case _ProbeKind.incomplete:
      case _ProbeKind.throttled:
        // 半张票：launcher 会按 warmupUrl 导航补票，这里继续等下一拍。
        return false;
      case _ProbeKind.error:
        // 校验接口不通 ≠ Cookie 无效（miao-dock 的语义：探测失败不撤登录态）。
        // 票据名已全部到齐时按 Rust「先落盘、后校验」口径收口，避免网络抖动丢登录。
        if (!collector.hasAllTickets(cookies)) return false;
        debugPrint('[music.login] probe failed, commit by complete tickets: platform=$platformId');
        return _commit(platformId, cookie, null);
    }
  }

  /// 调源 `loginInfo` 校验 Cookie（Cookie 先注入引擎）。
  ///
  /// 同一串 Cookie 明确判「未完成」后 [probeRetryInterval] 内不重复打接口；
  /// 网络/引擎异常不缓存（下一拍重试）。
  Future<_LoginProbe> _probe(String platformId, JsMusicSource source, String cookie) async {
    final now = DateTime.now();
    final lastAt = _probeAt;
    final cached = _probePlatform == platformId && _probeCookie == cookie && lastAt != null;
    if (cached && now.difference(lastAt) < probeRetryInterval) {
      return const _LoginProbe(_ProbeKind.throttled);
    }
    try {
      final engine = ref.read(musicSourceEngineProvider);
      await engine.setSessionCookie(source, cookie);
      final info = await engine.loginInfo(source);
      if (info == null) return const _LoginProbe(_ProbeKind.error);
      _probePlatform = platformId;
      _probeCookie = cookie;
      _probeAt = now;
      debugPrint(
        '[music.login] probe: platform=$platformId loggedIn=${info.loggedIn} '
        'nick=${info.nick.isEmpty ? '-' : info.nick.length}',
      );
      return _LoginProbe(info.loggedIn ? _ProbeKind.valid : _ProbeKind.incomplete, info: info);
    } on Object catch (e) {
      debugPrint('[music.login] probe failed: platform=$platformId error=$e');
      return const _LoginProbe(_ProbeKind.error);
    }
  }

  /// 落盘 + 置登录态。返回 false 仅当落盘失败（已置 failed 态）。
  Future<bool> _commit(String platformId, String cookie, MusicLoginInfo? info) async {
    state = state.copyWith(phase: MusicLoginPhase.saving);
    try {
      await ref.read(musicAuthProvider.notifier).save(platformId, cookie);
    } on MusicCredentialStoreException {
      // 落盘失败：不假装登录成功（重启就掉线，比直接报错更难查）。
      state = state.copyWith(phase: MusicLoginPhase.failed, message: 'credential_store_failed');
      return false;
    }
    // 昵称 / 头像随落盘一起回填（来自源 loginInfo，避免再打一次接口）。
    ref.read(musicAccountProvider.notifier).login(platformId, info?.nick ?? '', avatarUrl: info?.avatarUrl);
    state = state.copyWith(phase: MusicLoginPhase.succeeded, nick: info?.nick);
    return true;
  }

  void _resetProbeCache() {
    _probePlatform = null;
    _probeCookie = null;
    _probeAt = null;
  }

  /// 用户关闭了登录窗口却仍未登录。
  void cancel() {
    if (state.phase == MusicLoginPhase.succeeded) return;
    if (state.phase == MusicLoginPhase.awaiting) {
      state = state.copyWith(phase: MusicLoginPhase.cancelled);
    }
  }

  void reset() {
    _resetProbeCache();
    state = const MusicLoginState();
  }
}

@immutable
class _LoginProbe {
  const _LoginProbe(this.kind, {this.info});

  final _ProbeKind kind;
  final MusicLoginInfo? info;
}

final musicLoginProvider = NotifierProvider<MusicLoginController, MusicLoginState>(MusicLoginController.new);
