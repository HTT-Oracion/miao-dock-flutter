import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/manga/online/controller/online_browse_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/controller/online_detail_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/controller/online_download_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/controller/online_progress_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/controller/online_reader_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/controller/online_sources_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_image_loader.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_repository.dart';
import 'package:miao_dock_flutter/features/manga/online/data/translation_gateway.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_download.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/source_engine.dart';

import 'fake_engine.dart';
import 'fake_image_loader.dart';
import 'test_data.dart';
import 'test_store.dart';

class QuickTranslationGateway implements OnlineTranslationGateway {
  @override
  Stream<TranslationStatus> translate({
    required String sourceId,
    required String comicId,
    required String chapterId,
    required int total,
    bool fromCurrentPage = false,
  }) async* {
    yield TranslationStatus(state: TranslationState.queued, total: total);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    yield TranslationStatus(state: TranslationState.running, done: 5, total: total);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    yield TranslationStatus(state: TranslationState.done, done: total, total: total);
  }
}

ProviderContainer containerWith({SourceEngine? engine, OnlineTranslationGateway? gateway}) {
  final container = ProviderContainer(
    overrides: [
      onlineStoreProvider.overrideWithValue(MemoryStore()),
      sourceEngineProvider.overrideWithValue(engine ?? FakeSourceEngine()),
      onlineImageLoaderProvider.overrideWithValue(FakeImageLoader()),
      if (gateway != null) onlineTranslationGatewayProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('首页加载成功 / 分类与搜索 / 详情', () async {
    final container = containerWith();
    final sources = await container.read(onlineSourcesProvider.future);
    expect(sources, isNotEmpty);
    final source = container.read(activeOnlineSourceProvider)!;
    expect(source.id, 'manhuagui');

    final feed = await container.read(onlineFeedProvider.future);
    expect(feed.feed.sections.length, 2);
    expect(feed.feed.sections.first.items, isNotEmpty);

    final categories = await container.read(onlineCategoriesProvider.future);
    expect(categories, isNotEmpty);

    container.read(onlineNavProvider.notifier).selectCategory('hotblood');
    final category = await container.read(onlineCategoryResultsProvider.future);
    expect(category.page.items, isNotEmpty);

    container.read(onlineNavProvider.notifier).submitSearch('海贼');
    final search = await container.read(onlineSearchProvider.future);
    expect(search, isNotNull);
    expect(search!.page.items.first.title, '海贼王');

    await container.read(onlineDetailProvider.notifier).open('manhuagui', 'kimetsu');
    final detail = container.read(onlineDetailProvider).value;
    expect(detail, isNotNull);
    expect(detail!.chapters.first.title, '第206话 决战之后');
  });

  test('源连续失败累计（3 次熔断红点）', () async {
    final container = containerWith(engine: FailingEngine());
    await container.read(onlineSourcesProvider.future);
    for (var i = 0; i < 3; i++) {
      try {
        await container.read(onlineFeedProvider.future);
      } catch (_) {
        // 预期失败
      }
      // 让 markFailure 的微任务落地，再触发下一次请求。
      await Future<void>.delayed(const Duration(milliseconds: 10));
      container.invalidate(onlineFeedProvider);
    }
    final source = container.read(onlineSourcesProvider).value!.firstWhere((s) => s.id == 'manhuagui');
    expect(source.consecutiveFailures, greaterThanOrEqualTo(3));
    expect(source.isAbnormal, isTrue);
  });

  test('阅读器：页数 / 页图失败重试 / 进度写入 / 翻译状态机', () async {
    final container = containerWith(gateway: QuickTranslationGateway());
    await container.read(onlineSourcesProvider.future);
    await container.read(onlineRecentProvider.future);
    final source = container.read(activeOnlineSourceProvider)!;
    final comic = OnlineTestData.comicById('kimetsu')!;
    final chapter = OnlineTestData.chaptersOf('kimetsu').first;

    await container
        .read(onlineReaderProvider.notifier)
        .open(
          source: source,
          comic: comic,
          chapter: chapter,
          chapters: OnlineTestData.chaptersOf('kimetsu'),
          startPage: 10,
        );
    await Future<void>.delayed(const Duration(milliseconds: 450));
    var state = container.read(onlineReaderProvider)!;
    expect(state.pageCount, 26);
    expect(state.page, 10);

    container.read(onlineReaderProvider.notifier).goToPage(13);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    state = container.read(onlineReaderProvider)!;
    expect(state.pageError, isNotNull);

    container.read(onlineReaderProvider.notifier).retryPage();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    state = container.read(onlineReaderProvider)!;
    expect(state.pageError, isNull);

    final recent = container.read(onlineRecentProvider).value!;
    expect(recent.first.comicId, 'kimetsu');
    expect(recent.first.page, 13);

    await container.read(onlineReaderProvider.notifier).startTranslation();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    state = container.read(onlineReaderProvider)!;
    expect(state.translation.state, TranslationState.done);
    expect(state.translation.done, 26);
    expect(state.canToggleTranslated, isTrue);

    container.read(onlineReaderProvider.notifier).setShowOriginal(false);
    expect(container.read(onlineReaderProvider)!.showingTranslated, isTrue);
  });

  test('下载队列：建单 / 暂停 / 继续 / 取消', () async {
    final container = containerWith();
    await container.read(onlineSourcesProvider.future);
    await container.read(onlineDownloadsProvider.future);
    final source = container.read(activeOnlineSourceProvider)!;
    final comic = OnlineTestData.comicById('kimetsu')!;
    final chapter = OnlineTestData.chaptersOf('kimetsu').first;
    final task = await container
        .read(onlineDownloadsProvider.notifier)
        .begin(source: source, comic: comic, chapter: chapter, target: DownloadTarget.library, translate: true);
    expect(task, isNotNull);
    expect(task!.total, 26);
    expect(task.status, DownloadStatus.downloading);

    container.read(onlineDownloadsProvider.notifier).pause(task.id);
    expect(container.read(onlineDownloadsProvider).value!.first.status, DownloadStatus.paused);
    container.read(onlineDownloadsProvider.notifier).resume(task.id);
    expect(container.read(onlineDownloadsProvider).value!.first.status, DownloadStatus.downloading);
    container.read(onlineDownloadsProvider.notifier).cancel(task.id);
    expect(container.read(onlineDownloadsProvider).value!.first.status, DownloadStatus.canceled);

    final partial = OnlineTestData.seedDownloads(DateTime.now()).firstWhere((t) => t.status == DownloadStatus.partial);
    expect(partial.canResume, isTrue);
  });
}
