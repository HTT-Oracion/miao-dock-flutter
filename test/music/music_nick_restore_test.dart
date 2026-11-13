import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/controller/music_auth.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';
import 'package:miao_dock_flutter/features/music/data/api/netease_api.dart';

/// Cookie 从 Keychain 恢复后，昵称必须回读补齐。
///
/// 破坏点（用户实测）：重启 / 进音乐模块时 Cookie 恢复成功（弹 Keychain 授权、
/// logged=true），但昵称只存内存 —— 头像与右上角永远显示「?」，直到重新登录。
class _FakeAuth extends MusicAuthNotifier {
  _FakeAuth(this.cookie);
  final String cookie;
  bool cleared = false;

  @override
  MusicAuthState build() => MusicAuthState(cookies: {'netease': cookie}, loading: false);

  @override
  Future<void> clear(String p) async {
    cleared = true;
    state = state.copyWith(cookies: {...state.cookies}..remove(p));
  }
}

class _FakeApi extends NeteaseApi {
  _FakeApi({required this.loggedIn, required this.nick});
  final bool loggedIn;
  final String nick;

  @override
  Future<({bool loggedIn, String userId, String nick})> loginStatus() async =>
      (loggedIn: loggedIn, userId: '1', nick: nick);
}

class _TestAccount extends MusicAccountNotifier {
  _TestAccount(this.api);
  final NeteaseApi api;

  @override
  NeteaseApi createApi({String cookie = ''}) => api;
}

void main() {
  test('Cookie 恢复后回读成功：昵称补齐（不再是「?」）', () async {
    final c = ProviderContainer(
      overrides: [
        musicAuthProvider.overrideWith(() => _FakeAuth('MUSIC_U=ok')),
        musicAccountProvider.overrideWith(() => _TestAccount(_FakeApi(loggedIn: true, nick: '狼与羊皮纸'))),
      ],
    );
    addTearDown(c.dispose);

    // 触发 build（Keychain 已恢复出 cookie）→ 内部自动回读。
    final initial = c.read(musicAccountProvider);
    expect(initial.logged, isTrue);
    expect(initial.nick, isNull, reason: '恢复瞬间昵称还没回来');

    await Future<void>.delayed(const Duration(milliseconds: 30));
    final s = c.read(musicAccountProvider);
    // 破坏点：恢复后不回读 → 永远「?」。
    expect(s.nick, '狼与羊皮纸');
    expect(s.avatarInitial, '狼');
  });

  test('回读发现 Cookie 失效：撤下登录态并清凭据', () async {
    final auth = _FakeAuth('MUSIC_U=expired');
    final c = ProviderContainer(
      overrides: [
        musicAuthProvider.overrideWith(() => auth),
        musicAccountProvider.overrideWith(() => _TestAccount(_FakeApi(loggedIn: false, nick: ''))),
      ],
    );
    addTearDown(c.dispose);

    expect(c.read(musicAccountProvider).logged, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final s = c.read(musicAccountProvider);
    // 破坏点：不撤登录态 → 「顶着 ? 的已登录」，用户以为账号异常。
    expect(s.logged, isFalse);
    expect(auth.cleared, isTrue);
  });

  test('回读网络失败：保持已登录 + 「?」（不误撤）', () async {
    final c = ProviderContainer(
      overrides: [
        musicAuthProvider.overrideWith(() => _FakeAuth('MUSIC_U=ok')),
        musicAccountProvider.overrideWith(() => _TestAccount(_FakeNetError())),
      ],
    );
    addTearDown(c.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    final s = c.read(musicAccountProvider);
    expect(s.logged, isTrue);
    expect(s.avatarInitial, '?');
  });

  test('avatarInitial 渲染防护：空昵称兜底「?」', () {
    final s = MusicAccountState(cur: 'netease', logged: true, nick: '', extra: const {});
    expect(s.avatarInitial, '?');
    expect(s.displayName, '');
  });
}

class _FakeNetError extends NeteaseApi {
  @override
  Future<({bool loggedIn, String userId, String nick})> loginStatus() async => throw StateError('network down');
}
