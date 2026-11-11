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
/// 只对**网易云**实现真实扫码：其余三家（酷狗 / QQ / 咪咕）的上游登录是
/// 网页 Cookie 回读或手机号+验证码，属独立能力，本期不伪造入口 —— 它们的
/// 登录弹窗仍走演示流程，但线上仓库拿不到 Cookie 时会如实提示需要登录。
class MusicLoginController extends Notifier<MusicQrState> {
  Timer? _poll;

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
    final api = NeteaseApi();
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
    try {
      final r = await api.qrCheck(key);
      switch (r.code) {
        case 802:
          if (state.phase != MusicQrPhase.scanned) {
            state = state.copyWith(phase: MusicQrPhase.scanned);
          }
        case 803:
          final cookie = r.cookie;
          if (cookie == null || cookie.isEmpty) {
            state = state.copyWith(phase: MusicQrPhase.failed, message: 'cookie_missing');
            _poll?.cancel();
            return;
          }
          _poll?.cancel();
          await ref.read(musicAuthProvider.notifier).save(MusicPlatform.netease, cookie);
          final info = await NeteaseApi(cookie: cookie).loginStatus();
          ref.read(musicAccountProvider.notifier).login(MusicPlatform.netease, info.nick);
          state = state.copyWith(phase: MusicQrPhase.succeeded, nick: info.nick);
        case 800:
          _poll?.cancel();
          state = state.copyWith(phase: MusicQrPhase.expired, secondsLeft: 0);
      }
    } on Object {
      // 单拍失败不打断：扫码有效期 4 分钟，下一拍继续。
    }
  }

  void reset() {
    _poll?.cancel();
    state = const MusicQrState();
  }
}

final musicLoginProvider = NotifierProvider<MusicLoginController, MusicQrState>(MusicLoginController.new);
