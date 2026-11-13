import 'dart:convert';

import 'package:dio/dio.dart';

/// 远程链接异常（code 由 UI 映射 ARB，detail 只进日志）。
class MusicSourceRemoteException implements Exception {
  const MusicSourceRemoteException(this.code, [this.detail = '']);

  final String code;
  final String detail;

  @override
  String toString() => detail.isEmpty ? code : '$code: $detail';
}

/// 远程目录条目 —— 与漫画源 index.json 同字段（key / name / version /
/// description / fileName），其余（platform / hosts / entryClass）从 JS 推导。
class MusicSourceCatalogEntry {
  const MusicSourceCatalogEntry({
    required this.key,
    required this.name,
    required this.version,
    required this.description,
    required this.fileUrl,
  });

  final String key;
  final String name;
  final String version;
  final String description;
  final String fileUrl;
}

class MusicSourceCatalog {
  const MusicSourceCatalog({required this.name, required this.entries});

  final String name;
  final List<MusicSourceCatalogEntry> entries;
}

/// GitHub blob 页面链接换 raw 地址；其它链接原样返回。
String normalizeMusicSourceLink(String raw) {
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

/// 目录解析：`{name, sources: [...]}` / 裸数组都收（与漫画源同宽容度）。
/// 条目字段：key（或 id）、name、version、description、fileName（相对目录解析）。
MusicSourceCatalog parseMusicSourceCatalog(String raw, String catalogUrl) {
  final decoded = jsonDecode(raw);
  String name;
  List<dynamic> entries;
  if (decoded is List) {
    name = defaultMusicLibraryName(catalogUrl);
    entries = decoded;
  } else if (decoded is Map) {
    name = '${decoded['name'] ?? defaultMusicLibraryName(catalogUrl)}';
    final list = decoded['sources'] ?? decoded['entries'];
    if (list is! List) throw const FormatException('catalog');
    entries = list;
  } else {
    throw const FormatException('catalog');
  }
  final parsed = <MusicSourceCatalogEntry>[];
  final seen = <String>{};
  for (final item in entries) {
    if (item is! Map) continue;
    final key = '${item['key'] ?? item['id'] ?? ''}'.trim();
    final displayName = '${item['name'] ?? key}'.trim();
    final fileName = '${item['fileName'] ?? item['url'] ?? ''}'.trim();
    if (key.isEmpty || fileName.isEmpty) continue;
    final resolved = Uri.parse(catalogUrl).resolve(fileName);
    // http(s) = 远程目录；file = 本地导入（index.json 与 JS 同目录时的相对解析）。
    if (resolved.scheme != 'https' && resolved.scheme != 'http' && resolved.scheme != 'file') continue;
    if (!seen.add(key)) continue;
    parsed.add(
      MusicSourceCatalogEntry(
        key: key,
        name: displayName,
        version: '${item['version'] ?? '1.0.0'}',
        description: '${item['description'] ?? ''}',
        fileUrl: resolved.toString(),
      ),
    );
  }
  if (parsed.isEmpty) throw const FormatException('catalog');
  return MusicSourceCatalog(name: name, entries: parsed);
}

String defaultMusicLibraryName(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return url.trim();
  final parts = uri.pathSegments.where((p) => p.isNotEmpty && !p.endsWith('.json')).toList();
  return parts.isEmpty ? uri.host : '${uri.host}/${parts.first}';
}

/// 远程音乐源加载：目录（index.json）/ 裸 JS 两种形态。
class MusicSourceRemoteLoader {
  MusicSourceRemoteLoader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<String> fetchText(String url, {int maxBytes = 2 * 1024 * 1024}) async {
    final uri = Uri.tryParse(normalizeMusicSourceLink(url));
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const MusicSourceRemoteException('invalidUrl', 'url');
    }
    try {
      final resp = await _dio.get<List<int>>(
        uri.toString(),
        options: Options(responseType: ResponseType.bytes, validateStatus: (_) => true),
      );
      final status = resp.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw MusicSourceRemoteException('network', 'HTTP $status');
      }
      final bytes = resp.data ?? const <int>[];
      if (bytes.length > maxBytes) {
        throw const MusicSourceRemoteException('tooLarge', 'response');
      }
      return utf8.decode(bytes, allowMalformed: true);
    } on MusicSourceRemoteException {
      rethrow;
    } catch (e) {
      throw MusicSourceRemoteException('network', '$e');
    }
  }

  /// 判断链接形态：裸 JS（class 开头）或目录（JSON）。
  ///
  /// 返回「要导入的 JS 文本 + 目录元信息（目录导入时）」。
  Future<MusicSourceRemotePayload> inspect(String rawUrl) async {
    final url = normalizeMusicSourceLink(rawUrl);
    final text = await fetchText(url);
    final head = text.trimLeft();
    if (head.startsWith('class ') || head.startsWith('/**') || head.startsWith('//')) {
      return MusicSourceScriptPayload(url, text);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const MusicSourceRemoteException('invalidJson', 'link');
    }
    if (decoded is List || decoded is Map) {
      final catalog = parseMusicSourceCatalog(text, url);
      return MusicSourceCatalogPayload(url, catalog);
    }
    throw const MusicSourceRemoteException('unsupported', 'not a source/catalog');
  }
}

/// inspect 的结果（裸 JS / 目录）。
sealed class MusicSourceRemotePayload {
  const MusicSourceRemotePayload(this.url);

  final String url;
}

class MusicSourceScriptPayload extends MusicSourceRemotePayload {
  const MusicSourceScriptPayload(super.url, this.js);

  final String js;
}

class MusicSourceCatalogPayload extends MusicSourceRemotePayload {
  const MusicSourceCatalogPayload(super.url, this.catalog);

  final MusicSourceCatalog catalog;
}
