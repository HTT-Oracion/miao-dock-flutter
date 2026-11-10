import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/online_repository.dart';
import '../domain/online_models.dart';
import '../domain/online_source.dart';
import 'online_sources_controller.dart';

/// 当前详情（桌面主区 / 移动滑层）。
final onlineDetailProvider = AsyncNotifierProvider<OnlineDetailNotifier, OnlineComicDetail?>(
  OnlineDetailNotifier.new,
  retry: (_, _) => null,
);

class OnlineDetailNotifier extends AsyncNotifier<OnlineComicDetail?> {
  int _request = 0;
  String? _sourceId;
  String? _comicId;

  @override
  Future<OnlineComicDetail?> build() async => null;

  Future<void> open(String sourceId, String comicId) async {
    final request = ++_request;
    _sourceId = sourceId;
    _comicId = comicId;
    state = const AsyncLoading();
    try {
      final sources = ref.read(onlineSourcesProvider).value ?? const <OnlineSource>[];
      OnlineSource? source;
      for (final item in sources) {
        if (item.id == sourceId) {
          source = item;
          break;
        }
      }
      if (source == null) throw StateError('source not found');
      final detail = await ref.read(onlineRepositoryProvider).detail(source, comicId);
      ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
      if (request != _request) return;
      state = AsyncData(detail);
    } catch (error, stack) {
      final id = _sourceId;
      if (id != null) ref.read(onlineSourcesProvider.notifier).markFailure(id);
      if (request != _request) return;
      state = AsyncError(error, stack);
    }
  }

  Future<void> refresh() async {
    final sourceId = _sourceId;
    final comicId = _comicId;
    if (sourceId == null || comicId == null) return;
    await open(sourceId, comicId);
  }
}

/// 阅读器启动参数：路由只承载「打开阅读器」这一件事，具体章节对象随内存传递，
/// 避免把整棵章节数组序列化进 URL。
class OnlineReaderLaunch {
  const OnlineReaderLaunch({
    required this.source,
    required this.comic,
    required this.chapter,
    required this.chapters,
    this.page,
    this.autoTranslate = false,
    this.returnLocation = '/manga/online',
  });

  final OnlineSource source;
  final OnlineComic comic;
  final OnlineChapter chapter;
  final List<OnlineChapter> chapters;
  final int? page;
  final bool autoTranslate;
  final String returnLocation;
}

final onlineReaderLaunchProvider = NotifierProvider<OnlineReaderLaunchNotifier, OnlineReaderLaunch?>(
  OnlineReaderLaunchNotifier.new,
);

class OnlineReaderLaunchNotifier extends Notifier<OnlineReaderLaunch?> {
  @override
  OnlineReaderLaunch? build() => null;

  void set(OnlineReaderLaunch launch) => state = launch;

  void clear() => state = null;
}
