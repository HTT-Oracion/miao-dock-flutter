import '../domain/online_error.dart';
import '../domain/online_models.dart';

/// 源返回的纯 JSON → 领域模型。UI 永远不直接看到 JS 原始结构。
class SourceDto {
  const SourceDto(this.baseUrl, {this.requestHeaders = const {}});

  final String baseUrl;
  final Map<String, String> requestHeaders;

  HomeFeed homeFeed(Object? raw) {
    final map = _map(raw, 'explore');
    final sections = <FeedSection>[];
    final rawSections = map['sections'];
    if (rawSections is List) {
      for (final item in rawSections) {
        if (item is! Map) continue;
        final section = _map(item, 'section');
        final id = _str(section['id'], fallback: 'section-${sections.length}');
        final title = _str(section['title'], fallback: id);
        final items = <OnlineComic>[];
        final rawItems = section['items'];
        if (rawItems is List) {
          for (final comic in rawItems) {
            final parsed = _comic(comic);
            if (parsed != null) items.add(parsed);
          }
        }
        sections.add(
          FeedSection(
            id: id,
            title: title,
            items: items,
            layout: _str(section['layout'], fallback: 'grid'),
            moreId: _optionalStr(section['moreId']),
            pageSize: _int(section['pageSize'], 42),
            hint: _str(section['hint'], fallback: ''),
          ),
        );
      }
    }
    return HomeFeed(
      sections: sections,
      page: _int(map['page'], 1),
      hasMore: map['hasMore'] == true,
      total: _int(map['total'], 0),
    );
  }

  PagedComics paged(Object? raw, {required int page}) {
    final map = _map(raw, 'paged');
    final items = <OnlineComic>[];
    final rawItems = map['items'];
    if (rawItems is List) {
      for (final comic in rawItems) {
        final parsed = _comic(comic);
        if (parsed != null) items.add(parsed);
      }
    }
    return PagedComics(
      items: items,
      page: _int(map['page'], page),
      hasMore: map['hasMore'] == true,
      total: _int(map['total'], items.length),
    );
  }

  List<CategoryGroup> categories(Object? raw) {
    final groups = <CategoryGroup>[];
    if (raw is! List) return groups;
    for (final item in raw) {
      if (item is! Map) continue;
      final id = _str(item['id'], fallback: 'group-${groups.length}');
      final items = <CategoryItem>[];
      final rawItems = item['items'];
      if (rawItems is List) {
        for (final category in rawItems) {
          if (category is! Map) continue;
          final categoryId = _str(category['id'], fallback: '');
          final name = _str(category['name'], fallback: categoryId);
          if (categoryId.isNotEmpty && name.isNotEmpty) items.add(CategoryItem(id: categoryId, name: name));
        }
      }
      if (items.isNotEmpty) {
        groups.add(
          CategoryGroup(
            id: id,
            name: _str(item['name'], fallback: id),
            items: items,
          ),
        );
      }
    }
    return groups;
  }

  OnlineComicDetail detail(Object? raw) {
    final map = _map(raw, 'loadComicInfo');
    final chapters = <OnlineChapter>[];
    final rawChapters = map['chapters'];
    if (rawChapters is List) {
      final seen = <String>{};
      for (final item in rawChapters) {
        if (item is! Map) continue;
        final id = _str(item['id'], fallback: '');
        if (id.isEmpty || !seen.add(id)) continue;
        final title = _str(item['title'], fallback: id);
        chapters.add(OnlineChapter(id: id, title: title, group: _chapterGroup(title), no: _optionalDouble(item['no'])));
      }
    }
    final comic = _comic(map, fallbackChapterCount: chapters.length);
    if (comic == null) throw const OnlineException(OnlineErrorCode.parse, 'detail.comic');
    return OnlineComicDetail(comic: comic, chapters: chapters);
  }

  /// `loadComicPages` 返回字符串 URL 列表；配置部件由调用方另行补齐。
  List<String> pageUrls(Object? raw) {
    if (raw is! List) return const [];
    final urls = <String>[];
    for (final item in raw) {
      final value = item is String ? item : (item is Map ? _str(item['url'], fallback: '') : '');
      final resolved = resolve(value);
      if (resolved != null) urls.add(resolved);
    }
    return urls;
  }

  ImageLoadingConfig imageConfig(Object? raw) {
    if (raw is! Map) return const ImageLoadingConfig();
    final headers = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        if (entry.key is String && entry.value is String) headers['${entry.key}'] = '${entry.value}';
      }
    }
    return ImageLoadingConfig(
      url: resolve(_optionalStr(raw['url'])),
      method: _str(raw['method'], fallback: 'GET'),
      headers: headers,
    );
  }

  OnlineComic? _comic(Object? raw, {int fallbackChapterCount = 0}) {
    if (raw is! Map) return null;
    final id = _str(raw['id'], fallback: '');
    final title = _str(raw['title'], fallback: '');
    if (id.isEmpty || title.isEmpty) return null;
    final tags = <String>[];
    final rawTags = raw['tags'];
    if (rawTags is List) {
      for (final tag in rawTags) {
        if (tag is String && tag.trim().isNotEmpty) tags.add(tag.trim());
      }
    }
    final chapters = raw['chapters'];
    final chapterCount = _int(raw['chapterCount'], chapters is List ? chapters.length : fallbackChapterCount);
    return OnlineComic(
      id: id,
      title: title,
      coverUrl: resolve(_optionalStr(raw['cover'])),
      coverHeaders: requestHeaders,
      subtitle: _optionalStr(raw['subtitle']),
      author: _optionalStr(raw['author']),
      tags: tags,
      description: _str(raw['description'], fallback: ''),
      status: ComicStatus.parse(raw['status']),
      chapterCount: chapterCount,
      latestChapter: _optionalStr(raw['latestChapter']),
      badge: _optionalStr(raw['badge']),
    );
  }

  String? resolve(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();
    if (value.startsWith('//')) return 'https:$value';
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.hasScheme) return value;
    final base = Uri.tryParse(baseUrl);
    if (base == null) return value;
    return base.resolve(value).toString();
  }

  static ChapterGroup _chapterGroup(String title) {
    if (RegExp(r'番外|特别篇|extra', caseSensitive: false).hasMatch(title)) return ChapterGroup.extra;
    if (RegExp(r'卷|vol\.?', caseSensitive: false).hasMatch(title)) return ChapterGroup.volume;
    return ChapterGroup.serial;
  }

  static Map<String, Object?> _map(Object? raw, String label) {
    if (raw is Map) return Map<String, Object?>.from(raw);
    throw OnlineException(OnlineErrorCode.parse, '$label is not an object');
  }

  static String _str(Object? value, {required String fallback}) {
    if (value == null) return fallback;
    final text = '$value'.trim();
    return text.isEmpty ? fallback : text;
  }

  static String? _optionalStr(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  static int _int(Object? value, int fallback) => value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  static double? _optionalDouble(Object? value) => value is num ? value.toDouble() : double.tryParse('$value');
}
