import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/netease_api.dart';
import '../domain/music_models.dart';
import 'music_auth.dart';
import 'music_session.dart';

/// 扫码登录阶段。
///
/// · [idle] 未开始；[loading] 正在取 key；
/// · [waiting] 等待扫码；[scanned] 已扫码待手机确认；
/// · [succeeded] 登录完成；
/// · [expired] 二维码超时 —— **保持静止，等用户点重试**（不自动刷新）；
/// · [failed] 服务端拒绝（风控等）—— 同上，等用户重试。
enum MusicQrPhase { idle, loading, waiting, scanned, succeeded, expired, failed }

@immutable
class MusicQrState {
  const MusicQrState({
    this.phase = MusicQrPhase.idle,
    this.key,
    this.gatewayUrl,
    this.message = '',
    this.secondsLeft = 272,
    this.nick,
  });

  final MusicQrPhase phase;

  /// 平台二维码 key（扫码后用于轮询）。
  final String? key;

  /// 扫码目标 URL（`https://music.163.com/login?codekey=...`）。
  final String? gatewayUrl;
  final String message;
  final int secondsLeft;
  final String? nick;

  /// 是否需要用户点「重试」：超时或失败都停在这里，**不自动换码**。
  ///
  /// 为什么不自动刷新：二维码有 4 分钟有效期，自动换码会让用户正在扫的那张
  /// 突然失效（"扫了没反应"）；且频繁调登录接口会触发风控。
  bool get needsRetry => phase == MusicQrPhase.expired || phase == MusicQrPhase.failed;

  /// 登录已完成（弹窗应关闭）。
  bool get isDone => phase == MusicQrPhase.succeeded;

  MusicQrState copyWith({
    MusicQrPhase? phase,
    String? key,
    String? gatewayUrl,
    String? message,
    int? secondsLeft,
    String? nick,
  }) => MusicQrState(
    phase: phase ?? this.phase,
    key: key ?? this.key,
    gatewayUrl: gatewayUrl ?? this.gatewayUrl,
    message: message ?? this.message,
    secondsLeft: secondsLeft ?? this.secondsLeft,
    nick: nick ?? this.nick,
  );
}

/// 二维码登录控制器：唯一允许触碰平台登录接口的地方（UI 只读 state）。
///
/// 只对**网易云**实现真实扫码：其余三家的上游登录是网页 Cookie 回读或
/// 手机号 + 验证码，属独立能力，本期不伪造入口。
class MusicLoginController extends Notifier<MusicQrState> {
  Timer? _poll;

  /// 轮询间隔。
  ///
  /// 🔴 官方文档明确警告「不要频繁调登录接口，不然可能会被风控」。此前是 2 秒一次
  /// （4 分钟窗口内 120 次），是 8821 风控的重要诱因之一；放宽到 5 秒后同窗口仅 48 次。
  static const pollInterval = Duration(seconds: 5);

  /// 接口工厂（测试可替换，避免用例连真实站点）。
  @protected
  NeteaseApi createApi({String cookie = ''}) => NeteaseApi(cookie: cookie);

  @override
  MusicQrState build() {
    ref.onDispose(() => _poll?.cancel());
    return const MusicQrState();
  }

  Future<void> start(MusicPlatform platform) async {
    _poll?.cancel();
    if (platform != MusicPlatform.netease) {
      state = const MusicQrState(phase: MusicQrPhase.idle);
      return;
    }
    // 🔴 不能在 `initState` / `build` 期间同步改 provider（Riverpod 会抛
    // 「Tried to modify a provider while the widget tree was building」）。
    await Future<void>.delayed(Duration.zero);
    state = const MusicQrState(phase: MusicQrPhase.loading);
    final api = createApi();
    try {
      final key = await api.qrKey();
      state = MusicQrState(
        phase: MusicQrPhase.waiting,
        key: key,
        gatewayUrl: 'https://music.163.com/login?codekey=$key',
      );
      _poll = Timer.periodic(pollInterval, (_) => _tick(api, key));
    } on Object {
      state = state.copyWith(phase: MusicQrPhase.failed, message: 'qr_key_failed');
    }
  }

