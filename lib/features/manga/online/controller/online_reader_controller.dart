import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/online_image_loader.dart';
import '../data/online_repository.dart';
import '../data/translation_gateway.dart';
import '../domain/online_download.dart';
import '../domain/online_error.dart';
import '../domain/online_models.dart';
import '../domain/online_source.dart';
import 'online_progress_controller.dart';
import 'online_sources_controller.dart';

/// 翻译范围（翻译设置抽屉）。
enum TranslationRange { chapter, fromCurrentPage }

/// 在线阅读器状态（页面、工具栏、翻译、阅读偏好）。
class OnlineReaderState {
  const OnlineReaderState({
    required this.sourceId,
    required this.sourceName,
    required this.sourceHosts,
    required this.comic,
    required this.chapter,
    required this.chapters,
    required this.pageCount,
    this.page = 1,
    this.pageBytes,
    this.pageConfigs = const [],
    this.pageLoading = true,
    this.pageError,
    this.loadingPages = false,
    this.pagesError,
    this.translationEnabled = false,
    this.translation = const TranslationStatus(),
    this.showOriginal = true,
    this.controlsVisible = true,
    this.osdVisible = false,
    this.range = TranslationRange.chapter,
    this.retranslate = true,
  });

  final String sourceId;
  final String sourceName;
  final List<String> sourceHosts;
  final OnlineComic comic;
  final OnlineChapter chapter;
  final List<OnlineChapter> chapters;
  final int pageCount;
  final int page;

  /// 当前页已解码的图片字节；null = 尚未取到图。
  final Uint8List? pageBytes;
  final List<ImageLoadingConfig> pageConfigs;
  final bool pageLoading;
  final Object? pageError;
  final bool loadingPages;
  final Object? pagesError;
  final bool translationEnabled;
  final TranslationStatus translation;
  final bool showOriginal;
  final bool controlsVisible;
  final bool osdVisible;
  final TranslationRange range;
  final bool retranslate;

  bool get hasTranslation => translation.done > 0;
  bool get canToggleTranslated => translation.translatedReady;
  bool get canCompare => false;
  double get progress => pageCount <= 0 ? 0 : (page / pageCount).clamp(0, 1);

  /// 当前页是否已有译文（准实时逐页渐进）。
  bool get currentPageTranslated => pageHasTranslation(page);

  bool pageHasTranslation(int targetPage) => translation.done >= targetPage && translation.translatedReady;

  bool get showingTranslated => !showOriginal && canToggleTranslated;

  int get chapterIndex => chapters.indexWhere((c) => c.id == chapter.id);
  OnlineChapter? get prevChapter {
    final index = chapterIndex;
    return index > 0 ? chapters[index - 1] : null;
  }

  OnlineChapter? get nextChapter {
    final index = chapterIndex;
    return index >= 0 && index < chapters.length - 1 ? chapters[index + 1] : null;
  }

  OnlineReaderState copyWith({
    OnlineComic? comic,
    OnlineChapter? chapter,
    List<OnlineChapter>? chapters,
    List<String>? sourceHosts,
    int? pageCount,
    int? page,
    Uint8List? pageBytes,
    bool clearPageBytes = false,
    List<ImageLoadingConfig>? pageConfigs,
    bool? pageLoading,
    Object? pageError,
    bool clearPageError = false,
    bool? loadingPages,
    Object? pagesError,
    bool clearPagesError = false,
    bool? translationEnabled,
    TranslationStatus? translation,
    bool? showOriginal,
    bool? controlsVisible,
    bool? osdVisible,
    TranslationRange? range,
    bool? retranslate,
  }) => OnlineReaderState(
    sourceId: sourceId,
    sourceName: sourceName,
    sourceHosts: sourceHosts ?? this.sourceHosts,
    comic: comic ?? this.comic,
    chapter: chapter ?? this.chapter,
    chapters: chapters ?? this.chapters,
    pageCount: pageCount ?? this.pageCount,
    page: page ?? this.page,
    pageBytes: clearPageBytes ? null : (pageBytes ?? this.pageBytes),
    pageConfigs: pageConfigs ?? this.pageConfigs,
    pageLoading: pageLoading ?? this.pageLoading,
    pageError: clearPageError ? null : (pageError ?? this.pageError),
    loadingPages: loadingPages ?? this.loadingPages,
    pagesError: clearPagesError ? null : (pagesError ?? this.pagesError),
    translationEnabled: translationEnabled ?? this.translationEnabled,
    translation: translation ?? this.translation,
    showOriginal: showOriginal ?? this.showOriginal,
    controlsVisible: controlsVisible ?? this.controlsVisible,
    osdVisible: osdVisible ?? this.osdVisible,
    range: range ?? this.range,
    retranslate: retranslate ?? this.retranslate,
  );
}

final onlineReaderProvider = NotifierProvider<OnlineReaderNotifier, OnlineReaderState?>(OnlineReaderNotifier.new);

