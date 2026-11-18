import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/controller/music_auth.dart';
import 'package:miao_dock_flutter/features/music/controller/music_login_controller.dart';
import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';

import 'support/stub_engine.dart';
import 'support/stub_registry.dart';

import 'package:miao_dock_flutter/features/music/data/webview/webview_cookie.dart';
import 'package:miao_dock_flutter/features/music/data/webview/webview_login_config.dart';
import 'package:miao_dock_flutter/features/music/domain/js_music_source.dart';
import 'package:miao_dock_flutter/features/music/domain/music_login_info.dart';
import 'package:miao_dock_flutter/features/music/domain/music_source_manifest.dart';

/// WebView 登录：配置、Cookie 汇总与登录收口。
///
/// 破坏点：
/// · 不按域名过滤 → 把其它站点的 cookie 串进来，服务端不认；
/// · 判定票据用错名字（如网易云用 token）→ 永远判不出已登录；
/// · 票据缺失也落盘 → 假登录，重启掉线；
/// · 有 `loginInfo` 能力却仍按「任一票据」收口 → QQ 只有 uin 时提前落盘，
///   重启回读判失效并清凭据（用户看到「登录成功、重启掉线」）。
class _FakeAuth extends MusicAuthNotifier {
  @override
  MusicAuthState build() => const MusicAuthState(cookies: {}, loading: false);

  @override
  Future<void> save(String p, String cookie) async {
    state = state.copyWith(cookies: {...state.cookies, p: cookie});
  }
}

final repoNeteaseJs = File('../miao-dock-sources/music/netease.js').readAsStringSync();

/// 内联构造一个带登录声明的源（平台逻辑无关，便于造「半张票」场景）。
JsMusicSource declaredSource({
  required String platform,
  required List<String> cookieNames,
  required Set<String> capabilities,
  String domain = '163.com',
}) {
  final names = cookieNames.join(',');
  final js =
      "class S extends MusicSourceBase {\n"
      "  name = '测试源';\n  platform = '$platform';\n  key = '$platform';\n  version = '1.0.0';\n"
      "  baseUrl = 'https://music.163.com';\n"
      "  loginUrl = 'https://example.com/login';\n"
      "  loginCookieDomains = '$domain';\n"
      "  loginCookieNames = '$names';\n"
      "  async loginInfo(args) { return { loggedIn: true, nick: '' }; }\n"
      "}";
  final (manifest, issues) = manifestFromScript(js, '$platform.js');
  expect(issues, isEmpty, reason: '$issues');
  return JsMusicSource(manifest: manifest!, capabilities: capabilities);
}

