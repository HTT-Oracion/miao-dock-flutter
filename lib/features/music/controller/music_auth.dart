import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_store.dart';
import '../domain/music_models.dart';

/// 四平台登录 Cookie 的内存态 + 安全存储（D-047：凭据不进偏好明文）。
///
/// 只存 **Cookie 字符串**，不存账号昵称之类可再取的数据 —— 昵称由
/// `loginStatus()` 现取，避免两份事实源不一致。
@immutable
class MusicAuthState {
  const MusicAuthState({this.cookies = const {}, this.loading = true});

  final Map<MusicPlatform, String> cookies;

  /// 首次从安全存储读盘期间为 true（UI 据此避免先闪「未登录」）。
  final bool loading;

  String? cookieOf(MusicPlatform p) => cookies[p];

  MusicAuthState copyWith({Map<MusicPlatform, String>? cookies, bool? loading}) =>
      MusicAuthState(cookies: cookies ?? this.cookies, loading: loading ?? this.loading);
}

class MusicAuthNotifier extends Notifier<MusicAuthState> {
  static const _keyPrefix = 'music.cookie.';

  final SecureStore _store = SecureStore();

  @override
  MusicAuthState build() {
    _restore();
    return const MusicAuthState();
  }

  Future<void> _restore() async {
    final restored = <MusicPlatform, String>{};
    for (final p in MusicPlatform.values.where((p) => p != MusicPlatform.local)) {
      final v = await _store.read('$_keyPrefix${p.name}');
      if (v != null && v.isNotEmpty) restored[p] = v;
    }
    state = state.copyWith(cookies: restored, loading: false);
  }

  Future<void> save(MusicPlatform p, String cookie) async {
    if (cookie.trim().isEmpty) return;
    state = state.copyWith(cookies: {...state.cookies, p: cookie});
    await _store.write('$_keyPrefix${p.name}', cookie);
  }

  Future<void> clear(MusicPlatform p) async {
    final next = {...state.cookies}..remove(p);
    state = state.copyWith(cookies: next);
    await _store.delete('$_keyPrefix${p.name}');
  }
}

final musicAuthProvider = NotifierProvider<MusicAuthNotifier, MusicAuthState>(MusicAuthNotifier.new);
