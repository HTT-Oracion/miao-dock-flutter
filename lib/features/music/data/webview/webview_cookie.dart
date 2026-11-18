import '../../domain/music_source_manifest.dart';
import 'webview_login_config.dart';

/// WebView 里读到的一条 Cookie（与具体插件解耦）。
class RawWebviewCookie {
  const RawWebviewCookie({required this.name, required this.value, required this.domain});

  final String name;
  final String value;
  final String domain;
}

/// 把 WebView 抓到的 Cookie 汇总成可用的一串。
///
/// 规则对齐 miao-dock `build_cookie_from_webview`：
/// · 只取属于本平台域名的 Cookie（避免把其它站点的串进来）；
/// · 按优先级排序（登录票据在前，便于服务端识别）；
/// · 同名 Cookie 保留**首个**（先出现的通常是主域，子域重复项不覆盖它）；
/// · 跳过空值（空 cookie 只会有害）。
class WebviewCookieCollector {
  const WebviewCookieCollector(this.config);

  final WebviewLoginConfig config;

  /// Cookie 名优先级（影响拼接顺序，不影响判定）。
  ///
  /// 四平台名单与 miao-dock `mod.rs` 的 `*_COOKIE_PRIORITY` 逐项对齐：先出现的是
  /// 登录票据（服务端按顺序认），缺项会让落盘串的形状与 Rust 版不一致。
  static const _priority = [
    // 网易云（NETEASE_COOKIE_PRIORITY）
    'MUSIC_U', '__csrf', 'NMTID', 'MUSIC_A', '__remember_me', '_ntes_nuid', '_ntes_nnid', 'WEVNSM', 'WNMCID',
    'JSESSIONID-WYYY',
    // 酷狗（KUGOU_COOKIE_PRIORITY）：KuGoo 是复合票据，最优先。
    'KuGoo', 'token', 'userid', 'KugooID', 'kugouID', 'UserId', 'kg_mid', 'kg_dfid', 'Kugou', 'NickName',
    // QQ（QQ_COOKIE_PRIORITY）
    'uin', 'qqmusic_uin', 'wxuin', 'login_type', 'qm_keyst', 'qqmusic_key', 'p_skey', 'skey', 'psrf_qqopenid',
    'psrf_qqunionid', 'psrf_qqaccess_token', 'psrf_qqrefresh_token', 'wxopenid', 'wxunionid', 'wxrefresh_token',
    'wxskey', 'p_uin', 'ptcz', 'RK',
    // 咪咕（MIGU_COOKIE_PRIORITY）
    'MUSIC_SESSION', 'migu_cookie_id', 'ESAFEID', 'mtfk', 'P_CID', 'migu_music_tail', 'migu_userid', 'userid', 'uid',
    'SSON',
    // 通用
    'mid', 'dfid',
  ];

  /// 收集并拼成 `k=v; k=v` 形式；无有效 Cookie 时返回空串。
  String collect(Iterable<RawWebviewCookie> cookies) {
    final picked = <String, String>{};
    for (final c in cookies) {
      if (!config.ownsDomain(c.domain)) continue;
      if (c.name.isEmpty || c.value.isEmpty) continue;
      // 同名保留首个：先到的通常是主域，避免子域的短值覆盖。
      picked.putIfAbsent(c.name, () => c.value);
    }
    if (picked.isEmpty) return '';
    final names = picked.keys.toList()
      ..sort((a, b) {
        final ia = _priority.indexOf(a);
        final ib = _priority.indexOf(b);
        // 优先级表内的按表序；表外的排后面并按字母稳定排序。
        if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
        if (ia >= 0) return -1;
        if (ib >= 0) return 1;
        return a.compareTo(b);
      });
    return names.map((n) => '$n=${picked[n]}').join('; ');
  }

  /// 本平台域名下的 Cookie 名值表（同名保留首个，跳过空值）。
  Map<String, String> jarOf(Iterable<RawWebviewCookie> cookies) {
    final jar = <String, String>{};
    for (final c in cookies) {
      if (!config.ownsDomain(c.domain)) continue;
      if (c.name.isEmpty || c.value.isEmpty) continue;
      jar.putIfAbsent(c.name, () => c.value);
    }
    return jar;
  }

  /// 登录票据名是否**全部**到齐。
  ///
  /// 🔴 这才是「可以落盘」的判据：半张票（如 QQ 只有 uin、缺 qm_keyst）落盘后，
  /// 重启回读会被判失效并清凭据 —— 与 miao-dock 的 playbackReady 口径对齐。
  bool hasAllTickets(Iterable<RawWebviewCookie> cookies) {
    final jar = jarOf(cookies);
    return config.loginCookieNames.every((n) => (jar[n] ?? '').isNotEmpty);
  }

  /// 登录票据名是否**任一**到齐（只用于 launcher 触发 warmup 补票）。
  bool hasAnyTicket(Iterable<RawWebviewCookie> cookies) {
    final jar = jarOf(cookies);
    return config.loginCookieNames.any((n) => (jar[n] ?? '').isNotEmpty);
  }
}

/// 该平台是否支持 WebView 登录。
bool supportsWebviewLogin(String platformId, {MusicSourceLoginConfig? declared}) =>
    loginConfigFor(platformId, declared: declared) != null;
