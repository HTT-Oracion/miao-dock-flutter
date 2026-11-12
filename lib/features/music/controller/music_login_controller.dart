import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/netease_api.dart';
import '../domain/music_models.dart';
import 'music_auth.dart';
import 'music_session.dart';

/// 扫码登录阶段（与网易云 `client/login` 的 801/802/803/800 一一对应）。
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
  ///
  /// 失败态 / 提示态都从它派生；二维码图形渲染不在本层（见交付说明）。
  final String? gatewayUrl;
  final String message;
  final int secondsLeft;
  final String? nick;

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
    // 延迟到当前帧之后：弹窗先渲染「加载中」，下一帧再真正取 key。
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
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick(api, key));
    } on Object {
      state = state.copyWith(phase: MusicQrPhase.failed, message: 'qr_key_failed');
    }
  }

  Future<void> _tick(NeteaseApi api, String key) async {
    if (state.key != key) return;
    final left = state.secondsLeft - 2;
    if (left <= 0) {
      _poll?.cancel();
      state = state.copyWith(phase: MusicQrPhase.expired, secondsLeft: 0);
      return;
    }
    state = state.copyWith(secondsLeft: left);
    final result = await _tryCheck(api, key);
    if (result == null) return; // 单拍失败不打断：有效期 4 分钟，下一拍继续
    debugPrint('[music.login] code=${result.code} msg=${result.message} raw=${result.raw}');
    switch (result.code) {
      case 802:
        if (state.phase != MusicQrPhase.scanned) {
          state = state.copyWith(phase: MusicQrPhase.scanned);
        }
      case 803:
        _poll?.cancel();
        await _finishLogin(result.cookie);
      case 800:
        _poll?.cancel();
        state = state.copyWith(phase: MusicQrPhase.expired, secondsLeft: 0);
        return;
    }
  }

  Future<({int code, String message, String? cookie, String raw})?> _tryCheck(NeteaseApi api, String key) async {
    try {
      return await api.qrCheck(key);
    } on Object {
      return null;
    }
  }

  /// 803 收口：**先把 Cookie 落盘并置登录成功，再去补昵称**。
  ///
  /// 昵称是展示增强，`loginStatus` 失败（接口风控 / 老 Cookie）不能让用户
  /// 卡在「扫了码但没登录」——这正是之前扫码后应用状态不更新的根因。
  Future<void> _finishLogin(String? cookie) async {
    if (!NeteaseApi.cookieHasLogin(cookie)) {
      // 803 但没拿到 MUSIC_U：把实际收到的 cookie 名打进 message，便于定位是
      // 通道问题（只有 NMTID）还是服务端未授权。
      final names = cookie == null || cookie.isEmpty
          ? 'none'
          : cookie.split(';').map((e) => e.split('=').first.trim()).where((e) => e.isNotEmpty).join(',');
      state = state.copyWith(phase: MusicQrPhase.failed, message: 'cookie_missing:$names');
      return;
    }
    await ref.read(musicAuthProvider.notifier).save(MusicPlatform.netease, cookie!);
    ref.read(musicAccountProvider.notifier).login(MusicPlatform.netease, '');
    state = state.copyWith(phase: MusicQrPhase.succeeded);
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
