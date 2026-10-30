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