  Future<void> _tick(NeteaseApi api, String key) async {
    if (state.key != key) return;
    // 已进入终态（成功 / 超时 / 失败）就不再计时、不再请求。
    if (state.phase == MusicQrPhase.succeeded) return;
    if (state.needsRetry) {
      _poll?.cancel();
      return;
    }
    final left = state.secondsLeft - pollInterval.inSeconds;
    if (left <= 0) {
      _poll?.cancel();
      // 🔴 超时**不自动刷新**：停在这一屏等用户点重试。
      state = state.copyWith(phase: MusicQrPhase.expired, secondsLeft: 0);
      return;
    }
    state = state.copyWith(secondsLeft: left);
    final result = await _tryCheck(api, key);
    if (result == null) return; // 单拍失败不打断：有效期 4 分钟，下一拍继续
    debugPrint('[music.login] code=${result.code} msg=${result.message} raw=${result.raw}');
    switch (result.code) {
      case 801:
        // 等待扫码：若之前误标成 scanned（用户取消授权），退回 waiting。
        if (state.phase == MusicQrPhase.scanned) {
          state = state.copyWith(phase: MusicQrPhase.waiting);
        }
      case 802:
        if (state.phase != MusicQrPhase.scanned) {
          state = state.copyWith(phase: MusicQrPhase.scanned);
        }
      case 803:
        _poll?.cancel();
        await _finishLogin(result.cookie, result.nick);
      case 800:
        _poll?.cancel();
        state = state.copyWith(phase: MusicQrPhase.expired, secondsLeft: 0);
      case 502:
        // 文档：扫码后返回 502 时需带 noCookie 再查一次。
        final retried = await _tryCheck(api, key, noCookie: true);
        if (retried == null) return;
        debugPrint('[music.login] noCookie retry code=${retried.code} raw=${retried.raw}');
        await _handleCode(api, key, retried);
      default:
        // 其余业务码（8821 风控 / 8811 等）必须**立即收口**：之前落在 default 分支
        // 被静默忽略，界面只会空转到超时，用户完全不知道发生了什么。
        if (result.code > 0) {
          _poll?.cancel();
          state = state.copyWith(phase: MusicQrPhase.failed, message: _codeMessage(result.code));
        }
    }
  }

  /// 502 重试后的结果按同一套码处理（避免重复写分支）。
  Future<void> _handleCode(
    NeteaseApi api,
    String key,
    ({int code, String message, String? cookie, String? nick, String raw}) r,
  ) async {
    switch (r.code) {
      case 802 || 803:
        if (r.code == 803) {
          _poll?.cancel();
          await _finishLogin(r.cookie, r.nick);
        } else if (state.phase != MusicQrPhase.scanned) {
          state = state.copyWith(phase: MusicQrPhase.scanned);
        }
      case 800:
        _poll?.cancel();
        state = state.copyWith(phase: MusicQrPhase.expired, secondsLeft: 0);
      default:
        if (r.code > 0) {
          _poll?.cancel();
          state = state.copyWith(phase: MusicQrPhase.failed, message: _codeMessage(r.code));
        }
    }
  }

  /// 业务码 → 归因标签（UI 映射到 ARB 文案，不直接展示服务端 message）。
  static String _codeMessage(int code) => switch (code) {
    8821 => 'risk_control',
    8811 => 'risk_control',
    800 => 'expired',
    502 => 'network',
    _ => 'unknown:$code',
  };

  Future<({int code, String message, String? cookie, String? nick, String raw})?> _tryCheck(
    NeteaseApi api,
    String key, {
    bool noCookie = false,
  }) async {
    try {
      return await api.qrCheck(key, noCookie: noCookie);
    } on Object {
      return null;
    }
  }

  /// 803 收口：**先把 Cookie 落盘并置登录成功，再去补昵称**。
  ///
  /// 昵称是展示增强，`loginStatus` 失败不能让用户卡在「扫了码但没登录」。
  Future<void> _finishLogin(String? cookie, String? nickFromCheck) async {
    if (!NeteaseApi.cookieHasLogin(cookie)) {
      // 803 但没拿到 MUSIC_U：把实际收到的 cookie 名打进 message，便于定位是
      // 通道问题（只有 NMTID）还是服务端未授权。
      final names = cookie == null || cookie.isEmpty
          ? 'none'
          : cookie.split(';').map((e) => e.split('=').first.trim()).where((e) => e.isNotEmpty).join(',');
      state = state.copyWith(phase: MusicQrPhase.failed, message: 'cookie_missing:$names');
      return;
    }
    try {
      await ref.read(musicAuthProvider.notifier).save(MusicPlatform.netease, cookie!);
    } on MusicCredentialStoreException {
      // 落盘失败：不要假装登录成功（重启就掉线，用户会以为登录坏了）。
      state = state.copyWith(phase: MusicQrPhase.failed, message: 'credential_store_failed');
      return;
    }
    final initial = nickFromCheck ?? '';
    ref.read(musicAccountProvider.notifier).login(MusicPlatform.netease, initial);
    state = state.copyWith(phase: MusicQrPhase.succeeded, nick: initial.isEmpty ? null : initial);
    // 803 已带昵称就不再打 loginStatus；没带才补一次（失败也只是缺昵称）。
    if (initial.isNotEmpty) return;
    final nick = await _fetchNick(cookie);
    if (nick.isEmpty) return;
    ref.read(musicAccountProvider.notifier).login(MusicPlatform.netease, nick);
    state = state.copyWith(nick: nick);
  }

  Future<String> _fetchNick(String cookie) async {
    try {
      final info = await createApi(cookie: cookie).loginStatus();
      return info.nick;
    } on Object {
      return '';
    }
  }

  void reset() {
    _poll?.cancel();
    final key = state.key;
    if (key != null) createApi().dropQrCookies(key);
    state = const MusicQrState();
  }
}

final musicLoginProvider = NotifierProvider<MusicLoginController, MusicQrState>(MusicLoginController.new);
