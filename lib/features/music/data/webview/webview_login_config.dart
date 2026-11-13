import '../../domain/music_source_manifest.dart';

/// WebView 登录的平台配置（对齐 miao-dock `music::open_*_login_window`）。
///
/// 为什么走 WebView 而不是自己生成二维码：
/// 平台官方页面在**真实浏览器内核**里完成登录，服务端看到的是正常浏览器环境；
/// 自己拼二维码要伪造 deviceId / appver / 指纹头，反而会触发风控（网易云实测回 8821）。
/// 参考 miao-dock：开窗 → 轮询 Cookie → 抓到登录票据即关窗落盘。
///
/// 平台身份是字符串 id：内置四平台的配置在 [webviewLoginConfigs] 静态表；
/// **新平台由源声明**（`loginUrl` / `loginCookieDomains` / `loginCookieNames`
/// 类字段，导入期解析进 manifest.login），经 [loginConfigFor] 合并查询。
class WebviewLoginConfig {
  const WebviewLoginConfig({
    required this.platformId,
    required this.url,
    required this.title,
    required this.cookieDomains,
    required this.loginCookieNames,
    this.warmupUrl,
  });

  /// 平台 id（字符串身份）。
  final String platformId;

  /// 打开的官方登录页。
  final String url;

  /// 登录窗口标题。
  final String title;

  /// 需要收集 Cookie 的域名（后缀匹配）。
  final List<String> cookieDomains;

  /// 判定「登录成功」的 Cookie 名（任意一个存在即可）。
  ///
  /// · 网易云：`MUSIC_U` 是登录票据；
  /// · 酷狗：`token` + `userid`（`token` 存在即视为已登录）；
  /// · 新平台：源声明（manifest.login.cookieNames）。
  final List<String> loginCookieNames;

  /// 登录后需要再访问一次的「补全 Cookie」页。
  ///
  /// 酷狗首次登录只有 `loggedIn` 没有播放权限票据，需要访问个人中心页触发补齐
  /// （miao-dock 的 warmup 机制）。
  final String? warmupUrl;

  /// Cookie 是否属于本平台域名。
  bool ownsDomain(String domain) {
    final d = domain.trim().replaceFirst(RegExp(r'^\.'), '').toLowerCase();
    return cookieDomains.any((suffix) => d == suffix || d.endsWith('.$suffix'));
  }
}

/// 平台登录配置查询：**只走源声明**（JS `loginUrl` 等类字段，导入期解析进
/// manifest.login）。静态表已随内置播放实现一起移除 —— 登录能力跟着源走。
WebviewLoginConfig? loginConfigFor(String platformId, {MusicSourceLoginConfig? declared}) {
  if (declared == null) return null;
  return WebviewLoginConfig(
    platformId: platformId,
    url: declared.url,
    title: '$platformId 登录',
    cookieDomains: declared.cookieDomains,
    loginCookieNames: declared.cookieNames,
    warmupUrl: declared.warmupUrl,
  );
}
