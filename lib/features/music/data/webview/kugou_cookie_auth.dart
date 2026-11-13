/// 酷狗 WebView Cookie 的登录态解析（对齐 miao-dock `extract_kugou_auth`）。
///
/// 酷狗的登录票据不只有明文 `token`/`userid`：网页版主要把它们塞在 **复合 Cookie
/// `KuGoo`** 里（URL 编码的 `k=v&k=v` 串）。只认明文键会漏判 —— 用户实测：
/// 窗口里已登录、应用却始终抓不到。
class KugouCookieAuth {
  const KugouCookieAuth({required this.userId, required this.token, required this.hasKugoo});

  /// 用户数字 id（空串 / "0" 视为未登录）。
  final String userId;

  /// 播放票据（明文 token / Token / t / T / KuGoo 里的 t、token）。
  final String token;

  /// 是否存在 KuGoo 复合 Cookie（有它本身就算「已登录」）。
  final bool hasKugoo;

  /// 有登录态（miao-dock `logged_in`）：数字 userid 或存在 KuGoo。
  bool get loggedIn => (userId.isNotEmpty && userId != '0') || hasKugoo;

  /// 播放就绪（miao-dock `playback_ready`）：userid 有效 **且** token 非空。
  bool get playbackReady => userId.isNotEmpty && userId != '0' && token.isNotEmpty;
}

/// 从「已过滤为本平台域」的 Cookie 列表解析酷狗登录态。
KugouCookieAuth extractKugouCookieAuth(List<({String name, String value})> cookies) {
  String? pick(List<String> names) {
    for (final n in names) {
      for (final c in cookies) {
        if (c.name == n && c.value.trim().isNotEmpty) return c.value.trim();
      }
    }
    return null;
  }

  // KuGoo 复合 Cookie：URL 编码的 k=v&k=v 串（网页版主票据）。
  Map<String, String> parseKugoo(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return const {};
    try {
      text = Uri.decodeComponent(text);
    } on Object {
      // 不是合法编码就按原文解析。
    }
    final out = <String, String>{};
    for (final part in text.split('&')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      out[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    return out;
  }

  final kugooRaw = pick(['KuGoo', 'kugou', 'Kugou']) ?? '';
  final kugoo = parseKugoo(kugooRaw);

  String digits(String? s) => (s ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  final userId = digits(
    pick(['userid', 'UserId', 'KugooID', 'kugouID']) ??
        kugoo['KugooID'] ??
        kugoo['kugouID'] ??
        kugoo['userid'] ??
        kugoo['uid'],
  );

  final token = pick(['token', 'Token', 't', 'T']) ?? kugoo['t'] ?? kugoo['token'] ?? '';

  return KugouCookieAuth(userId: userId, token: token, hasKugoo: kugooRaw.isNotEmpty);
}
