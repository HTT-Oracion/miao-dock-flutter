import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/music_qr_login.dart';
import '../data/api/netease_api.dart';
import '../data/api/qr_login_adapters.dart';
import '../domain/music_models.dart';
import 'music_auth.dart';
import 'music_session.dart';

/// 扫码登录阶段。
///
/// · [idle] 未开始；[loading] 正在取码；
/// · [waiting] 等待扫码；[scanned] 已扫码待手机确认；
/// · [succeeded] 登录完成；
/// · [expired] 二维码超时 —— **保持静止，等用户点重试**（不自动刷新）；
/// · [failed] 服务端拒绝（风控等）—— 同上，等用户重试；
/// · [unsupported] 该平台没有二维码登录能力（QQ / 咪咕）。
enum MusicQrPhase { idle, loading, waiting, scanned, succeeded, expired, failed, unsupported }

@immutable
class MusicQrState {
  const MusicQrState({
    this.phase = MusicQrPhase.idle,
    this.key,
    this.gatewayUrl,
    this.qrImageBase64,
    this.message = '',
    this.secondsLeft = 272,
    this.nick,
  });

  final MusicQrPhase phase;

  /// 平台二维码 key（扫码后用于轮询）。
  final String? key;

  /// 二维码内容（登录 URL）。
  final String? gatewayUrl;

  /// 平台直接给的二维码图（`data:image/png;base64,...`）；非空时优先显示它。
  final String? qrImageBase64;

  final String message;
  final int secondsLeft;
  final String? nick;

  /// 是否需要用户点「重试」：超时或失败都停在这里，**不自动换码**。
  bool get needsRetry => phase == MusicQrPhase.expired || phase == MusicQrPhase.failed;

  /// 登录已完成（弹窗应关闭）。
  bool get isDone => phase == MusicQrPhase.succeeded;

  MusicQrState copyWith({
    MusicQrPhase? phase,
    String? key,
    String? gatewayUrl,
    String? qrImageBase64,
    String? message,
    int? secondsLeft,
    String? nick,
  }) => MusicQrState(
    phase: phase ?? this.phase,
    key: key ?? this.key,
    gatewayUrl: gatewayUrl ?? this.gatewayUrl,
    qrImageBase64: qrImageBase64 ?? this.qrImageBase64,
    message: message ?? this.message,
    secondsLeft: secondsLeft ?? this.secondsLeft,
    nick: nick ?? this.nick,
  );
}

/// 二维码登录控制器：唯一允许触碰平台登录接口的地方（UI 只读 state）。
///
/// 平台差异收在 [QrLoginAdapter]：网易云走 EAPI 的 `unikey` + `client/login`，
/// 酷狗走 `login-user.kugou.com` 的 `/v2/qrcode` + `/v2/get_userinfo_qrcode`。
/// QQ / 咪咕的参考实现没有二维码登录，[qrLoginAdapterFor] 返回 null，UI 显示不支持。
class MusicLoginController extends Notifier<MusicQrState> {
  Timer? _poll;

  /// 轮询间隔。
  ///
  /// 🔴 官方文档明确警告「不要频繁调登录接口，不然可能会被风控」。此前是 2 秒一次
  /// （4 分钟窗口内 120 次），是 8821 风控的重要诱因之一；放宽到 5 秒后同窗口仅 48 次。
  static const pollInterval = Duration(seconds: 5);

  /// 适配器工厂（测试可替换，避免用例连真实站点）。
  @protected
  QrLoginAdapter? createAdapter(MusicPlatform platform, {String cookie = ''}) =>
      qrLoginAdapterFor(platform, cookie: cookie);

  @override
  MusicQrState build() {
    ref.onDispose(() => _poll?.cancel());
    return const MusicQrState();
  }

