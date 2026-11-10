import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/fallback_categories.dart';
import '../data/online_repository.dart';
import '../domain/online_error.dart';
import '../domain/online_models.dart';
import '../domain/online_source.dart';
import 'online_sources_controller.dart';

/// 在线视图的四个二级入口（设计稿侧栏「浏览」）。
enum OnlineView { discover, categories, ranking, recent, downloads }

class OnlineNavState {
  const OnlineNavState({
    this.view = OnlineView.discover,
    this.categoryId = 'hotblood',
    this.searchInput = '',
    this.query = '',
  });

  final OnlineView view;
  final String categoryId;
  final String searchInput;

  /// 已提交的搜索词；非空时主区显示搜索结果。
  final String query;

  OnlineNavState copyWith({
    OnlineView? view,
    String? categoryId,
    String? searchInput,
    String? query,
    bool clearQuery = false,
  }) => OnlineNavState(
    view: view ?? this.view,
    categoryId: categoryId ?? this.categoryId,
    searchInput: searchInput ?? this.searchInput,
    query: clearQuery ? '' : (query ?? this.query),
  );
}

final onlineNavProvider = NotifierProvider<OnlineNavNotifier, OnlineNavState>(OnlineNavNotifier.new);

class OnlineNavNotifier extends Notifier<OnlineNavState> {
  Timer? _debounce;

  @override
  OnlineNavState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const OnlineNavState();
  }

  void selectView(OnlineView view) {
    _debounce?.cancel();
    state = state.copyWith(view: view, searchInput: '', clearQuery: true);
  }

  void selectCategory(String id) => state = state.copyWith(categoryId: id, view: OnlineView.categories);

  void setSearchInput(String value) {
    final capped = value.length > 60 ? value.substring(0, 60) : value;
    state = state.copyWith(searchInput: capped);
    _debounce?.cancel();
    final trimmed = capped.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(clearQuery: true);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (state.searchInput.trim() == trimmed) {
        state = state.copyWith(query: trimmed);
      }
    });
  }

  void submitSearch([String? value]) {
    _debounce?.cancel();
    final trimmed = (value ?? state.searchInput).trim();
    state = state.copyWith(searchInput: trimmed, query: trimmed);
  }

  void clearSearch() {
    _debounce?.cancel();
    state = state.copyWith(searchInput: '', clearQuery: true);
  }
}

/// 当前源 id（只暴露 id，避免源对象字段变化引发无意义的重新取数）。
final activeOnlineSourceIdProvider = Provider<String?>(
  (ref) => ref.watch(activeOnlineSourceProvider.select((source) => source?.id)),
);

/// 当前源对象（读最新状态，不订阅全部字段）。
OnlineSource? _activeSource(Ref ref) {
  final id = ref.watch(activeOnlineSourceIdProvider);
  if (id == null) return null;
  final sources = ref.read(onlineSourcesProvider).value;
  if (sources == null) return null;
  for (final source in sources) {
    if (source.id == id) return source;
  }
  return null;
}

// ── 首页 ────────────────────────────────────────────────────────────────

class FeedBrowseState {
  const FeedBrowseState({required this.feed, this.loadingMore = false, this.loadMoreError});

  final HomeFeed feed;
  final bool loadingMore;
  final Object? loadMoreError;

  FeedBrowseState copyWith({HomeFeed? feed, bool? loadingMore, Object? loadMoreError, bool clearError = false}) =>
      FeedBrowseState(
        feed: feed ?? this.feed,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
      );
}

final onlineFeedProvider = AsyncNotifierProvider<OnlineFeedNotifier, FeedBrowseState>(
  OnlineFeedNotifier.new,
  retry: (_, _) => null,
);

class OnlineFeedNotifier extends AsyncNotifier<FeedBrowseState> {
  @override
  Future<FeedBrowseState> build() async {
    final source = _activeSource(ref);
    if (source == null) return FeedBrowseState(feed: const HomeFeed(sections: []));
    try {
      final page = await ref.read(onlineRepositoryProvider).explore(source, 1);
      ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
      return FeedBrowseState(feed: page);
    } catch (_) {
      ref.read(onlineSourcesProvider.notifier).markFailure(source.id);
      rethrow;
    }
  }

