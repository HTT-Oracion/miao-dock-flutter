import 'online_models.dart';
import 'online_source.dart';

/// 漫画源引擎接口（plan §4.3）。
///
/// 当前实现是 [DemoSourceEngine]：按导入的 manifest 回放内置演示数据，
/// 让浏览 / 详情 / 阅读 / 下载 / 翻译全链路可以在没有原生 QuickJS 的
/// 构建里跑通。QuickJS 实现只需替换这一个 provider，上层不感知。
abstract interface class SourceEngine {
  /// 源加载（可选 `init` 钩子也在这里执行一次）。
  Future<void> ensureLoaded(OnlineSource source);

  Future<HomeFeed> explore(OnlineSource source, {required int page});

  Future<List<CategoryGroup>> categories(OnlineSource source);

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
