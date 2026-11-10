import 'online_models.dart';
import 'online_source.dart';

/// 漫画源引擎接口（plan §4.3）。
///
/// 生产实现是 QuickJS 源引擎；测试注入 Fixture 实现。上层只依赖本接口。
abstract interface class SourceEngine {
  /// 源加载（可选 `init` 钩子也在这里执行一次）。
  Future<void> ensureLoaded(OnlineSource source);

  Future<HomeFeed> explore(OnlineSource source, {required int page});

  Future<List<CategoryGroup>> categories(OnlineSource source);

  /// 源声明的排行分类；无排行返回空列表。
  Future<List<RankTab>> rankTabs(OnlineSource source);

  Future<PagedComics> rank(OnlineSource source, {required String tabId, required int page});

  Future<PagedComics> category(OnlineSource source, {required String id, required int page});

  Future<PagedComics> search(OnlineSource source, {required String keyword, required int page});

  Future<OnlineComicDetail> loadComicInfo(OnlineSource source, {required String comicId});

  Future<List<ImageLoadingConfig>> loadComicPages(
    OnlineSource source, {
    required String comicId,
    required String chapterId,
  });

  Future<ImageLoadingConfig> getImageLoadingConfig(
    OnlineSource source, {
    required String url,
    required String comicId,
    required String chapterId,
  });

  Future<void> unload(String sourceId);

  Future<void> dispose();
}