  Future<void> refresh() async {
    final source = _activeSource(ref);
    if (source == null) {
      state = AsyncData(FeedBrowseState(feed: const HomeFeed(sections: [])));
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        final page = await ref.read(onlineRepositoryProvider).explore(source, 1);
        ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
        return FeedBrowseState(feed: page);
      } catch (_) {
        ref.read(onlineSourcesProvider.notifier).markFailure(source.id);
        rethrow;
      }
    });
  }

  Future<void> loadMore() async {
    final current = state.value;
    final source = _activeSource(ref);
    if (current == null || source == null || current.loadingMore || !current.feed.hasMore) return;
    final nextPage = current.feed.page + 1;
    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    try {
      final next = await ref.read(onlineRepositoryProvider).explore(source, nextPage);
      ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
      state = AsyncData(FeedBrowseState(feed: current.feed.append(next)));
    } catch (e) {
      ref.read(onlineSourcesProvider.notifier).markFailure(source.id);
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: e));
    }
  }
}

// ── 分类 ────────────────────────────────────────────────────────────────

final onlineCategoriesProvider = AsyncNotifierProvider<OnlineCategoriesNotifier, List<CategoryGroup>>(
  OnlineCategoriesNotifier.new,
  retry: (_, _) => null,
);

class OnlineCategoriesNotifier extends AsyncNotifier<List<CategoryGroup>> {
  @override
  Future<List<CategoryGroup>> build() async {
    final source = _activeSource(ref);
    if (source == null) return const [];
    try {
      final groups = await ref.read(onlineRepositoryProvider).categories(source);
      ref.read(onlineCategoriesFallbackProvider.notifier).set(false);
      ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
      return groups;
    } catch (_) {
      // 分类结构解析失败时用常用题材兜底，并让 UI 显示「可能不完整」提示条。
      ref.read(onlineCategoriesFallbackProvider.notifier).set(true);
      ref.read(onlineSourcesProvider.notifier).markFailure(source.id);
      return fallbackCategoryGroups;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

class CategoryBrowseState {
  const CategoryBrowseState({required this.page, this.loadingMore = false, this.loadMoreError});

  final PagedComics page;
  final bool loadingMore;
  final Object? loadMoreError;

  CategoryBrowseState copyWith({
    PagedComics? page,
    bool? loadingMore,
    Object? loadMoreError,
    bool clearError = false,
  }) => CategoryBrowseState(
    page: page ?? this.page,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
  );
}

final onlineCategoryResultsProvider = AsyncNotifierProvider<OnlineCategoryResultsNotifier, CategoryBrowseState>(
  OnlineCategoryResultsNotifier.new,
  retry: (_, _) => null,
);

class OnlineCategoryResultsNotifier extends AsyncNotifier<CategoryBrowseState> {
  @override
  Future<CategoryBrowseState> build() async {
    final source = _activeSource(ref);
    final category = ref.watch(onlineNavProvider.select((nav) => nav.categoryId));
    if (source == null) return CategoryBrowseState(page: PagedComics(items: const [], page: 1, hasMore: false));
    try {
      final page = await ref.read(onlineRepositoryProvider).category(source, category, 1);
      ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
      return CategoryBrowseState(page: page);
    } catch (_) {
      ref.read(onlineSourcesProvider.notifier).markFailure(source.id);
      rethrow;
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    final source = _activeSource(ref);
    final category = ref.read(onlineNavProvider).categoryId;
    if (current == null || source == null || current.loadingMore || !current.page.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    try {
      final next = await ref.read(onlineRepositoryProvider).category(source, category, current.page.page + 1);
      ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
      state = AsyncData(CategoryBrowseState(page: current.page.append(next)));
    } catch (e) {
      ref.read(onlineSourcesProvider.notifier).markFailure(source.id);
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: e));
    }
  }
}

// ── 搜索 ────────────────────────────────────────────────────────────────

class SearchBrowseState {
  const SearchBrowseState({required this.page, this.loadingMore = false, this.loadMoreError});

  final PagedComics page;
  final bool loadingMore;
  final Object? loadMoreError;

  SearchBrowseState copyWith({PagedComics? page, bool? loadingMore, Object? loadMoreError, bool clearError = false}) =>
      SearchBrowseState(
        page: page ?? this.page,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
      );
}

final onlineSearchProvider = AsyncNotifierProvider<OnlineSearchNotifier, SearchBrowseState?>(
  OnlineSearchNotifier.new,
  retry: (_, _) => null,
);

class OnlineSearchNotifier extends AsyncNotifier<SearchBrowseState?> {
  @override
  Future<SearchBrowseState?> build() async {
    final query = ref.watch(onlineNavProvider.select((nav) => nav.query)).trim();
    final source = _activeSource(ref);
    if (query.isEmpty || source == null) return null;
    try {
      final page = await ref.read(onlineRepositoryProvider).search(source, query, 1);
      ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
      return SearchBrowseState(page: page);
    } catch (_) {
      ref.read(onlineSourcesProvider.notifier).markFailure(source.id);
      rethrow;
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    final source = _activeSource(ref);
    final query = ref.read(onlineNavProvider).query.trim();
    if (current == null || source == null || current.loadingMore || !current.page.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    try {
      final next = await ref.read(onlineRepositoryProvider).search(source, query, current.page.page + 1);
      ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
      state = AsyncData(SearchBrowseState(page: current.page.append(next)));
    } catch (e) {
      ref.read(onlineSourcesProvider.notifier).markFailure(source.id);
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: e));
    }
  }
}

/// 错误对象 → 错误码（UI 用 ARB 映射，不展示原始异常）。
OnlineErrorCode errorCodeOf(Object? error) {
  if (error is OnlineException) return error.code;
  return OnlineErrorCode.crashed;
}

String errorWireName(Object? error) => errorCodeOf(error).wireName;

// ── 排行 ────────────────────────────────────────────────────────────────

/// 排行 tabs 与具体列表分开加载：tabs 先显示，列表区域再显示骨架/错误。
final onlineRankTabsProvider = AsyncNotifierProvider<OnlineRankTabsNotifier, List<RankTab>>(
  OnlineRankTabsNotifier.new,
  retry: (_, _) => null,
);

class OnlineRankTabsNotifier extends AsyncNotifier<List<RankTab>> {
  @override
  Future<List<RankTab>> build() async {
    final source = _activeSource(ref);
    if (source == null || !source.hasRank) return const [];
    try {
      final tabs = await ref.read(onlineRepositoryProvider).rankTabs(source);
      ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
      return tabs;
    } catch (_) {
      ref.read(onlineSourcesProvider.notifier).markFailure(source.id);
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final onlineRankTabProvider = NotifierProvider<OnlineRankTabNotifier, String?>(OnlineRankTabNotifier.new);

class OnlineRankTabNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) => state = id;
}

class RankBrowseState {
  const RankBrowseState({
    required this.tabs,
    required this.selected,
    required this.page,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<RankTab> tabs;
  final String selected;
  final PagedComics page;
  final bool loadingMore;
  final Object? loadMoreError;

  RankBrowseState copyWith({
    List<RankTab>? tabs,
    String? selected,
    PagedComics? page,
    bool? loadingMore,
    Object? loadMoreError,
    bool clearError = false,
  }) => RankBrowseState(
    tabs: tabs ?? this.tabs,
    selected: selected ?? this.selected,
    page: page ?? this.page,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
  );
}

final onlineRankProvider = AsyncNotifierProvider<OnlineRankNotifier, RankBrowseState>(
  OnlineRankNotifier.new,
  retry: (_, _) => null,
);

class OnlineRankNotifier extends AsyncNotifier<RankBrowseState> {
  static const _emptyPage = PagedComics(items: [], page: 1, hasMore: false);

  static RankBrowseState _empty() => const RankBrowseState(tabs: [], selected: '', page: _emptyPage);

  @override
  Future<RankBrowseState> build() async {
    final source = _activeSource(ref);
    if (source == null || !source.hasRank) return _empty();
    final tabs = await ref.watch(onlineRankTabsProvider.future);
    if (tabs.isEmpty) return _empty().copyWith(tabs: tabs);
    final wanted = ref.watch(onlineRankTabProvider);
    final selected = wanted != null && tabs.any((tab) => tab.id == wanted) ? wanted : tabs.first.id;
    try {
      final page = await ref.read(onlineRepositoryProvider).rank(source, selected, 1);
      ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
      return RankBrowseState(tabs: tabs, selected: selected, page: page);
    } catch (_) {
      ref.read(onlineSourcesProvider.notifier).markFailure(source.id);
      rethrow;
    }
  }

  void selectTab(String id) => ref.read(onlineRankTabProvider.notifier).select(id);

  void refresh() {
    if (ref.read(onlineRankTabsProvider).hasError) ref.invalidate(onlineRankTabsProvider);
    ref.invalidateSelf();
  }

  Future<void> loadMore() async {
    final current = state.value;
    final source = _activeSource(ref);
    if (current == null || source == null || current.loadingMore || !current.page.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    try {
      final next = await ref.read(onlineRepositoryProvider).rank(source, current.selected, current.page.page + 1);
      ref.read(onlineSourcesProvider.notifier).markSuccess(source.id);
      state = AsyncData(current.copyWith(page: current.page.append(next), loadingMore: false));
    } catch (e) {
      ref.read(onlineSourcesProvider.notifier).markFailure(source.id);
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: e));
    }
  }
}
