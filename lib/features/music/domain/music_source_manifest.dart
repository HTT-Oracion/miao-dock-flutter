/// 音乐源运行时清单 —— **字段从 JS 源自身推导**（与漫画源同口径）。
///
/// JS 类字段是唯一事实源：源作者只写一份 JS，name / key / version / baseUrl /
/// platform 都声明在类里；导入时静态扫描得出其余（entryClass / hosts）。
/// 域名白名单从 JS 里实际出现的 URL 推导 —— 源声称什么不算数，实际请求什么才算数。
///
/// `music_source.json` 可选，只承载 JS 无法表达的两个覆盖项：timeoutMs / headers。
class MusicSourceManifest {
  const MusicSourceManifest({
    required this.specVersion,
    required this.id,
    required this.platform,
    required this.name,
    required this.version,
    required this.baseUrl,
    required this.entryClass,
    required this.sourceFile,
    required this.hosts,
    this.logoUrl,
    this.colorHex,
    this.streamReferer,
    this.login,
    this.timeoutMs = 15000,
    this.headers = const {},
    this.rateLimitIntervalMs = 300,
  });

  final int specVersion;
  final String id;
  final String platform;
  final String name;
  final String version;
  final String baseUrl;
  final String entryClass;
  final String sourceFile;
  final List<String> hosts;

  /// 源声明的平台 logo（JS `logo = 'https://…'`）；null = 用内置品牌或派生兜底。
  final String? logoUrl;

  /// 源声明的平台主色（JS `color = '#RRGGBB'`）。
  final String? colorHex;

  /// 源声明的播放流 Referer（音频 CDN 防盗链；JS `referer = '…'`）。
  final String? streamReferer;

  /// 源声明的 WebView 登录配置（新平台必需，内置四平台有静态表兜底）。
  final MusicSourceLoginConfig? login;

  final int timeoutMs;
  final Map<String, String> headers;
  final int rateLimitIntervalMs;
}

/// 源声明的 WebView 登录配置（`loginUrl` / `loginCookieDomains` /
/// `loginCookieNames` 三个类字段）——新平台据此接入「打开官方页 → 回读 Cookie」流程。
class MusicSourceLoginConfig {
  const MusicSourceLoginConfig({
    required this.url,
    required this.cookieDomains,
    required this.cookieNames,
    this.warmupUrl,
  });

  final String url;
  final List<String> cookieDomains;
  final List<String> cookieNames;

  /// 登录后导航的补 Cookie 页（酷狗个人中心同款机制）；null = 无 warmup。
  final String? warmupUrl;
}

/// 从 JS 源文本推导清单。
///
/// [sourceFile] 是包内文件名；[catalog] 是远程目录条目（name/version/description
/// 允许仓库侧覆盖 —— 类字段缺失时兜底）。校验问题以字段名返回（UI 映射 ARB）。
(MusicSourceManifest?, List<String>) manifestFromScript(
  String js,
  String sourceFile, {
  String? catalogKey,
  String? catalogName,
  String? catalogVersion,
  String? catalogDescription,
  int? timeoutMs,
  Map<String, String> headers = const {},
}) {
  final issues = <String>[];

  String? scanString(String field) {
    // 类字段是裸标识符赋值（name = 'xxx'）。
    final m = RegExp("$field\\s*=\\s*['\"]([^'\"]+)['\"]").firstMatch(js);
    return m?.group(1);
  }

  final entryMatch = RegExp(r'class\s+([A-Za-z_$][A-Za-z0-9_$]*)\s+extends\s+MusicSourceBase').firstMatch(js);
  final entryClass = entryMatch?.group(1) ?? '';
  if (entryClass.isEmpty) issues.add('entryClass');

  final platform = scanString('platform') ?? '';
  final key = scanString('key') ?? catalogKey ?? '';
  final name = scanString('name') ?? catalogName ?? '';
  final version = scanString('version') ?? catalogVersion ?? '1.0.0';
  final baseUrl = scanString('baseUrl') ?? '';
  // 可选展示字段：logo / 主色。
  final logoUrl = scanString('logo');
  final colorHex = scanString('color');
  // 可选登录声明（新平台接入 WebView 登录用，逗号分隔列表）。
  final loginUrl = scanString('loginUrl');
  final loginDomainsRaw = scanString('loginCookieDomains');
  final loginNamesRaw = scanString('loginCookieNames');
  final loginWarmupUrl = scanString('loginWarmupUrl');
  MusicSourceLoginConfig? login;
  if (loginUrl != null && loginUrl.isNotEmpty) {
    final domains =
        loginDomainsRaw?.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ?? const <String>[];
    final names =
        loginNamesRaw?.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ?? const <String>[];
    if (domains.isNotEmpty && names.isNotEmpty) {
      login = MusicSourceLoginConfig(
        url: loginUrl,
        cookieDomains: domains,
        cookieNames: names,
        warmupUrl: loginWarmupUrl,
      );
    }
  }

  if (platform.isEmpty) issues.add('platform');
  if (key.isEmpty) issues.add('key');
  if (name.isEmpty) issues.add('name');
  if (baseUrl.isEmpty) issues.add('baseUrl');

  // hosts 从 JS 里实际出现的 URL 推导（安全边界跟实际请求走，不跟声明走）。
  final hosts = <String>{};
  for (final m in RegExp(r'https?://([A-Za-z0-9.-]+)').allMatches(js)) {
    final host = m.group(1)!.toLowerCase();
    if (host.contains('*') || host.length < 4) continue;
    hosts.add(host);
  }

  if (issues.isNotEmpty) return (null, issues);

  final manifest = MusicSourceManifest(
    specVersion: 1,
    id: key,
    platform: platform,
    name: name,
    version: version,
    baseUrl: baseUrl,
    entryClass: entryClass,
    sourceFile: sourceFile,
    hosts: hosts.toList(),
    logoUrl: logoUrl,
    colorHex: colorHex,
    streamReferer: scanString('referer'),
    login: login,
    timeoutMs: timeoutMs ?? 15000,
    headers: headers,
  );
  // platform 只要是合法的小写标识符即可（新平台任意命名）；'local' 保留给本地曲目。
  if (RegExp(r'^[a-z][a-z0-9_]{1,31}$').hasMatch(manifest.platform) == false || manifest.platform == 'local') {
    issues.add('platform');
  }
  if (manifest.hosts.isEmpty) issues.add('hosts');
  return (issues.isEmpty ? manifest : null, issues);
}
