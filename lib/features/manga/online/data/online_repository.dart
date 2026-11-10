import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/online_error.dart';
import '../domain/online_models.dart';
import '../domain/online_source.dart';
import '../domain/source_engine.dart';
import 'js/quickjs_source_engine.dart';
import 'online_store.dart';

/// 在线漫画仓库：controller 只依赖这一层，UI 不碰引擎与存储。
class OnlineRepository {
  const OnlineRepository({required this.engine, required this.store});

  final SourceEngine engine;
  final OnlineStore store;

  Future<void> ensureLoaded(OnlineSource source) => engine.ensureLoaded(source);

  Future<HomeFeed> explore(OnlineSource source, int page) => engine.explore(source, page: page);

  Future<List<CategoryGroup>> categories(OnlineSource source) => engine.categories(source);

  Future<PagedComics> category(OnlineSource source, String id, int page) => engine.category(source, id: id, page: page);

  Future<PagedComics> search(OnlineSource source, String keyword, int page) =>
      engine.search(source, keyword: keyword, page: page);

  Future<OnlineComicDetail> detail(OnlineSource source, String comicId) =>
      engine.loadComicInfo(source, comicId: comicId);

  Future<List<ImageLoadingConfig>> pages(OnlineSource source, String comicId, String chapterId) =>
      engine.loadComicPages(source, comicId: comicId, chapterId: chapterId);

  Future<ImageLoadingConfig> imageConfig(OnlineSource source, String url, String comicId, String chapterId) =>
      engine.getImageLoadingConfig(source, url: url, comicId: comicId, chapterId: chapterId);

  /// 切源 / 调用前统一维护熔断：连续失败 3 次在源列表里标红。
  Never fail(OnlineErrorCode code, [String message = '']) => throw OnlineException(code, message);
}

final sourceEngineProvider = Provider<SourceEngine>((ref) {
  final engine = QuickJsSourceEngine();
  ref.onDispose(() {
    engine.dispose();
  });
  return engine;
});

final onlineStoreProvider = Provider<OnlineStore>((ref) => OnlineStore());

final onlineRepositoryProvider = Provider<OnlineRepository>((ref) {
  return OnlineRepository(engine: ref.watch(sourceEngineProvider), store: ref.watch(onlineStoreProvider));
});
