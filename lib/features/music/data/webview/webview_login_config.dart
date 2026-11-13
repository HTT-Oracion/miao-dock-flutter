import '../../domain/music_models.dart';

/// WebView 登录的平台配置（对齐 miao-dock `music::open_*_login_window`）。
///
/// 为什么走 WebView 而不是自己生成二维码：
/// 平台官方页面在**真实浏览器内核**里完成登录，服务端看到的是正常浏览器环境；
/// 自己拼二维码要伪造 deviceId / appver / 指纹头，反而会触发风控（网易云实测回 8821）。
/// 参考 miao-dock：开窗 → 轮询 Cookie → 抓到登录票据即关窗落盘。
class WebviewLoginConfig {
  const WebviewLoginConfig({
    required this.platform,
    required this.url,
    required this.title,
    required this.cookieDomains,
    required this.loginCookieNames,
    this.warmupUrl,
  });

  final MusicPlatform platform;

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
  /// · QQ / 咪咕：见各自实现。
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

/// 四平台登录窗口配置。
const webviewLoginConfigs = <MusicPlatform, WebviewLoginConfig>{
  MusicPlatform.netease: WebviewLoginConfig(
    platform: MusicPlatform.netease,
    url: 'https://music.163.com/#/login',
    title: '网易云音乐登录',
    cookieDomains: ['music.163.com', '163.com', 'netease.com'],
    loginCookieNames: ['MUSIC_U'],
  ),
  MusicPlatform.kugou: WebviewLoginConfig(
    platform: MusicPlatform.kugou,
    url: 'https://www.kugou.com/',
    title: '酷狗音乐登录',
    cookieDomains: ['kugou.com'],
    loginCookieNames: ['token'],
    warmupUrl: 'https://www.kugou.com/newuc/user/uc/type=edit',
  ),
  MusicPlatform.qq: WebviewLoginConfig(
    platform: MusicPlatform.qq,
    url: 'https://y.qq.com/n/ryqq/profile',
    title: 'QQ 音乐登录',
    cookieDomains: ['qq.com', 'y.qq.com'],
    loginCookieNames: ['qm_keyst'],
  ),
  MusicPlatform.migu: WebviewLoginConfig(
    platform: MusicPlatform.migu,
    url: 'https://music.migu.cn/v5/',
    title: '咪咕音乐登录',
    cookieDomains: ['migu.cn'],
    // 咪咕没有稳定登录票据，靠 userid / uid 判定。
    loginCookieNames: ['userid', 'uid'],
  ),
};