class OnlineReaderNotifier extends Notifier<OnlineReaderState?> {
  Timer? _osdTimer;
  Timer? _translationTimer;
  StreamSubscription<TranslationStatus>? _translationSub;
  final Set<String> _prefetched = {};
  int _pageRequest = 0;

  @override
  OnlineReaderState? build() {
    ref.onDispose(() {
      _osdTimer?.cancel();
      _translationTimer?.cancel();
      _translationSub?.cancel();
    });
    return null;
  }

  /// 打开阅读器。先取章节页列表（真实图片管道的入口），再渲染当前页。
  Future<void> open({
    required OnlineSource source,
    required OnlineComic comic,
    required OnlineChapter chapter,
    required List<OnlineChapter> chapters,
    int? startPage,
  }) async {
    _translationSub?.cancel();
    final initialPage = (startPage ?? 1).clamp(1, 9999);
    state = OnlineReaderState(
      sourceId: source.id,
      sourceName: source.name,
      sourceHosts: source.manifest.hosts,
      translationEnabled: source.translationEnabled,
      comic: comic,
      chapter: chapter,
      chapters: chapters.isEmpty ? [chapter] : chapters,
      pageCount: 0,
      page: initialPage,
      loadingPages: true,
      pageLoading: true,
    );
    try {
      final pages = await ref.read(onlineRepositoryProvider).pages(source, comic.id, chapter.id);
      ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
      if (state == null) return;
      final count = pages.length;
      if (count == 0) {
        state = state!.copyWith(
          loadingPages: false,
          pageLoading: false,
          pageConfigs: const [],
          pagesError: const OnlineException(OnlineErrorCode.parse, 'empty chapter'),
        );
        return;
      }
      final page = startPage == null ? 1 : initialPage.clamp(1, count);
      state = state!.copyWith(
        pageCount: count,
        page: page,
        pageConfigs: pages,
        loadingPages: false,
        translation: state!.translation.copyWith(total: count),
      );
      unawaited(_loadPage(page));
    } catch (e) {
      ref.read(onlineSourcesProvider.notifier).markFailure(source.id);
      if (state == null) return;
      state = state!.copyWith(loadingPages: false, pagesError: e, pageLoading: false);
    }
  }

  /// 详情页「继续阅读 / 点章节」都走这里：保留章节进度，换章节时重置翻译。
  Future<void> switchChapter({required OnlineChapter chapter, int? startPage}) async {
    final current = state;
    if (current == null) return;
    final id = state!.sourceId;
    OnlineSource? source;
    final sources = ref.read(onlineSourcesProvider).value ?? const <OnlineSource>[];
    for (final item in sources) {
      if (item.id == id) {
        source = item;
        break;
      }
    }
    if (source == null) return;
    _translationSub?.cancel();
    _osdTimer?.cancel();
    state = current.copyWith(
      chapter: chapter,
      page: startPage ?? 1,
      pageLoading: true,
      loadingPages: true,
      clearPageError: true,
      clearPageBytes: true,
      translation: TranslationStatus(total: current.pageCount),
      showOriginal: true,
      controlsVisible: true,
    );
    try {
      final pages = await ref.read(onlineRepositoryProvider).pages(source, current.comic.id, chapter.id);
      if (state == null) return;
      final count = pages.length;
      if (count == 0) {
        state = state!.copyWith(
          loadingPages: false,
          pageLoading: false,
          pageConfigs: const [],
          pagesError: const OnlineException(OnlineErrorCode.parse, 'empty chapter'),
        );
        return;
      }
      final page = (startPage ?? 1).clamp(1, count);
      state = state!.copyWith(
        pageCount: count,
        page: page,
        pageConfigs: pages,
        loadingPages: false,
        translation: state!.translation.copyWith(total: count),
      );
      unawaited(_loadPage(page));
    } catch (e) {
      if (state == null) return;
      state = state!.copyWith(loadingPages: false, pageLoading: false, pagesError: e);
    }
  }

  Future<void> _loadPage(int page) async {
    final current = state;
    if (current == null) return;
    final token = ++_pageRequest;
    state = current.copyWith(page: page, pageLoading: true, clearPageError: true, clearPageBytes: true);
    _showOsd();
    final configs = state!.pageConfigs;
    if (page < 1 || page > configs.length) {
      state = state!.copyWith(
        pageLoading: false,
        pageError: const OnlineException(OnlineErrorCode.parse, 'page out of range'),
      );
      return;
    }
    try {
      final bytes = await ref
          .read(onlineImageLoaderProvider)
          .load(configs[page - 1], sourceId: state!.sourceId, allowedHosts: state!.sourceHosts);
      if (state == null || token != _pageRequest) return;
      state = state!.copyWith(pageLoading: false, pageBytes: bytes);
      _prefetch(page);
      _commitProgress();
    } catch (e) {
      if (state == null || token != _pageRequest) return;
      state = state!.copyWith(pageLoading: false, pageError: e);
    }
  }

