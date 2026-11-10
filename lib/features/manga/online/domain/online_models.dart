import 'dart:math' as math;

/// 漫画连载状态（plan §5.4 `status`）。
enum ComicStatus {
  ongoing,
  completed,
  unknown;

  static ComicStatus parse(Object? raw) => switch ('$raw') {
    'ongoing' => ComicStatus.ongoing,
    'completed' => ComicStatus.completed,
    _ => ComicStatus.unknown,
  };
}

/// 封面色调。设计稿用八组语义化渐变 + 书名占位，不使用随机图 / emoji。
enum CoverTone { red, blue, orange, olive, gold, purple, teal, steel }

/// 统一的漫画条目（plan §5.4 `Comic`）。
class OnlineComic {
  const OnlineComic({
    required this.id,
    required this.title,
    this.coverTone = CoverTone.blue,
    this.subtitle,
    this.author,
    this.tags = const [],
    this.description = '',
    this.status = ComicStatus.unknown,
    this.chapterCount = 0,
    this.latestChapter,
    this.badge,
  });

  final String id;
  final String title;
  final CoverTone coverTone;

  /// 副标题 / 最新话，直接展示。
  final String? subtitle;
  final String? author;
  final List<String> tags;
  final String description;
  final ComicStatus status;

  /// 总话数（用于「235 话」与「完结 · 全271话」）。
  final int chapterCount;

  /// 最新话展示文本，如 `第206话`。
  final String? latestChapter;

  /// 封面角标（更新 / 新 / 完结等），源数据，不做本地化。
  final String? badge;
}

/// 章节分组（设计稿：连载 → 番外 → 单行本）。
enum ChapterGroup { serial, extra, volume }

/// 章节（plan §5.4 `Chapter`）。
class OnlineChapter {
  const OnlineChapter({required this.id, required this.title, required this.group, this.no});

  final String id;
  final String title;
  final ChapterGroup group;

  /// 可选话号，用于排序 / 进度显示。
  final double? no;
}

/// 详情（plan §5.4 `ComicDetail`）。
class OnlineComicDetail {
  const OnlineComicDetail({required this.comic, required this.chapters});

  final OnlineComic comic;
  final List<OnlineChapter> chapters;

  List<OnlineChapter> groupOf(ChapterGroup group) => chapters.where((c) => c.group == group).toList();

  bool get hasChapters => chapters.isNotEmpty;
}

/// 首页分区（plan §5.4 `FeedSection`）。
class FeedSection {
  const FeedSection({
    required this.id,
    required this.title,
    required this.items,
    this.layout = 'grid',
    this.moreId,
    this.pageSize = 42,
    this.hint = '',
  });

  final String id;
  final String title;
  final List<OnlineComic> items;
  final String layout;
  final String? moreId;

  /// 分区每页条数（设计稿「42 条 / 页」）。
  final int pageSize;

  /// 调试提示（设计稿 `explore · section=update · page=1`），源数据。
  final String hint;
}

/// 首页（plan §5.4 `HomeFeed`）。
class HomeFeed {
  const HomeFeed({required this.sections, this.page = 1, this.hasMore = false, this.total = 0});

  final List<FeedSection> sections;
  final int page;
  final bool hasMore;
  final int total;

  bool get isEmpty => sections.every((section) => section.items.isEmpty);

  HomeFeed copyWith({List<FeedSection>? sections, int? page, bool? hasMore, int? total}) => HomeFeed(
    sections: sections ?? this.sections,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    total: total ?? this.total,
  );

  /// 分页追加：按 section id 合并，卡片去重。
  HomeFeed append(HomeFeed next) {
    final merged = <FeedSection>[];
    for (final section in sections) {
      FeedSection? addition;
      for (final candidate in next.sections) {
        if (candidate.id == section.id) {
          addition = candidate;
          break;
        }
      }
      if (addition == null) {
        merged.add(section);
        continue;
      }
      final seen = section.items.map((e) => e.id).toSet();
      merged.add(
        FeedSection(
          id: section.id,
          title: section.title,
          items: [...section.items, ...addition.items.where((c) => seen.add(c.id))],
          layout: section.layout,
          moreId: section.moreId,
          pageSize: section.pageSize,
          hint: section.hint,
        ),
      );
    }
    return HomeFeed(sections: merged, page: next.page, hasMore: next.hasMore, total: next.total);
  }
}

/// 分页列表（plan §5.4 `PagedComics`）。
class PagedComics {
  const PagedComics({required this.items, required this.page, required this.hasMore, this.total = 0});