  Future<void> start(MusicPlatform platform) async {
    _poll?.cancel();
    final adapter = createAdapter(platform);
    if (adapter == null) {
      state = const MusicQrState(phase: MusicQrPhase.unsupported);
      return;
    }
    // 🔴 不能在 `initState` / `build` 期间同步改 provider（Riverpod 会抛
    // 「Tried to modify a provider while the widget tree was building」）。
    await Future<void>.delayed(Duration.zero);
    state = const MusicQrState(phase: MusicQrPhase.loading);
    try {
      final ticket = await adapter.requestTicket();
      state = MusicQrState(
        phase: MusicQrPhase.waiting,
        key: ticket.ticket,
        gatewayUrl: ticket.content,
        qrImageBase64: ticket.imageBase64,
      );
      _poll = Timer.periodic(pollInterval, (_) => _tick(adapter, ticket.ticket));
    } on Object {
      state = state.copyWith(phase: MusicQrPhase.failed, message: 'qr_key_failed');
    }
  }

  Future<void> _tick(QrLoginAdapter adapter, String key) async {
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

    final result = await _tryPoll(adapter, key);
    if (result == null) return; // 单拍失败不打断：有效期 4 分钟，下一拍继续
    switch (result.state) {
      case QrPollState.waiting:
        // 若之前误标成 scanned（用户取消授权），退回 waiting。
        if (state.phase == MusicQrPhase.scanned) {
          state = state.copyWith(phase: MusicQrPhase.waiting);
        }
      case QrPollState.scanned:
        if (state.phase != MusicQrPhase.scanned) {
          state = state.copyWith(phase: MusicQrPhase.scanned);
        }
      case QrPollState.success:
        _poll?.cancel();
        await _finishLogin(adapter.platform, result.cookie, result.nick);
      case QrPollState.expired:
        _poll?.cancel();
        state = state.copyWith(phase: MusicQrPhase.expired, secondsLeft: 0);
      case QrPollState.rejected:
        // 8821 风控 / 其它业务拒绝：立即收口，不空等到超时。
        _poll?.cancel();
        state = state.copyWith(phase: MusicQrPhase.failed, message: 'risk_control');
    }
  }

  Future<QrLoginPoll?> _tryPoll(QrLoginAdapter adapter, String key) async {
    try {
      return await adapter.poll(key);
    } on Object {
      return null;
    }
  }

  /// 登录成功收口：**先把 Cookie 落盘并置登录成功，再去补昵称**。
  Future<void> _finishLogin(MusicPlatform platform, String? cookie, String? nickFromPoll) async {
    // 各平台的登录票据字段不同：网易云认 `MUSIC_U`，酷狗认 `token` + `userid`。
    final valid = switch (platform) {
      MusicPlatform.netease => NeteaseApi.cookieHasLogin(cookie),
      _ => cookie != null && cookie.contains('token=') && cookie.contains('userid='),
    };
    if (!valid) {
      final names = cookie == null || cookie.isEmpty
          ? 'none'
          : cookie.split(';').map((e) => e.split('=').first.trim()).where((e) => e.isNotEmpty).join(',');
      state = state.copyWith(phase: MusicQrPhase.failed, message: 'cookie_missing:$names');
      return;
    }
    try {
      await ref.read(musicAuthProvider.notifier).save(platform, cookie!);
    } on MusicCredentialStoreException {
      // 落盘失败：不要假装登录成功（重启就掉线，用户会以为登录坏了）。
      state = state.copyWith(phase: MusicQrPhase.failed, message: 'credential_store_failed');
      return;
    }
    final initial = nickFromPoll ?? '';
    ref.read(musicAccountProvider.notifier).login(platform, initial);
    state = state.copyWith(phase: MusicQrPhase.succeeded, nick: initial.isEmpty ? null : initial);
    // 平台已带昵称就不再额外请求；没带才补一次（失败也只是缺昵称）。
    if (initial.isNotEmpty) return;
    final nick = await _fetchNick(platform, cookie);
    if (nick.isEmpty) return;
    ref.read(musicAccountProvider.notifier).login(platform, nick);
    state = state.copyWith(nick: nick);
  }

  Future<String> _fetchNick(MusicPlatform platform, String cookie) async {
    try {
      // 目前只有网易云能稳定回读昵称；其它平台留空（只影响展示）。
      if (platform != MusicPlatform.netease) return '';
      final info = await NeteaseApi(cookie: cookie).loginStatus();
      return info.nick;
    } on Object {
      return '';
    }
  }

  void reset() {
    _poll?.cancel();
    state = const MusicQrState();
  }
}

final musicLoginProvider = NotifierProvider<MusicLoginController, MusicQrState>(MusicLoginController.new);
