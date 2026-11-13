import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/controller/music_auth.dart';
import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';
import 'package:miao_dock_flutter/features/music/domain/js_music_source.dart';
import 'package:miao_dock_flutter/features/music/domain/music_login_info.dart';
import 'package:miao_dock_flutter/features/music/domain/music_source_engine.dart';
import 'package:miao_dock_flutter/features/music/domain/music_source_manifest.dart';

/// Cookie 从 Keychain 恢复后，昵称必须经由 JS 源的 `loginInfo` 能力回读补齐。
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

/// 可编程引擎替身：loginInfo 按脚本返回。
class _StubEngine implements MusicSourceEngine {
  _StubEngine({this.loggedIn, this.nick = '', this.throwOnLogin = false});

  final bool? loggedIn;
  final String nick;
  final bool throwOnLogin;

  String? injectedCookie;

  @override
  Future<void> ensureLoaded(JsMusicSource source) async {}

  @override
  Future<void> setSessionCookie(JsMusicSource source, String cookie) async => injectedCookie = cookie;

  @override
  Future<MusicLoginInfo?> loginInfo(JsMusicSource source) async {
    if (throwOnLogin) throw StateError('network down');
    if (loggedIn == null) return null;
    return MusicLoginInfo(loggedIn: loggedIn!, nick: nick);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _TestAccount extends MusicAccountNotifier {
  _TestAccount(this.engine);
  final MusicSourceEngine engine;

  @override
  MusicSourceEngine createEngine() => engine;
}

JsMusicSource _neteaseSource() {
  final (manifest, issues) = manifestFromScript(
    "class S extends MusicSourceBase {\n  name = '网易云';\n  platform = 'netease';\n"
        "  key = 'netease';\n  version = '1.0.0';\n  baseUrl = 'https://music.163.com';\n"
        "  async loginInfo(args) { return { loggedIn: true, nick: '' }; }\n}",
    'netease.js',
  );
  assert(issues.isEmpty, '$issues');
  return JsMusicSource(manifest: manifest!, capabilities: {'loginInfo'});
}

void main() {
  test('Cookie 恢复后回读成功：昵称补齐（不再是「?」）', () async {
    final engine = _StubEngine(loggedIn: true, nick: '狼与羊皮纸');
    final c = ProviderContainer(
      overrides: [
        musicAuthProvider.overrideWith(() => _FakeAuth('MUSIC_U=ok')),
        musicSourceEngineProvider.overrideWithValue(engine),
        jsMusicSourceRegistryProvider.overrideWith(() => _RegistryStub([_neteaseSource()])),
        musicAccountProvider.overrideWith(() => _TestAccount(engine)),
      ],
    );
    addTearDown(c.dispose);

    final initial = c.read(musicAccountProvider);
    expect(initial.logged, isTrue);
    expect(initial.nick, isNull, reason: '恢复瞬间昵称还没回来');

    await Future<void>.delayed(const Duration(milliseconds: 30));
    final s = c.read(musicAccountProvider);
    // 破坏点：恢复后不回读 → 永远「?」。
    expect(s.nick, '狼与羊皮纸');
    expect(s.avatarInitial, '狼');
    // Cookie 注入引擎（源请求才能带登录态）。
    expect(engine.injectedCookie, 'MUSIC_U=ok');
  });

  test('回读发现 Cookie 失效：撤下登录态并清凭据', () async {
    final auth = _FakeAuth('MUSIC_U=expired');
    final engine = _StubEngine(loggedIn: false, nick: '');
    final c = ProviderContainer(
      overrides: [
        musicAuthProvider.overrideWith(() => auth),
        musicSourceEngineProvider.overrideWithValue(engine),
        jsMusicSourceRegistryProvider.overrideWith(() => _RegistryStub([_neteaseSource()])),
        musicAccountProvider.overrideWith(() => _TestAccount(engine)),
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
    final engine = _StubEngine(throwOnLogin: true);
    final c = ProviderContainer(
      overrides: [
        musicAuthProvider.overrideWith(() => _FakeAuth('MUSIC_U=ok')),
        musicSourceEngineProvider.overrideWithValue(engine),
        jsMusicSourceRegistryProvider.overrideWith(() => _RegistryStub([_neteaseSource()])),
        musicAccountProvider.overrideWith(() => _TestAccount(engine)),
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

  test('平台描述符：源声明 logo / color 生效（徽章三层兜底的第一层）', () {
    final (manifest, issues) = manifestFromScript(
      "class S extends MusicSourceBase {\n  name = '哔哩哔哩';\n  platform = 'bilibili';\n"
          "  key = 'bilibili';\n  version = '1.0.0';\n  baseUrl = 'https://www.bilibili.com';\n"
          "  logo = 'https://www.bilibili.com/favicon.ico';\n  color = '#FB7299';\n}",
      'bilibili.js',
    );
    expect(issues, isEmpty, reason: '$issues');
    final source = JsMusicSource(manifest: manifest!, capabilities: const {});
    expect(source.info.logoUrl, 'https://www.bilibili.com/favicon.ico');
    expect(source.info.color, isNotNull);
    // 未声明 logo / color 的新平台 → 留空给注册表派生兜底。
    final (plain, _) = manifestFromScript(
      "class S extends MusicSourceBase {\n  name = '某平台';\n  platform = 'someplat';\n"
          "  key = 'someplat';\n  version = '1.0.0';\n  baseUrl = 'https://x.example.com';\n}",
      'someplat.js',
    );
    final plainInfo = JsMusicSource(manifest: plain!, capabilities: const {}).info;
    expect(plainInfo.logoUrl, isNull);
    expect(plainInfo.color, isNull);
  });
}

/// 注册表替身：固定源清单（不走磁盘）。
class _RegistryStub extends JsMusicSourceRegistry {
  _RegistryStub(this.sources);

  final List<JsMusicSource> sources;

  @override
  List<JsMusicSource> build() => sources;
}