  void _prefetch(int page) {
    final current = state;
    if (current == null) return;
    for (var next = page + 1; next <= page + 2 && next <= current.pageCount; next++) {
      final key = '${current.chapter.id}:$next';
      if (!_prefetched.add(key)) continue;
      final config = current.pageConfigs[next - 1];
      unawaited(
        ref
            .read(onlineImageLoaderProvider)
            .load(config, sourceId: current.sourceId, allowedHosts: current.sourceHosts)
            .catchError((_) {
              _prefetched.remove(key);
              return Uint8List(0);
            }),
      );
    }
  }

  void goToPage(int page) {
    final current = state;
    if (current == null || current.pageCount <= 0) return;
    final next = page.clamp(1, current.pageCount);
    if (next == current.page) return;
    _loadPage(next);
  }

  void nextPage() => goToPage((state?.page ?? 1) + 1);

  void previousPage() => goToPage((state?.page ?? 1) - 1);

  void retryPage() {
    final current = state;
    if (current == null) return;
    // 同一页的失败演示只触发一次：重试不再复现 403。
    _loadPage(current.page);
  }

  void toggleControls() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(controlsVisible: !current.controlsVisible);
  }

  void setControlsVisible(bool visible) {
    final current = state;
    if (current == null || current.controlsVisible == visible) return;
    state = current.copyWith(controlsVisible: visible);
  }

  /// 源语言配置变化时同步；关闭翻译时回到原图，避免旧的译文覆盖继续生效。
  void setTranslationEnabled(bool enabled) {
    final current = state;
    if (current == null || current.translationEnabled == enabled) return;
    state = current.copyWith(translationEnabled: enabled, showOriginal: enabled ? current.showOriginal : true);
  }

  void setShowOriginal(bool original) {
    final current = state;
    if (current == null) return;
    if (!original && !current.canToggleTranslated) return;
    state = current.copyWith(showOriginal: original);
  }

  void setRange(TranslationRange range) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(range: range);
  }

  void setRetranslate(bool value) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(retranslate: value);
  }

  /// 翻译本话：提交队列 → 逐页 running → done / failed / partial / unavailable。
  Future<void> startTranslation() async {
    final current = state;
    if (current == null ||
        current.translation.state == TranslationState.running ||
        current.translation.state == TranslationState.queued) {
      return;
    }
    final total = current.pageCount > 0 ? current.pageCount : 26;
    state = current.copyWith(
      translation: TranslationStatus(state: TranslationState.queued, total: total),
      showOriginal: true,
    );
    final gateway = ref.read(onlineTranslationGatewayProvider);
    if (!ref.read(onlineTranslationAvailableProvider)) {
      state = state!.copyWith(
        translation: TranslationStatus(state: TranslationState.unavailable, total: total),
      );
      return;
    }
    await _translationSub?.cancel();
    _translationSub = gateway
        .translate(
          sourceId: current.sourceId,
          comicId: current.comic.id,
          chapterId: current.chapter.id,
          total: total,
          fromCurrentPage: current.range == TranslationRange.fromCurrentPage,
        )
        .listen(
          (status) {
            final latest = state;
            if (latest == null) return;
            state = latest.copyWith(translation: status);
            if (status.state == TranslationState.done) {
              _translationTimer?.cancel();
              _translationSub?.cancel();
            }
          },
          onError: (Object error) {
            final latest = state;
            if (latest == null) return;
            final unavailable = error is OnlineException && error.message.contains('unavailable');
            state = latest.copyWith(
              translation: TranslationStatus(
                state: unavailable ? TranslationState.unavailable : TranslationState.failed,
                total: total,
                done: latest.translation.done,
                failed: total - latest.translation.done,
              ),
            );
          },
          cancelOnError: true,
        );
  }

  void retryTranslation() {
    final current = state;
    if (current == null) return;
    _translationSub?.cancel();
    state = current.copyWith(translation: const TranslationStatus(), showOriginal: true);
    startTranslation();
  }

  void onlyOriginal() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(showOriginal: true);
  }

  /// 完成翻译后跳页时，若用户选了译文但本页未完成，UI 自动回退原图。

  void _showOsd() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(osdVisible: true);
    _osdTimer?.cancel();
    _osdTimer = Timer(const Duration(milliseconds: 800), () {
      final latest = state;
      if (latest == null) return;
      state = latest.copyWith(osdVisible: false);
    });
  }

  void _commitProgress() {
    final current = state;
    if (current == null || current.pageCount <= 0) return;
    final progress = ReadingProgress(
      sourceId: current.sourceId,
      sourceName: current.sourceName,
      comicId: current.comic.id,
      comicTitle: current.comic.title,
      coverTone: current.comic.coverTone,
      chapterId: current.chapter.id,
      chapterTitle: current.chapter.title,
      page: current.page,
      pageCount: current.pageCount,
      updatedAt: DateTime.now(),
    );
    ref.read(onlineRecentProvider.notifier).record(progress);
    if (current.page >= current.pageCount) {
      ref
          .read(onlineReadChaptersProvider.notifier)
          .markRead(sourceId: current.sourceId, comicId: current.comic.id, chapterId: current.chapter.id);
    }
  }

  Future<void> close() async {
    _osdTimer?.cancel();
    _translationSub?.cancel();
    state = null;
  }
}
