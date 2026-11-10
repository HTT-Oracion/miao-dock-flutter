import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 用户添加的源仓库（`index.json`）。应用不内置任何仓库。
class SourceLibrary {
  const SourceLibrary({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.priority = 0,
    this.lastChecked,
  });

  final String id;
  final String name;
  final String url;
  final bool enabled;
  final int priority;
  final DateTime? lastChecked;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'enabled': enabled,
    'priority': priority,
    'lastChecked': lastChecked?.toIso8601String(),
  };

  static SourceLibrary? fromJson(Map<String, Object?> json) {
    final url = '${json['url'] ?? ''}'.trim();
    if (!isValidSourceUrl(url)) return null;
    final id = '${json['id'] ?? stableSourceLibraryId(url)}';
    return SourceLibrary(
      id: id,
      name: '${json['name'] ?? defaultSourceLibraryName(url)}',
      url: url,
      enabled: json['enabled'] != false,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      lastChecked: DateTime.tryParse('${json['lastChecked']}'),
    );
  }

  SourceLibrary copyWith({String? name, String? url, bool? enabled, int? priority, DateTime? lastChecked}) =>
      SourceLibrary(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        enabled: enabled ?? this.enabled,
        priority: priority ?? this.priority,
        lastChecked: lastChecked ?? this.lastChecked,
      );
}

/// 仓库中的一个源条目。`manifestUrl` 已按仓库地址归一。
class SourceCatalogEntry {
  const SourceCatalogEntry({
    required this.key,
    required this.name,
    required this.version,
    required this.manifestUrl,
    this.description = '',
  });

  final String key;
  final String name;
  final String version;
  final String description;
  final String manifestUrl;

  Map<String, Object?> toJson() => {
    'key': key,
    'name': name,
    'version': version,
    'description': description,
    'manifestUrl': manifestUrl,
  };
}

class SourceCatalog {
  const SourceCatalog({required this.name, required this.entries});

  final String name;
  final List<SourceCatalogEntry> entries;
}

/// 链接既可能是仓库列表，也可能是单个源清单。
sealed class SourceLinkPayload {
  const SourceLinkPayload(this.rawUrl);
  final String rawUrl;
}

class SourceCatalogPayload extends SourceLinkPayload {
  const SourceCatalogPayload(super.rawUrl, this.catalog);
  final SourceCatalog catalog;
}

class SourceManifestPayload extends SourceLinkPayload {
  const SourceManifestPayload(super.rawUrl, this.rawJson);
  final Map<String, Object?> rawJson;
}

/// 直接粘贴的单个脚本（上游 `ComicSource` 格式）。
class SourceScriptPayload extends SourceLinkPayload {
  const SourceScriptPayload(super.rawUrl, this.js);
  final String js;
}

bool isValidSourceUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  return true;
}

String canonicalSourceUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty) return raw.trim().replaceAll(RegExp(r'/+$'), '');
  return uri
      .replace(
        scheme: uri.scheme.toLowerCase(),
        host: uri.host.toLowerCase(),
        path: uri.path.replaceAll(RegExp(r'/+$'), ''),
      )
      .toString();
}

String stableSourceLibraryId(String url) =>
    sha1.convert(utf8.encode(canonicalSourceUrl(url))).toString().substring(0, 12);

String defaultSourceLibraryName(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return url.trim();
  final parts = uri.pathSegments.where((part) => part.isNotEmpty && !part.toLowerCase().endsWith('.json')).toList();
  return parts.isEmpty ? uri.host : '${uri.host}/${parts.first}';
}

/// 把仓库条目解析成统一的 [SourceCatalogEntry]。
///
/// 仓库格式（推荐）：
/// `{"name": "...", "sources": [{"id":"...","name":"...","version":"1.0.0",
/// "description":"...","manifest":"sources/manhuagui/source.json"}]}`。
/// 也接受裸数组，以及 `url`/`fileName` 作为 `manifest` 的别名，方便静态托管。
SourceCatalog parseSourceCatalog(String raw, String catalogUrl) {
  final decoded = jsonDecode(raw);
  String name;
  List<dynamic> entries;
  if (decoded is List) {
    name = defaultSourceLibraryName(catalogUrl);
    entries = decoded;
  } else if (decoded is Map) {
    name = '${decoded['name'] ?? defaultSourceLibraryName(catalogUrl)}';
    final list = decoded['sources'] ?? decoded['entries'];
    if (list is! List) throw const FormatException('catalog');
    entries = list;
  } else {
    throw const FormatException('catalog');
  }
  final base = Uri.parse(catalogUrl);
  final parsed = <SourceCatalogEntry>[];
  final seen = <String>{};
  for (final item in entries) {
    if (item is! Map) continue;
    final key = '${item['id'] ?? item['key'] ?? ''}'.trim();
    final displayName = '${item['name'] ?? key}'.trim();
    final version = '${item['version'] ?? ''}'.trim();
    final manifestRaw = '${item['manifest'] ?? item['manifestUrl'] ?? item['url'] ?? ''}'.trim();
    final fileName = '${item['fileName'] ?? ''}'.trim();
    String? resolved;
    if (manifestRaw.isNotEmpty) {
      resolved = isValidSourceUrl(manifestRaw) ? manifestRaw : base.resolve(manifestRaw).toString();
    } else if (fileName.isNotEmpty) {
      resolved = base.resolve(fileName).toString();
    }
    if (key.isEmpty || displayName.isEmpty || !isValidSourceUrl(resolved ?? '')) continue;
    if (!seen.add(key)) continue;
    parsed.add(
      SourceCatalogEntry(
        key: key,
        name: displayName,
        version: version.isEmpty ? '1.0.0' : version,
        description: '${item['description'] ?? ''}',
        manifestUrl: resolved!,
      ),
    );
  }
  return SourceCatalog(name: name, entries: parsed);
}
