import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/storage/secure_store.dart';
import 'package:miao_dock_flutter/features/music/controller/music_auth.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';

/// 启动读盘与登录写入的竞态。
///
/// 破坏点（修复前真实存在，曾导致「登录完成后应用仍显示未登录」）：
/// · `_restore()` 用 `copyWith(cookies: restored)` **整体替换**内存态 →
///   登录刚写入的 Cookie 被启动时读到的空值覆盖。把 `_restore` 改回整体替换，
///   第一条用例立即失败。
/// · `save()` 不回读校验 → Keychain 静默失败时仍报登录成功。
void main() {
  test('慢 _restore 不得覆盖登录写入的 cookie', () async {
    final store = _MemoryStore()..gate = Completer<void>();
    final c = ProviderContainer(overrides: [musicAuthProvider.overrideWith(() => _TestAuth(store))]);

    // 触发 build → _restore 开始，第一次 read 挂在 gate 上（已取旧快照 = 空）。
    c.read(musicAuthProvider);

    // 挂起期间完成登录写入。
    await c.read(musicAuthProvider.notifier).save(MusicPlatform.netease, 'MUSIC_U=real');
    expect(c.read(musicAuthProvider).cookieOf(MusicPlatform.netease), 'MUSIC_U=real');

    // 放行读盘：它带回的是登录前的空快照。
    store.gate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // 破坏点：_restore 整体替换 → 这里回退成 null（登录状态丢失）。
    expect(c.read(musicAuthProvider).cookieOf(MusicPlatform.netease), 'MUSIC_U=real');
    c.dispose();
  });

  test('存储写不进去时报错，不假装登录成功', () async {
    final store = _MemoryStore(rejectWrites: true);
    final c = ProviderContainer(overrides: [musicAuthProvider.overrideWith(() => _TestAuth(store))]);
    addTearDown(c.dispose);

    // 破坏点：去掉回读校验 → 这里不会抛，登录会在重启后静默失效。
    await expectLater(
      c.read(musicAuthProvider.notifier).save(MusicPlatform.netease, 'MUSIC_U=real'),
      throwsA(isA<MusicCredentialStoreException>()),
    );
    expect(c.read(musicAuthProvider).cookieOf(MusicPlatform.netease), isNull);
  });
}

class _TestAuth extends MusicAuthNotifier {
  _TestAuth(this._s);

  final SecureStore _s;

  @override
  SecureStore createStore() => _s;
}

/// 内存仓库：可延迟读、可拒绝写。
/// 内存仓库：`read` 可以挂起，用于精确制造「读盘慢于登录写入」的时序。
///
/// 关键：`_restore()` 会依次读四个平台。这里让**第一个** read 挂起，
/// 期间执行登录写入，再放行 —— 复现的是「读到的快照早于写入」这一真实竞态
/// （真实场景：Keychain 冷启动慢 / 用户很快完成登录）。
class _MemoryStore implements SecureStore {
  _MemoryStore({this.rejectWrites = false});

  final bool rejectWrites;
  final Map<String, String> _data = {};

  /// 非空时，第一次 read 会等待它被 complete。
  Completer<void>? gate;
  bool _firstRead = true;

  @override
  Future<String?> read(String key) async {
    if (gate != null && _firstRead) {
      _firstRead = false;
      final snapshot = _data[key]; // 先取快照（此时还没有登录写入）
      await gate!.future; // 挂起，等测试放行
      return snapshot; // 返回**旧快照**，模拟慢读
    }
    return _data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (rejectWrites) return; // 模拟 Keychain 拒绝：静默不写
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> migrateServiceName() async {}
}
