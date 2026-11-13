import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/controller/music_auth.dart';
import 'package:miao_dock_flutter/features/music/controller/music_login_controller.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';
import 'package:miao_dock_flutter/features/music/data/webview/webview_cookie.dart';
import 'package:miao_dock_flutter/features/music/data/webview/webview_login_config.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';

/// WebView 登录：配置、Cookie 汇总与登录收口。
///
/// 破坏点：
/// · 不按域名过滤 → 把其它站点的 cookie 串进来，服务端不认；
/// · 判定票据用错名字（如网易云用 token）→ 永远判不出已登录；
/// · 票据缺失也落盘 → 假登录，重启掉线。
class _FakeAuth extends MusicAuthNotifier {
  @override
  MusicAuthState build() => const MusicAuthState(cookies: {}, loading: false);

  @override
  Future<void> save(MusicPlatform p, String cookie) async {
    state = state.copyWith(cookies: {...state.cookies, p: cookie});
  }
}

void main() {
  ProviderContainer make() {
    final c = ProviderContainer(overrides: [musicAuthProvider.overrideWith(_FakeAuth.new)]);
    addTearDown(c.dispose);
    return c;
  }

  test('四平台都有 WebView 登录配置（含登录页与域名）', () {
    for (final p in [MusicPlatform.netease, MusicPlatform.kugou, MusicPlatform.qq, MusicPlatform.migu]) {
      final cfg = webviewLoginConfigs[p];
      expect(cfg, isNotNull, reason: '$p 缺登录配置');
      expect(cfg!.url, startsWith('https://'));
      expect(cfg.cookieDomains, isNotEmpty);
      expect(cfg.loginCookieNames, isNotEmpty);
    }
  });

  test('Cookie 按域名过滤：只收本平台域，且跳过空值', () {
    final cfg = webviewLoginConfigs[MusicPlatform.netease]!;
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
    final ne = WebviewCookieCollector(webviewLoginConfigs[MusicPlatform.netease]!);
    // 破坏点：网易云用 token 判 → 这里会误判为已登录。
    expect(ne.hasLogin(const [RawWebviewCookie(name: 'token', value: 't', domain: 'music.163.com')]), isFalse);
    expect(ne.hasLogin(const [RawWebviewCookie(name: 'MUSIC_U', value: 'u', domain: 'music.163.com')]), isTrue);

    final kg = WebviewCookieCollector(webviewLoginConfigs[MusicPlatform.kugou]!);
    expect(kg.hasLogin(const [RawWebviewCookie(name: 'token', value: 't', domain: 'kugou.com')]), isTrue);
  });

  test('拿到票据即登录成功并落盘', () async {
    final c = make();
    final nm = c.read(musicLoginProvider.notifier);
    nm.begin(MusicPlatform.netease);
    expect(c.read(musicLoginProvider).phase, MusicLoginPhase.awaiting);

    final ok = await nm.submitCookies(const [
      RawWebviewCookie(name: 'MUSIC_U', value: 'real', domain: 'music.163.com'),
    ]);

    expect(ok, isTrue);
    expect(c.read(musicLoginProvider).phase, MusicLoginPhase.succeeded);
    // 破坏点：不落盘 → 重启掉线。
    expect(c.read(musicAuthProvider).cookieOf(MusicPlatform.netease), contains('MUSIC_U=real'));
    expect(c.read(musicAccountProvider).logged, isTrue);
  });

  test('没有票据时不算登录，保持等待', () async {
    final c = make();
    final nm = c.read(musicLoginProvider.notifier);
    nm.begin(MusicPlatform.netease);

    final ok = await nm.submitCookies(const [
      RawWebviewCookie(name: 'NMTID', value: 'only-stats', domain: 'music.163.com'),
    ]);

    expect(ok, isFalse);
    expect(c.read(musicLoginProvider).phase, MusicLoginPhase.awaiting);
    expect(c.read(musicAccountProvider).logged, isFalse);
  });

  test('用户关闭窗口 → 取消（不算登录）', () {
    final c = make();
    final nm = c.read(musicLoginProvider.notifier);
    nm.begin(MusicPlatform.kugou);
    nm.cancel();
    expect(c.read(musicLoginProvider).phase, MusicLoginPhase.cancelled);
    expect(c.read(musicAccountProvider).logged, isFalse);
  });
}