void main() {
  ProviderContainer make({List<JsMusicSource>? sources, StubMusicSourceEngine? engine}) {
    final c = ProviderContainer(
      overrides: [
        jsMusicSourceRegistryProvider.overrideWith(() => StubRegistry(sources ?? [neteaseSourceFromRepo()])),
        musicAuthProvider.overrideWith(_FakeAuth.new),
        musicSourceEngineProvider.overrideWithValue(
          engine ?? StubMusicSourceEngine(loginResult: const MusicLoginInfo(loggedIn: true, nick: '')),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// 从外部源仓库读取四平台 JS，声明登录配置则生成配置（登录能力跟着源走）。
  Future<WebviewLoginConfig?> declaredConfig(String pkg) async {
    final js = File('../miao-dock-sources/music/$pkg.js').readAsStringSync();
    final (manifest, issues) = manifestFromScript(js, '$pkg.js');
    expect(manifest, isNotNull, reason: '$pkg 清单问题：$issues');
    return loginConfigFor(manifest!.platform, declared: manifest.login);
  }

  RawWebviewCookie cookie(String name, String value, {String domain = 'music.163.com'}) =>
      RawWebviewCookie(name: name, value: value, domain: domain);

  test('四平台源都声明了 WebView 登录配置（含登录页与域名）', () {
    for (final p in ['netease', 'kugou', 'qq', 'migu']) {
      final cfg = declaredConfig(p);
      expect(cfg, isNotNull, reason: '$p 缺登录声明');
    }
  });

  test('已装副本是旧 JS（无登录声明）：内置兜底仍可登录', () {
    // 模拟用户已安装的旧版副本（声明字段出现前的 JS）——这是用户实测踩到的场景。
    final staleJs = repoNeteaseJs
        .replaceAll(RegExp(r"\s*loginUrl = '[^']*';"), '')
        .replaceAll(RegExp(r"\s*loginCookieDomains = '[^']*';"), '')
        .replaceAll(RegExp(r"\s*loginCookieNames = '[^']*';"), '');
    expect(staleJs.contains('loginUrl'), isFalse);
    final (manifest, issues) = manifestFromScript(staleJs, 'netease.js');
    expect(manifest, isNotNull, reason: '$issues');
    expect(manifest!.login, isNull, reason: '旧副本应无登录声明');

    // 破坏点：内置兜底删除 → 旧副本永远「不支持窗口登录」，只能重新导入。
    final cfg = loginConfigFor(manifest.platform, declared: manifest.login);
    expect(cfg, isNotNull, reason: '内置兜底必须能登录');
    expect(cfg!.loginCookieNames, contains('MUSIC_U'));
    expect(cfg.url, startsWith('https://music.163.com'));
  });

  test('Cookie 按域名过滤：只收本平台域，且跳过空值', () {
    final manifestJs = File('../miao-dock-sources/music/netease.js').readAsStringSync();
    final (manifest, issues) = manifestFromScript(manifestJs, 'netease.js');
    expect(manifest, isNotNull, reason: '$issues');
    final cfg = loginConfigFor(manifest!.platform, declared: manifest.login)!;
    final out = WebviewCookieCollector(cfg).collect(const [
      RawWebviewCookie(name: 'MUSIC_U', value: 'abc', domain: '.music.163.com'),
      RawWebviewCookie(name: 'NMTID', value: 'x', domain: 'music.163.com'),
      // 破坏点：不过滤 → 这条会被串进去。
      RawWebviewCookie(name: 'evil', value: '1', domain: 'evil.com'),
      RawWebviewCookie(name: 'empty', value: '', domain: 'music.163.com'),
    ]);

    expect(out, contains('MUSIC_U=abc'));
    expect(out, contains('NMTID=x'));
    expect(out, isNot(contains('evil')));
    expect(out, isNot(contains('empty=')));
  });

  test('登录票据判定按平台各自的 cookie 名', () {
    final manifestJs = File('../miao-dock-sources/music/netease.js').readAsStringSync();
    final (neManifest, _) = manifestFromScript(manifestJs, 'netease.js');
    final ne = WebviewCookieCollector(loginConfigFor(neManifest!.platform, declared: neManifest.login)!);
    // 破坏点：网易云用 token 判 → 这里会误判为已登录。
    expect(ne.hasAnyTicket(const [RawWebviewCookie(name: 'token', value: 't', domain: 'music.163.com')]), isFalse);
    expect(ne.hasAnyTicket(const [RawWebviewCookie(name: 'MUSIC_U', value: 'u', domain: 'music.163.com')]), isTrue);
    // 全票判据：单票据平台「任一」与「全部」一致；多票据平台必须全到。
    expect(ne.hasAllTickets(const [RawWebviewCookie(name: 'MUSIC_U', value: 'u', domain: 'music.163.com')]), isTrue);

    final kugouJs = File('../miao-dock-sources/music/kugou.js').readAsStringSync();
    final (kgManifest, _) = manifestFromScript(kugouJs, 'kugou.js');
    final kg = WebviewCookieCollector(loginConfigFor(kgManifest!.platform, declared: kgManifest.login)!);
    expect(kg.hasAnyTicket(const [RawWebviewCookie(name: 'token', value: 't', domain: 'kugou.com')]), isTrue);
    expect(kg.hasAllTickets(const [RawWebviewCookie(name: 'token', value: 't', domain: 'kugou.com')]), isFalse);
    expect(
      kg.hasAllTickets(const [
        RawWebviewCookie(name: 'token', value: 't', domain: 'kugou.com'),
        RawWebviewCookie(name: 'userid', value: '7', domain: 'kugou.com'),
      ]),
      isTrue,
    );
  });

  test('源 loginInfo 校验通过才落盘，并回填昵称/头像', () async {
    final engine = StubMusicSourceEngine(
      loginResult: const MusicLoginInfo(loggedIn: true, nick: '狼与羊皮纸', avatarUrl: 'https://x/a.png'),
    );
    final c = make(engine: engine);
    final nm = c.read(musicLoginProvider.notifier);
    nm.begin('netease');
    expect(c.read(musicLoginProvider).phase, MusicLoginPhase.awaiting);

    final ok = await nm.submitCookies([cookie('MUSIC_U', 'real')]);

    expect(ok, isTrue);
    expect(c.read(musicLoginProvider).phase, MusicLoginPhase.succeeded);
    // 破坏点：不落盘 → 重启掉线。
    expect(c.read(musicAuthProvider).cookieOf('netease'), contains('MUSIC_U=real'));
    expect(c.read(musicAccountProvider).logged, isTrue);
    // 昵称 / 头像来自同一次 loginInfo，不再二次回读。
    expect(c.read(musicAccountProvider).nick, '狼与羊皮纸');
    expect(c.read(musicAccountProvider).avatarUrl, 'https://x/a.png');
    expect(engine.injectedCookie, contains('MUSIC_U=real'));
  });

  test('半张票：源判未完成 → 不落盘、保持等待；补票后才成功', () async {
    final source = declaredSource(
      platform: 'qq',
      cookieNames: ['uin', 'qm_keyst'],
      capabilities: {'loginInfo', 'searchSongs'},
    );
    final engine = StubMusicSourceEngine(loginResult: const MusicLoginInfo(loggedIn: false, nick: ''));
    final c = make(sources: [source], engine: engine);
    final nm = c.read(musicLoginProvider.notifier);
    nm.begin('qq');

    // 只有 uin：源明确回「未完成」——落盘会造成「假登录，重启清凭据」。
    final half = await nm.submitCookies([cookie('uin', '12345')]);
    expect(half, isFalse);
    expect(c.read(musicAuthProvider).cookieOf('qq'), isNull);
    expect(c.read(musicLoginProvider).phase, MusicLoginPhase.awaiting);

    // 补到 qm_keyst 后同拍校验通过。
    engine.loginResult = const MusicLoginInfo(loggedIn: true, nick: 'QQ用户');
    final done = await nm.submitCookies([cookie('uin', '12345'), cookie('qm_keyst', 'k')]);
    expect(done, isTrue);
    expect(c.read(musicAuthProvider).cookieOf('qq'), contains('qm_keyst=k'));
  });

  test('同一串 Cookie 明确未完成：节流期内不重复打接口', () async {
    final source = declaredSource(platform: 'qq', cookieNames: ['uin', 'qm_keyst'], capabilities: {'loginInfo'});
    final engine = StubMusicSourceEngine(loginResult: const MusicLoginInfo(loggedIn: false, nick: ''));
    final c = make(sources: [source], engine: engine);
    final nm = c.read(musicLoginProvider.notifier);
    nm.begin('qq');

    await nm.submitCookies([cookie('uin', '1')]);
    await nm.submitCookies([cookie('uin', '1')]);
    // 破坏点：不节流 → 每 2s 轮询都打一次源接口（风控风险）。
    expect(engine.probes, 1);
  });

  test('校验接口异常 + 票据齐全 → 仍落盘（Rust 先落盘后校验口径）', () async {
    final engine = StubMusicSourceEngine(loginThrows: true);
    final c = make(engine: engine);
    final nm = c.read(musicLoginProvider.notifier);
    nm.begin('netease');

    final ok = await nm.submitCookies([cookie('MUSIC_U', 'real')]);

    // 破坏点：探测异常直接当未登录 → 网络抖动就丢登录。
    expect(ok, isTrue);
    expect(c.read(musicAuthProvider).cookieOf('netease'), contains('MUSIC_U=real'));
    expect(c.read(musicAccountProvider).logged, isTrue);
    // 探测失败拿不到昵称：保持空串（UI 兜底「?」），不阻止登录态成立。
    expect(c.read(musicAccountProvider).nick, isEmpty);
  });

  test('校验接口异常 + 半张票 → 不落盘（宁缺不假登录）', () async {
    final source = declaredSource(platform: 'qq', cookieNames: ['uin', 'qm_keyst'], capabilities: {'loginInfo'});
    final engine = StubMusicSourceEngine(loginThrows: true);
    final c = make(sources: [source], engine: engine);
    final nm = c.read(musicLoginProvider.notifier);
    nm.begin('qq');

    final ok = await nm.submitCookies([cookie('uin', '1')]);
    expect(ok, isFalse);
    expect(c.read(musicAuthProvider).cookieOf('qq'), isNull);
  });

  test('旧源无 loginInfo 能力：票据名全到齐才收口（旧副本兼容）', () async {
    final source = declaredSource(
      platform: 'kugou',
      cookieNames: ['token', 'userid'],
      capabilities: {'searchSongs'},
      domain: 'kugou.com',
    );
    final engine = StubMusicSourceEngine(loginResult: const MusicLoginInfo(loggedIn: false, nick: ''));
    final c = make(sources: [source], engine: engine);
    final nm = c.read(musicLoginProvider.notifier);
    nm.begin('kugou');

    // 只有半张票：旧源也必须等全齐（任一就落盘 → 重启判失效清凭据）。
    final half = await nm.submitCookies([cookie('token', 't', domain: 'kugou.com')]);
    expect(half, isFalse);
    expect(c.read(musicAuthProvider).cookieOf('kugou'), isNull);

    final done = await nm.submitCookies([
      cookie('token', 't', domain: 'kugou.com'),
      cookie('userid', '7', domain: 'kugou.com'),
    ]);
    expect(done, isTrue);
    expect(c.read(musicAuthProvider).cookieOf('kugou'), contains('token=t'));
    // 旧源没有校验能力，不应调用 loginInfo。
    expect(engine.probes, 0);
  });

  test('没有票据时不算登录，保持等待', () async {
    final engine = StubMusicSourceEngine(loginResult: const MusicLoginInfo(loggedIn: false, nick: ''));
    final c = make(engine: engine);
    final nm = c.read(musicLoginProvider.notifier);
    nm.begin('netease');

    final ok = await nm.submitCookies([cookie('NMTID', 'only-stats')]);

    // 破坏点：只要 Cookie 非空就落盘 → 统计串被当成登录态。
    expect(ok, isFalse);
    expect(c.read(musicLoginProvider).phase, MusicLoginPhase.awaiting);
    expect(c.read(musicAccountProvider).logged, isFalse);
  });

  test('用户关闭窗口 → 取消（不算登录）', () {
    final c = make();
    final nm = c.read(musicLoginProvider.notifier);
    nm.begin('netease');
    nm.cancel();
    expect(c.read(musicLoginProvider).phase, MusicLoginPhase.cancelled);
    expect(c.read(musicAccountProvider).logged, isFalse);
  });
}
