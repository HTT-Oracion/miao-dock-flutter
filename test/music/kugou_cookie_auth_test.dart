import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/data/webview/kugou_cookie_auth.dart';

/// 酷狗 WebView Cookie 的登录态解析。
///
/// 破坏点（用户实测）：只认明文 `token`/`userid` 键 —— 网页版酷狗登录后
/// 票据主要在复合 Cookie `KuGoo`（URL 编码的 k=v&k=v）里，通用判定漏判，
/// 窗口里已登录、应用却一直显示未完成。
void main() {
  List<({String name, String value})> cookiesOf(Map<String, String> m) => [
    for (final e in m.entries) (name: e.key, value: e.value),
  ];

  test('明文 token + userid：登录且播放就绪', () {
    final a = extractKugouCookieAuth(cookiesOf({'userid': '12345', 'token': 'abc'}));
    expect(a.loggedIn, isTrue);
    expect(a.playbackReady, isTrue);
  });

  test('复合 KuGoo：URL 编码里带 KugooID 与 t → 判定登录', () {
    // 破坏点：不解析 KuGoo → loggedIn=false，永远等不到登录完成。
    final kugoo = Uri.encodeComponent('KugooID=888999&t=fa1c...& userid=888999');
    final a = extractKugouCookieAuth(cookiesOf({'KuGoo': kugoo}));
    expect(a.hasKugoo, isTrue);
    expect(a.userId, '888999');
    expect(a.loggedIn, isTrue);
    expect(a.playbackReady, isTrue, reason: 'KuGoo 里的 t 可当播放票据');
  });

  test('仅有 KuGoo（无可解析字段）：仍算已登录', () {
    final a = extractKugouCookieAuth(cookiesOf({'KuGoo': 'some-opaque-value'}));
    // 破坏点：要求 userId 才算登录 → 漏判。
    expect(a.loggedIn, isTrue);
  });

  test('userid=0：不算登录（游客）', () {
    final a = extractKugouCookieAuth(cookiesOf({'userid': '0', 'token': 'x'}));
    expect(a.loggedIn, isFalse);
    expect(a.playbackReady, isFalse);
  });

  test('userid 带非数字噪声：只留数字', () {
    final a = extractKugouCookieAuth(cookiesOf({'userid': '888999abc'}));
    expect(a.userId, '888999');
  });

  test('空 Cookie：未登录', () {
    final a = extractKugouCookieAuth(cookiesOf({'NMTID': 'x'}));
    expect(a.loggedIn, isFalse);
    expect(a.playbackReady, isFalse);
  });
}
