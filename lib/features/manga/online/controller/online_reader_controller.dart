import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    required this.comic,
    required this.chapter,
    required this.chapters,
    required this.pageCount,
    this.page = 1,
    this.pageLoading = true,
    this.pageError,
    this.loadingPages = false,
    this.pagesError,
    this.translation = const TranslationStatus(),
    this.showOriginal = true,
    this.zoom = 1,
    this.controlsVisible = true,
    this.night = false,
    this.webtoon = false,
    this.brightness = 1,
    this.osdVisible = false,
    this.range = TranslationRange.chapter,
    this.retranslate = true,
  });

  final String sourceId;
  final String sourceName;
  final OnlineComic comic;
  final OnlineChapter chapter;
  final List<OnlineChapter> chapters;
  final int pageCount;
  final int page;
  final bool pageLoading;
  final Object? pageError;
  final bool loadingPages;
  final Object? pagesError;
  final TranslationStatus translation;
  final bool showOriginal;
  final double zoom;
  final bool controlsVisible;
  final bool night;
  final bool webtoon;
  final double brightness;
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
    int? pageCount,
    int? page,
    bool? pageLoading,
    Object? pageError,
    bool clearPageError = false,
    bool? loadingPages,
    Object? pagesError,
    bool clearPagesError = false,
    TranslationStatus? translation,
    bool? showOriginal,
    double? zoom,
    bool? controlsVisible,
    bool? night,
    bool? webtoon,
    double? brightness,
    bool? osdVisible,
    TranslationRange? range,
    bool? retranslate,
  }) => OnlineReaderState(
    sourceId: sourceId,
    sourceName: sourceName,
    comic: comic ?? this.comic,
    chapter: chapter ?? this.chapter,
    chapters: chapters ?? this.chapters,
    pageCount: pageCount ?? this.pageCount,
    page: page ?? this.page,
    pageLoading: pageLoading ?? this.pageLoading,
    pageError: clearPageError ? null : (pageError ?? this.pageError),
    loadingPages: loadingPages ?? this.loadingPages,
    pagesError: clearPagesError ? null : (pagesError ?? this.pagesError),
    translation: translation ?? this.translation,
    showOriginal: showOriginal ?? this.showOriginal,
    zoom: zoom ?? this.zoom,
    controlsVisible: controlsVisible ?? this.controlsVisible,
    night: night ?? this.night,
    webtoon: webtoon ?? this.webtoon,
    brightness: brightness ?? this.brightness,
    osdVisible: osdVisible ?? this.osdVisible,
    range: range ?? this.range,
    retranslate: retranslate ?? this.retranslate,
  );
}

final onlineReaderProvider = NotifierProvider<OnlineReaderNotifier, OnlineReaderState?>(OnlineReaderNotifier.new);

class OnlineReaderNotifier extends Notifier<OnlineReaderState?> {
  Timer? _pageTimer;
  Timer? _osdTimer;
  Timer? _translationTimer;
  StreamSubscription<TranslationStatus>? _translationSub;
  final Set<String> _failedOnce = {};
  final Set<String> _prefetched = {};

  @override
  OnlineReaderState? build() {
    ref.onDispose(() {
      _pageTimer?.cancel();
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
    _pageTimer?.cancel();
    final initialPage = (startPage ?? 1).clamp(1, 9999);
    state = OnlineReaderState(
      sourceId: source.id,
      sourceName: source.name,
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
      final page = startPage == null ? 1 : initialPage.clamp(1, count <= 0 ? 1 : count);
      state = state!.copyWith(
        pageCount: count,
        page: page,
        loadingPages: false,
        translation: state!.translation.copyWith(total: count),
      );
      _prefetch(page);
      _loadPage(page);
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
    _pageTimer?.cancel();
    _osdTimer?.cancel();
    state = current.copyWith(
      chapter: chapter,
      page: startPage ?? 1,
      pageLoading: true,
      clearPageError: true,
      translation: TranslationStatus(total: current.pageCount),
      showOriginal: true,
      controlsVisible: true,
    );
    _prefetch(startPage ?? 1);
    _loadPage(startPage ?? 1);
  }

  void _loadPage(int page) {
    final current = state;
    if (current == null) return;
    _pageTimer?.cancel();
    state = current.copyWith(page: page, pageLoading: true, clearPageError: true);
    _showOsd();
    _pageTimer = Timer(const Duration(milliseconds: 380), () {
      final latest = state;
      if (latest == null || latest.page != page) return;
      final failKey = '${latest.chapter.id}:$page';
      // 设计稿要展示「403 防盗链拒绝」的失败页；用第 13 页首次加载演示，
      // 重试后成功（自动换新签名）。
      if (page == 13 && _failedOnce.add(failKey)) {
        state = latest.copyWith(
          pageLoading: false,
          pageError: const OnlineException(OnlineErrorCode.blocked, '403 referer'),
        );
        return;
      }
      state = latest.copyWith(pageLoading: false);
      _prefetch(page);
      _commitProgress();
    });
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

  void setZoom(double zoom) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(zoom: zoom.clamp(0.75, 3));
  }

  void cycleZoom() {
    final current = state;
    if (current == null) return;
    const values = [1.0, 1.25, 1.5, 2.0];
    final index = values.indexOf(current.zoom);
    setZoom(values[(index + 1) % values.length]);
  }

  void setShowOriginal(bool original) {
    final current = state;
    if (current == null) return;
    if (!original && !current.canToggleTranslated) return;
    state = current.copyWith(showOriginal: original);
  }

  void toggleNight() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(night: !current.night);
  }

  void toggleWebtoon() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(webtoon: !current.webtoon);
  }

  void setBrightness(double value) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(brightness: value.clamp(0.25, 1));
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

  Future<void> _prefetch(int page) async {
    final current = state;
    if (current == null || current.pageCount <= 0) return;
    final source = _source(current.sourceId);
    if (source == null) return;
    for (var offset = -2; offset <= 2; offset++) {
      final target = page + offset;
      if (target < 1 || target > current.pageCount) continue;
      final key = '${current.chapter.id}:$target';
      if (!_prefetched.add(key)) continue;
      unawaited(
        ref
            .read(onlineRepositoryProvider)
            .imageConfig(
              source,
              'demo://${current.comic.id}/${current.chapter.id}/$target',
              current.comic.id,
              current.chapter.id,
            )
            .catchError((_) => const ImageLoadingConfig()),
      );
    }
  }

  OnlineSource? _source(String id) {
    final sources = ref.read(onlineSourcesProvider).value ?? const <OnlineSource>[];
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  Future<void> close() async {
    _pageTimer?.cancel();
    _osdTimer?.cancel();
    _translationSub?.cancel();
    state = null;
  }
}
