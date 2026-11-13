import 'dart:async' show unawaited;

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

  /// 存储实现（测试覆盖为内存替身）。
  @protected
  SecureStore createStore() => SecureStore();

  late final SecureStore _store = createStore();

  @override
  MusicAuthState build() {
    // 服务名迁移（旧 flutter_secure_storage_service → 喵坞）：只跑一次，失败不阻断。
    unawaited(_store.migrateServiceName());
    _restore();
    return const MusicAuthState();
  }

  /// 启动读盘。
  ///
  /// 🔴 必须**合并**到当前内存态，不能整体替换：读盘是异步的，而扫码登录可能
  /// 在它返回前就完成了 `save()`。整体替换会把刚写入的登录 Cookie 覆盖成启动时
  /// 读到的旧值（空），表现为「手机显示登录成功、应用仍是未登录」。
  /// 只在本轮修复前，这一行为是扫码登录失败的真因之一。
  Future<void> _restore() async {
    final restored = <MusicPlatform, String>{};
    for (final p in MusicPlatform.values.where((p) => p != MusicPlatform.local)) {
      final v = await _store.read('$_keyPrefix${p.name}');
      if (v != null && v.isNotEmpty) restored[p] = v;
    }
    if (!ref.mounted) return; // 读盘期间 provider 可能已释放
    state = state.copyWith(
      // 内存态优先（期间可能已登录 / 已登出）。
      cookies: {...restored, ...state.cookies},
      loading: false,
    );
  }

  Future<void> save(MusicPlatform p, String cookie) async {
    if (cookie.trim().isEmpty) return;
    state = state.copyWith(cookies: {...state.cookies, p: cookie});
    await _store.write('$_keyPrefix${p.name}', cookie);
    // 写盘后再回读校验：某些平台（缺 keychain 权限）会静默失败，
    // 不校验的话用户会看到「已登录」而重启后消失。
    final readBack = await _store.read('$_keyPrefix${p.name}');
    if (readBack == null || readBack.isEmpty) {
      // 诊断：把期望长度带出来，能区分「完全没写入」与「写入被截断」。
      debugPrint(
        '[music.auth] keychain read-back empty: platform=${p.name} '
        'expectedLen=${cookie.length} key=$_keyPrefix${p.name}',
      );
      state = state.copyWith(cookies: {...state.cookies}..remove(p));
      throw const MusicCredentialStoreException();
    }
    if (readBack != cookie) {
      debugPrint('[music.auth] keychain read-back mismatch: got ${readBack.length} chars, expected ${cookie.length}');
    }
  }

  Future<void> clear(MusicPlatform p) async {
    final next = {...state.cookies}..remove(p);
    state = state.copyWith(cookies: next);
    await _store.delete('$_keyPrefix${p.name}');
  }
}

/// 凭据落盘失败（Keychain / Credential Manager 不可用或被拒）。
///
/// 与"接口失败"区分：这类失败重试网络没用，必须提示用户检查系统权限。
class MusicCredentialStoreException implements Exception {
  const MusicCredentialStoreException();

  @override
  String toString() => 'MusicCredentialStoreException: credential was not persisted';
}

final musicAuthProvider = NotifierProvider<MusicAuthNotifier, MusicAuthState>(MusicAuthNotifier.new);
