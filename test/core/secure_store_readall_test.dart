import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/storage/secure_store.dart';
import 'package:miao_dock_flutter/features/music/controller/music_auth.dart';

/// SecureStore 的键命名空间契约（D-047 配套回归）。
///
/// 生产口径：真实底层存储里的键带 `miao.` 前缀，而 `FlutterSecureStorage.readAll()`
/// 返回的是**原始键**（仍带前缀）。若 `SecureStore.readAll()` 直接透传，
/// `MusicAuthNotifier._restore()` 用相对键前缀 `music.cookie.` 过滤会永远匹配不到
/// → 表现为「登录成功，重启掉线」。
///
/// 反证锚点：把 `SecureStore.readAll()` 改回 `_storage.readAll()` 透传后，
/// 「readAll 返回相对键」与「启动恢复登录态」两条用例立即失败。
void main() {
  group('SecureStore 键命名空间', () {
    test('write/read/delete 落到原始存储时带 miao. 前缀', () async {
      final raw = _FakeSecureStorage();
      final store = SecureStore(storage: raw);

      await store.write('music.cookie.netease', 'MUSIC_U=abc');

      // (a) 原始键确实带命名空间前缀，且不是裸相对键。
      expect(raw.keys, contains('miao.music.cookie.netease'));
      expect(raw.keys, isNot(contains('music.cookie.netease')));
      expect(raw.raw['miao.music.cookie.netease'], 'MUSIC_U=abc');

      expect(await store.read('music.cookie.netease'), 'MUSIC_U=abc');
      await store.delete('music.cookie.netease');
      expect(raw.keys, isNot(contains('miao.music.cookie.netease')));
    });

    test('readAll 返回去掉前缀的相对键，并过滤命名空间外的条目', () async {
      final raw = _FakeSecureStorage({
        'miao.music.cookie.netease': 'MUSIC_U=abc',
        'miao.cred.youdaoZhiYun.key': 'app-key',
        'other.app.token': '外部键不得泄漏',
        'miao.': '只有前缀：相对键为空，过滤',
      });
      final store = SecureStore(storage: raw);

      // (b) 键为相对键（可直接与 read/write/delete 的入参口径对齐）。
      expect(await store.readAll(), {'music.cookie.netease': 'MUSIC_U=abc', 'cred.youdaoZhiYun.key': 'app-key'});
    });

    test('存储后端异常时 readAll 返回空表，不把启动搞崩', () async {
      final store = SecureStore(storage: _ThrowingSecureStorage());
      expect(await store.readAll(), isEmpty);
    });
  });

  group('登录态恢复链路（生产口径：原始键带 miao. 前缀）', () {
    test('raw 预置 miao.music.cookie.* → 启动后 cookieOf 恢复且 loading=false', () async {
      final raw = _FakeSecureStorage({
        'miao.music.cookie.netease': 'MUSIC_U=netease',
        'miao.music.cookie.kugou': 'kg_mid=kugou',
        'miao.music.cookie.local': '本地占位键，不算登录态',
        'other.app.token': '外部键不得进入内存态',
      });
      final container = ProviderContainer(
        overrides: [musicAuthProvider.overrideWith(() => _TestAuth(SecureStore(storage: raw)))],
      );
      addTearDown(container.dispose);

      container.read(musicAuthProvider); // 触发 build → _restore()
      await _waitForRestore(container);

      final state = container.read(musicAuthProvider);
      // (c) 重启后登录态必须恢复：这是「登录成功→重启掉线」的直接反证。
      expect(state.loading, isFalse);
      expect(state.cookieOf('netease'), 'MUSIC_U=netease');
      expect(state.cookieOf('kugou'), 'kg_mid=kugou');
      expect(state.cookieOf('local'), isNull); // _restore 显式跳过本地占位键
      expect(state.cookies.keys, isNot(contains('app.token'))); // 外部键不泄漏
    });
  });
}

/// 等 `_restore()` 落定（loading 变 false）。读盘是异步的，轮询避免依赖固定延时。
Future<void> _waitForRestore(ProviderContainer container) async {
  for (var i = 0; i < 200; i++) {
    if (!container.read(musicAuthProvider).loading) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('启动读盘超时：loading 一直为 true');
}

class _TestAuth extends MusicAuthNotifier {
  _TestAuth(this._store);

  final SecureStore _store;

  @override
  SecureStore createStore() => _store;
}

/// 假底层存储：直接持有**原始键**（与真实插件一致，前缀由 SecureStore 负责）。
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage([Map<String, String>? initial]) : raw = {...?initial};

  final Map<String, String> raw;

  Iterable<String> get keys => raw.keys;

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map<String, String>.from(raw);

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => raw[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      raw.remove(key);
    } else {
      raw[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    raw.remove(key);
  }
}

/// 底层存储完全不可用（插件缺失 / libsecret 缺失）。
class _ThrowingSecureStorage extends FlutterSecureStorage {
  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('secure storage unavailable');
}
