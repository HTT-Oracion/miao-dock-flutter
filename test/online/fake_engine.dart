import 'package:miao_dock_flutter/features/manga/online/domain/online_download.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_models.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_source.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/source_engine.dart';

import 'test_data.dart';

/// 测试夹具引擎：不加载 QuickJS，按 [OnlineTestData] 回放。
class FakeSourceEngine implements SourceEngine {
  FakeSourceEngine({this.delay = Duration.zero, this.rankTabsDelay, this.rankPageDelay});

  final Duration delay;
  final Duration? rankTabsDelay;
  final Duration? rankPageDelay;
  final Set<String> unloaded = {};

  Future<void> _wait([Duration? override]) async {
    final wait = override ?? delay;
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }

  @override
  Future<void> ensureLoaded(OnlineSource source) async => _wait();

  @override
  Future<HomeFeed> explore(OnlineSource source, {required int page}) async {
    await _wait();
    return HomeFeed(sections: OnlineTestData.feedPage(page), page: page, hasMore: page < 2, total: 42);
  }

  @override
  Future<List<CategoryGroup>> categories(OnlineSource source) async {
    await _wait();
    return OnlineTestData.categoryGroups;
  }

  @override
  Future<List<RankTab>> rankTabs(OnlineSource source) async {
    await _wait(rankTabsDelay);
    if (!source.hasRank) return const [];
    return const [
      RankTab(id: 'day', title: '日排行'),
      RankTab(id: 'week', title: '周排行'),
      RankTab(id: 'month', title: '月排行'),
      RankTab(id: 'total', title: '总排行'),
    ];
  }

  @override
  Future<PagedComics> rank(OnlineSource source, {required String tabId, required int page}) async {
    await _wait(rankPageDelay);
    final items = OnlineTestData.rankedComics(tabId, page: page);
    return PagedComics(items: items, page: page, hasMore: false, total: items.length);
  }

  @override
  Future<PagedComics> category(OnlineSource source, {required String id, required int page}) async {
    await _wait();
    final items = OnlineTestData.comicsInCategory(id, page: page);
    return PagedComics(items: items, page: page, hasMore: page < 2, total: items.length * 2);
  }

  @override
  Future<PagedComics> search(OnlineSource source, {required String keyword, required int page}) async {
    await _wait();
    final items = OnlineTestData.search(keyword, page: page);
    return PagedComics(items: items, page: page, hasMore: false, total: items.length);
  }

  @override
  Future<OnlineComicDetail> loadComicInfo(OnlineSource source, {required String comicId}) async {
    await _wait();
    final comic = OnlineTestData.comicById(comicId);
    if (comic == null) throw StateError('not found');
    return OnlineComicDetail(comic: comic, chapters: OnlineTestData.chaptersOf(comicId));
  }

  @override
  Future<List<ImageLoadingConfig>> loadComicPages(
    OnlineSource source, {
    required String comicId,
    required String chapterId,
  }) async {
    await _wait();
    final count = OnlineTestData.pageCountOf(comicId);
    return [
      for (var i = 1; i <= count; i++) ImageLoadingConfig(url: 'https://example.com/demo/$comicId/$chapterId/$i.jpg'),
    ];
  }

  @override
  Future<ImageLoadingConfig> getImageLoadingConfig(
    OnlineSource source, {
    required String url,
    required String comicId,
    required String chapterId,
  }) async => ImageLoadingConfig(url: url);

  @override
  Future<void> unload(String sourceId) async => unloaded.add(sourceId);

  @override
  Future<void> dispose() async {}
}

class FailingEngine extends FakeSourceEngine {
  @override
  Future<HomeFeed> explore(OnlineSource source, {required int page}) async {
    throw StateError('blocked');
  }

  @override
  Future<List<ImageLoadingConfig>> loadComicPages(
    OnlineSource source, {
    required String comicId,
    required String chapterId,
  }) async {
    throw StateError('pages failed');
  }
}

/// 下载 fixture 里保持一个“部分成功”任务，测试能直接断言可续传。
DownloadTask partialTask(DateTime now) =>
    OnlineTestData.seedDownloads(now).firstWhere((task) => task.status == DownloadStatus.partial);
