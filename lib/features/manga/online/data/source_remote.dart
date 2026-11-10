import 'dart:convert';
import 'dart:typed_data';

import '../domain/source_library.dart';
import '../domain/source_manifest.dart';
import 'legacy_source_manifest.dart';
import 'source_http.dart';
import 'source_package.dart';

class SourceRemoteException implements Exception {
  const SourceRemoteException(this.code, [this.detail = '']);

  final String code;
  final String detail;

  @override
  String toString() => detail.isEmpty ? code : '$code: $detail';
}

/// 把 GitHub 的 blob 页面链接换成 raw 文件地址；其他链接原样返回。
String normalizeSourceLink(String raw) {
  final trimmed = raw.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.toLowerCase() != 'github.com') return trimmed;
  final parts = uri.pathSegments;
  if (parts.length >= 5 && (parts[2] == 'blob' || parts[2] == 'raw')) {
    final owner = parts[0];
    final repo = parts[1];
    final branch = parts[3];
    final path = parts.skip(4).join('/');
    return 'https://raw.githubusercontent.com/$owner/$repo/$branch/$path';
  }
  return trimmed;
}

/// 远程链接导入：先判断是仓库 `index.json` 还是单个 `source.json`，
/// 再按清单解析 `sourceFile` / `icon` 的相对地址并抓取。
class SourceRemoteLoader {
  SourceRemoteLoader({SourceHttp? http}) : _http = http ?? SourceHttp();

  final SourceHttp _http;

  Future<SourceLinkPayload> inspect(String rawUrl) async {
    final url = normalizeSourceLink(rawUrl);
    if (!isValidSourceUrl(url)) throw const SourceRemoteException('invalidUrl', 'url');
    final text = await _fetchText(url, maxBytes: 2 * 1024 * 1024);
    final head = text.trimLeft();
    if (head.startsWith('class ') || head.startsWith('/**') || head.startsWith('//')) {
      return SourceScriptPayload(url, text);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const SourceRemoteException('invalidJson', 'link');
    }
    if (decoded is List || (decoded is Map && (decoded.containsKey('sources') || decoded.containsKey('entries')))) {
      try {
        final catalog = parseSourceCatalog(text, url);
        if (catalog.entries.isEmpty) throw const SourceRemoteException('emptyCatalog');
        return SourceCatalogPayload(url, catalog);
      } on FormatException catch (e) {
        throw SourceRemoteException('invalidJson', e.message);
      }
    }
    if (decoded is Map && decoded['specVersion'] != null) {
      return SourceManifestPayload(url, Map<String, Object?>.from(decoded));
    }
    throw const SourceRemoteException('unsupported', 'not a source/catalog');
  }

  Future<SourceCatalog> loadCatalog(String libraryUrl) async {
    final normalized = normalizeSourceLink(libraryUrl);
    final text = await _fetchText(normalized, maxBytes: 1024 * 1024);
    try {
      return parseSourceCatalog(text, normalized);
    } on FormatException catch (e) {
      throw SourceRemoteException('invalidJson', e.message);
    }
  }

  Future<SourcePackageData> loadManifest(String manifestUrl, {String? libraryId}) async {
    final normalized = normalizeSourceLink(manifestUrl);
    final text = await _fetchText(normalized, maxBytes: 512 * 1024);
    return _packageFromManifestText(normalized, text, libraryId: libraryId);
  }

  Future<SourcePackageData> _packageFromManifestText(String manifestUrl, String text, {String? libraryId}) async {
    SourceManifest manifest;
    try {
      manifest = SourceManifest.fromJsonString(text);
    } on FormatException catch (e) {
      throw SourceRemoteException('invalidJson', e.message);
    }
    final errors = manifest.validate();
    if (errors.isNotEmpty) throw SourceRemoteException('field', errors.join(','));
    final base = Uri.parse(manifestUrl);
    final sourceUri = base.resolve(manifest.sourceFile);
    if (!isValidSourceUrl(sourceUri.toString())) {
      throw const SourceRemoteException('sourceMissing', 'source.js url');
    }
    final js = await _fetchText(sourceUri.toString(), maxBytes: 2 * 1024 * 1024);
    Uint8List? icon;
    if (manifest.icon != null) {
      final iconUri = base.resolve(manifest.icon!);
      if (isValidSourceUrl(iconUri.toString())) {
        try {
          icon = await _http.fetchRemoteBytes(iconUri.toString(), maxBytes: 512 * 1024);
        } catch (_) {
          icon = null;
        }
      }
    }
    return SourcePackageData(manifest: manifest, js: js, icon: icon, sourceUrl: manifestUrl, libraryId: libraryId);
  }

  Future<SourcePackageData> loadEntry(SourceCatalogEntry entry, {String? libraryId}) async {
    final normalized = normalizeSourceLink(entry.manifestUrl);
    final text = await _fetchText(normalized, maxBytes: 2 * 1024 * 1024);
    final head = text.trimLeft();
    if (head.startsWith('class ') || head.startsWith('/**') || head.startsWith('//')) {
      return packageFromScript(
        normalized,
        text,
        catalogKey: entry.key,
        catalogName: entry.name,
        catalogVersion: entry.version,
        catalogDescription: entry.description,
        libraryId: libraryId,
      );
    }
    if (head.startsWith('{')) {
      return _packageFromManifestText(normalized, text, libraryId: libraryId);
    }
    throw const SourceRemoteException('unsupported', 'entry is neither script nor manifest');
  }

  Future<SourcePackageData> loadScript(
    String url,
    String js, {
    String? catalogKey,
    String? catalogName,
    String? catalogVersion,
    String? catalogDescription,
    String? libraryId,
  }) => packageFromScript(
    url,
    js,
    catalogKey: catalogKey,
    catalogName: catalogName,
    catalogVersion: catalogVersion,
    catalogDescription: catalogDescription,
    libraryId: libraryId,
  );

  Future<SourcePackageData> packageFromScript(
    String url,
    String js, {
    String? catalogKey,
    String? catalogName,
    String? catalogVersion,
    String? catalogDescription,
    String? libraryId,
  }) async {
    final manifest = legacyManifestFromScript(
      js,
      scriptUri: Uri.parse(normalizeSourceLink(url)),
      catalogKey: catalogKey,
      catalogName: catalogName,
      catalogVersion: catalogVersion,
      catalogDescription: catalogDescription,
    );
    return SourcePackageData(manifest: manifest, js: js, sourceUrl: normalizeSourceLink(url), libraryId: libraryId);
  }

  Future<String> _fetchText(String url, {required int maxBytes}) async {
    try {
      final response = await _http.fetchRemoteText(normalizeSourceLink(url), maxBytes: maxBytes);
      if (response.status < 200 || response.status >= 300) {
        throw SourceRemoteException('http', '${response.status}');
      }
      return response.body;
    } on SourceRemoteException {
      rethrow;
    } catch (e) {
      throw SourceRemoteException('network', '$e');
    }
  }
}
