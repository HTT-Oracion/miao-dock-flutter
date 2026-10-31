import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol/protocol.dart';

import 'queue_controller.dart';

/// 漫画库书架。
final libraryProvider = AsyncNotifierProvider<LibraryNotifier, List<LibBook>>(LibraryNotifier.new);

class LibraryNotifier extends AsyncNotifier<List<LibBook>> {
  @override
  Future<List<LibBook>> build() => ref.watch(mangasvcClientProvider).listLibrary();
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
  final books = ref.watch(libraryProvider).value ?? const <LibBook>[];
  final query = ref.watch(shelfQueryProvider).trim();
  if (query.isEmpty) return books;
  return books.where((b) => b.name.contains(query) || b.author.contains(query)).toList();
}

/// 搜索分组（设计稿 G Row 4）：作品命中列全话，话号命中仅列命中话。
typedef SearchGroup = ({LibBook book, List<LibChapter> chapters});

List<SearchGroup> searchGroups(WidgetRef ref) {
  final query = ref.watch(shelfQueryProvider).trim();
  final books = ref.watch(libraryProvider).value ?? const <LibBook>[];
  if (query.isEmpty) return const <SearchGroup>[];
  final groups = <SearchGroup>[];
  for (final book in books) {
    final bookHit = book.name.contains(query) || book.author.contains(query);
    final chapterHits = book.chapters.where((c) => '第 ${c.no} 话'.contains(query)).toList();
    if (bookHit) {
      groups.add((book: book, chapters: book.chapters));
    } else if (chapterHits.isNotEmpty) {
      groups.add((book: book, chapters: chapterHits));
    }
  }
  return groups;
}
