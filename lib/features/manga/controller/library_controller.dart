import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/contract_map.dart';
import '../domain/lib_book.dart';

import 'queue_controller.dart';

/// 漫画库书架。
final libraryProvider = AsyncNotifierProvider<LibraryNotifier, List<LibBook>>(LibraryNotifier.new);

class LibraryNotifier extends AsyncNotifier<List<LibBook>> {
  /// 最近一次成功拉取的书架。
  ///
  /// 设计稿 §07：「失败**不清空**已成功的数据（横幅 + 上次数据并存）」。
  /// 队列早就这么做了，书架之前没做 —— 服务一挂，书架整片变空，比报错更糟：
  /// 用户会以为书没了。
  List<LibBook> _lastGood = const [];

  /// 错误态时 UI 仍需展示的书架（可能为空 = 没成功过）。
  List<LibBook> get lastGood => _lastGood;

  @override
  Future<List<LibBook>> build() async {
    try {
      final response = await ref.watch(mangaSvcClientProvider).listLibrary();
      // 新服务端给 books；旧服务端只给 comics —— 后者无法还原「话」层级，按空书架处理。
      final books = response.books?.map(toLibBook).toList() ?? const <LibBook>[];
      _lastGood = books;
      return books;
    } catch (e, st) {
      // 保留 _lastGood，交给 UI 决定「横幅 + 旧数据」还是「整块错误态」。
      Error.throwWithStackTrace(e, st);
    }
  }

  /// 重试：切 loading 再拉一次。
  Future<void> refresh() async {
    state = const AsyncLoading<List<LibBook>>();
    state = await AsyncValue.guard(() async {
      final response = await ref.read(mangaSvcClientProvider).listLibrary();
      final books = response.books?.map(toLibBook).toList() ?? const <LibBook>[];
      _lastGood = books;
      return books;
    });
  }
}

/// 当前选中的作品 key；null = 未选中（详情区展示空态指引）。
final selectedBookProvider = NotifierProvider<SelectedBookNotifier, String?>(SelectedBookNotifier.new);

class SelectedBookNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? key) => state = key;
}

/// 书架搜索词（收窄书架用；防抖随交互打磨补）。
final shelfQueryProvider = NotifierProvider<ShelfQueryNotifier, String>(ShelfQueryNotifier.new);

class ShelfQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

/// 派生：按搜索词收窄的书架列表（取数判据：派生数据不进 build）。
List<LibBook> shelfBooks(WidgetRef ref) {
  final state = ref.watch(libraryProvider);
  // 失败时回落到上次成功的数据（设计稿 §07：不清空已成功的数据）。
  // 直接 `.value ?? []` 会让服务一挂书架整片变空，用户以为书没了。
  final books = state.value ?? ref.read(libraryProvider.notifier).lastGood;
  final query = ref.watch(shelfQueryProvider).trim();
  if (query.isEmpty) return books;
  return books.where((b) => b.name.contains(query) || b.author.contains(query)).toList();
}

/// 书架当前是否处于「失败但有旧数据」状态（UI 据此显示横幅）。
bool shelfHasError(WidgetRef ref) => ref.watch(libraryProvider).hasError;

/// 是否处于「首次加载中」（有旧数据时不算，避免书架闪成骨架）。
bool shelfLoading(WidgetRef ref) {
  final st = ref.watch(libraryProvider);
  return st.isLoading && st.value == null;
}

/// 书架错误对象（透传给 [ErrorBanner]）。
Object? shelfError(WidgetRef ref) => ref.watch(libraryProvider).error;

/// 搜索分组（设计稿 G Row 4）：作品命中列全话，话号命中仅列命中话。
typedef SearchGroup = ({LibBook book, List<LibChapter> chapters});

List<SearchGroup> searchGroups(WidgetRef ref) {
  final query = ref.watch(shelfQueryProvider).trim();
  final books = ref.watch(libraryProvider).value ?? const <LibBook>[];
  if (query.isEmpty) return const <SearchGroup>[];
  final groups = <SearchGroup>[];
  for (final book in books) {
    final bookHit = book.name.contains(query) || book.author.contains(query);
    // 话号匹配不拼中文文案：直接按数字比对，`3` / `第3话` / `第 3 话` 都能命中。
    final chapterHits = book.chapters.where((c) => '${c.no}'.contains(query) || query.contains('${c.no}')).toList();
    if (bookHit) {
      groups.add((book: book, chapters: book.chapters));
    } else if (chapterHits.isNotEmpty) {
      groups.add((book: book, chapters: chapterHits));
    }
  }
  return groups;
}