  final List<OnlineComic> items;
  final int page;
  final bool hasMore;
  final int total;

  PagedComics append(PagedComics next) {
    final seen = items.map((e) => e.id).toSet();
    return PagedComics(
      items: [...items, ...next.items.where((c) => seen.add(c.id))],
      page: next.page,
      hasMore: next.hasMore,
      total: next.total,
    );
  }
}

/// 分类项 / 分类组（plan §5.4）。
class CategoryItem {
  const CategoryItem({required this.id, required this.name});

  final String id;
  final String name;
}

class CategoryGroup {
  const CategoryGroup({required this.id, required this.name, required this.items});

  final String id;
  final String name;
  final List<CategoryItem> items;
}

/// 取图配置（plan §5.3 `getImageLoadingConfig` 首期子集）。
class ImageLoadingConfig {
  const ImageLoadingConfig({this.url, this.method = 'GET', this.headers = const {}});

  final String? url;
  final String method;
  final Map<String, String> headers;
}

/// 在线阅读进度（设计稿：键 = sourceId + comicId + chapterId + page）。
class ReadingProgress {
  const ReadingProgress({
    required this.sourceId,
    required this.sourceName,
    required this.comicId,
    required this.comicTitle,
    required this.coverTone,
    required this.chapterId,
    required this.chapterTitle,
    required this.page,
    required this.pageCount,
    required this.updatedAt,
  });

  final String sourceId;
  final String sourceName;
  final String comicId;
  final String comicTitle;
  final CoverTone coverTone;
  final String chapterId;
  final String chapterTitle;
  final int page;
  final int pageCount;
  final DateTime updatedAt;

  String get key => progressKey(sourceId: sourceId, comicId: comicId, chapterId: chapterId);
  int get pageIndex => page.clamp(1, math.max(pageCount, 1));
  double get fraction => pageCount <= 0 ? 0 : (page / pageCount).clamp(0, 1);

  ReadingProgress copyWith({int? page, int? pageCount, DateTime? updatedAt, String? chapterId, String? chapterTitle}) =>
      ReadingProgress(
        sourceId: sourceId,
        sourceName: sourceName,
        comicId: comicId,
        comicTitle: comicTitle,
        coverTone: coverTone,
        chapterId: chapterId ?? this.chapterId,
        chapterTitle: chapterTitle ?? this.chapterTitle,
        page: page ?? this.page,
        pageCount: pageCount ?? this.pageCount,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'sourceName': sourceName,
    'comicId': comicId,
    'comicTitle': comicTitle,
    'coverTone': coverTone.name,
    'chapterId': chapterId,
    'chapterTitle': chapterTitle,
    'page': page,
    'pageCount': pageCount,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static ReadingProgress? fromJson(Map<String, Object?> json) {
    final sourceId = json['sourceId'];
    final comicId = json['comicId'];
    final chapterId = json['chapterId'];
    if (sourceId is! String || comicId is! String || chapterId is! String) return null;
    return ReadingProgress(
      sourceId: sourceId,
      sourceName: '${json['sourceName'] ?? ''}',
      comicId: comicId,
      comicTitle: '${json['comicTitle'] ?? ''}',
      coverTone: CoverTone.values.firstWhere((tone) => tone.name == json['coverTone'], orElse: () => CoverTone.blue),
      chapterId: chapterId,
      chapterTitle: '${json['chapterTitle'] ?? ''}',
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 1,
      updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? DateTime.now(),
    );
  }
}

/// 进度唯一键：必须带 sourceId，防止跨源同名漫画串进度（设计稿 §三）。
String progressKey({required String sourceId, required String comicId, required String chapterId}) =>
    '$sourceId|$comicId|$chapterId';

/// 已读章节集合的键（`sourceId|comicId`）。
String readChaptersKey({required String sourceId, required String comicId}) => '$sourceId|$comicId';

/// 扫描 `source.js` 中实现的能力名（导入试跑用，不执行 JS）。
///
/// 只匹配函数声明形态，不误伤注释里的字符串；能力数量用于源管理列表的
/// 「N 项能力」展示，与设计稿的能力计数一致。
Set<String> detectCapabilities(String js) {
  const names = [
    'explore',
    'categories',
    'category',
    'search',
    'loadComicInfo',
    'loadComicPages',
    'getImageLoadingConfig',
    'init',
  ];
  final found = <String>{};
  for (final name in names) {
    final pattern = RegExp('(?:^|[\\s;{}])$name\\s*(?:\\(|=)', multiLine: true);
    if (pattern.hasMatch(js)) found.add(name);
  }
  return found;
}
