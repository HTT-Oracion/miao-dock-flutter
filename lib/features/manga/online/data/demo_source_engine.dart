import 'dart:async';

import '../domain/online_error.dart';
import '../domain/online_models.dart';
import '../domain/online_source.dart';
import '../domain/source_engine.dart';
import 'demo_online_data.dart';

/// 演示引擎：不加载原生 QuickJS，按源 manifest 回放 [DemoOnlineData]。
///
/// 它保持与真实引擎**相同的异步形状和错误模型**，所以 controller、阅读器
/// 图片管道和下载队列都是真链路；换真引擎只替换 provider。
class DemoSourceEngine implements SourceEngine {
  DemoSourceEngine({this.delay = const Duration(milliseconds: 260)});

  /// 单次能力调用延迟（骨架屏需要可见的加载时间）。
  final Duration delay;

  final Set<String> _loaded = {};

  Future<void> _latency([Duration? override]) => Future<void>.delayed(override ?? delay);

  void _guard(OnlineSource source) {
    if (!source.enabled) throw const OnlineException(OnlineErrorCode.crashed, 'source disabled');
    if (source.id == 'mangabz') {
      throw const OnlineException(OnlineErrorCode.crashed, 'source circuit open');
    }
  }

  @override
  Future<void> ensureLoaded(OnlineSource source) async {
    _guard(source);
    if (_loaded.add(source.id)) await _latency(const Duration(milliseconds: 60));
  }

  @override
  Future<HomeFeed> explore(OnlineSource source, {required int page}) async {
    await ensureLoaded(source);
    await _latency();
    final sections = DemoOnlineData.feedPage(page);
    return HomeFeed(sections: sections, page: page, hasMore: page < 2, total: 42);
  }

  @override
  Future<List<CategoryGroup>> categories(OnlineSource source) async {
    await ensureLoaded(source);
    await _latency();
    return DemoOnlineData.categoryGroups;
  }

  @override
  Future<PagedComics> category(OnlineSource source, {required String id, required int page}) async {
    await ensureLoaded(source);
    await _latency();
    final items = DemoOnlineData.comicsInCategory(id, page: page);
    if (items.isEmpty && page > 1) {
      return PagedComics(items: const [], page: page, hasMore: false, total: 6);
    }
    return PagedComics(items: items, page: page, hasMore: page < 2, total: 6);
  }

  @override
  Future<PagedComics> search(OnlineSource source, {required String keyword, required int page}) async {
    await ensureLoaded(source);
    await _latency();
    final items = DemoOnlineData.search(keyword, page: page);
    return PagedComics(items: items, page: page, hasMore: page < 2 && items.length >= 6, total: items.length);
  }

  @override
  Future<OnlineComicDetail> loadComicInfo(OnlineSource source, {required String comicId}) async {
    await ensureLoaded(source);
    await _latency();
    final comic = DemoOnlineData.comicById(comicId);
    if (comic == null) throw const OnlineException(OnlineErrorCode.notFound, 'comic not found');
    return OnlineComicDetail(comic: comic, chapters: DemoOnlineData.chaptersOf(comicId));
  }

  @override
  Future<List<ImageLoadingConfig>> loadComicPages(
    OnlineSource source, {
    required String comicId,
    required String chapterId,
  }) async {
    await ensureLoaded(source);
    await _latency();
    final count = DemoOnlineData.pageCountOf(comicId);
    return [
      for (var i = 1; i <= count; i++)
        ImageLoadingConfig(
          url: 'https://cf.mhgui.com/img/$comicId/$chapterId/$i.webp?e=173166&m=${'${chapterId}_$i'.hashCode.abs()}',
          headers: {'Referer': '${source.manifest.baseUrl}/'},
        ),
    ];
  }

  @override
  Future<ImageLoadingConfig> getImageLoadingConfig(
    OnlineSource source, {
    required String url,
    required String comicId,
    required String chapterId,
  }) async {
    await ensureLoaded(source);
    return ImageLoadingConfig(url: url, headers: {'Referer': '${source.manifest.baseUrl}/'});
  }

  @override
  Future<void> unload(String sourceId) async {
    _loaded.remove(sourceId);
  }

  @override
  Future<void> dispose() async {
    _loaded.clear();
  }
}
