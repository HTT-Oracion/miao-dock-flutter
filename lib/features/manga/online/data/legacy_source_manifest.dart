import '../domain/source_manifest.dart';

/// 把上游单文件 `ComicSource` 归一成本项目的 [SourceManifest]。
///
/// 脚本仍是唯一事实源：类名 / key / version / baseUrl 从脚本读取；仓库索引只
/// 补显示名、版本和描述。hosts 从脚本里出现的绝对 URL 提取，保证 HTTP 白名单
/// 能覆盖站点与图床。
SourceManifest legacyManifestFromScript(
  String js, {
  required Uri scriptUri,
  String? catalogKey,
  String? catalogName,
  String? catalogVersion,
  String? catalogDescription,
}) {
  final className = _match(js, RegExp(r'class\s+([A-Za-z_$][A-Za-z0-9_$]*)\s+extends\s+ComicSource\b'));
  if (className == null) {
    throw const FormatException('not a ComicSource script');
  }
  final scriptKey = _match(js, RegExp(r'''(?:^|\n)\s*key\s*=\s*["']([^"']+)["']'''));
  final scriptName = _match(js, RegExp(r'''(?:^|\n)\s*name\s*=\s*["']([^"']+)["']'''));
  final scriptVersion = _match(js, RegExp(r'''(?:^|\n)\s*version\s*=\s*["']([^"']+)["']'''));
  final baseUrl = _match(js, RegExp(r'''(?:^|\n)\s*baseUrl\s*=\s*["']([^"']+)["']'''));
  final rawHosts = <String>{
    for (final match in RegExp(r'https?://([A-Za-z0-9.-]+\.[A-Za-z]{2,})').allMatches(js))
      match.group(1)!.toLowerCase(),
  };
  final baseHost = Uri.tryParse(baseUrl ?? '')?.host.toLowerCase();
  if (baseHost != null && baseHost.isNotEmpty) rawHosts.add(baseHost);
  rawHosts.removeWhere((host) => host.isEmpty);

  var base = baseUrl?.trim() ?? '';
  if (base.isEmpty && rawHosts.isNotEmpty) base = 'https://${rawHosts.first}';
  if (base.isEmpty) base = 'https://${scriptUri.host}';
  final version = _validVersion(catalogVersion) ?? _validVersion(scriptVersion) ?? '1.0.0';
  final id = (scriptKey ?? catalogKey ?? className).trim();
  if (!SourceManifest.idPattern.hasMatch(id)) {
    throw const FormatException('invalid source key');
  }
  final hosts = rawHosts.toList()..sort();
  if (hosts.isEmpty) {
    final host = Uri.tryParse(base)?.host;
    if (host != null && host.isNotEmpty) hosts.add(host);
  }
  return SourceManifest(
    specVersion: SourceManifest.supportedSpecVersion,
    id: id,
    name: (catalogName ?? scriptName ?? id).trim(),
    version: version,
    lang: 'zh',
    baseUrl: base,
    entryClass: className,
    sourceFile: 'source.js',
    hosts: hosts,
    description: catalogDescription ?? '',
    timeoutMs: 20000,
    rateLimitIntervalMs: 300,
    rateLimitConcurrency: 2,
    runtime: SourceRuntime.comicSource,
  );
}

String? _match(String text, RegExp pattern) => pattern.firstMatch(text)?.group(1)?.trim();

String? _validVersion(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  if (RegExp(r'^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$').hasMatch(value)) return value;
  final parts = value.split('.');
  if (parts.every((part) => int.tryParse(part) != null)) {
    while (parts.length < 3) {
      parts.add('0');
    }
    return parts.take(3).join('.');
  }
  return '1.0.0';
}
