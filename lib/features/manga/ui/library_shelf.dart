import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/toast.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../core/utils/format.dart';
import '../controller/queue_controller.dart';
import '../controller/library_controller.dart';
import '../domain/lib_book.dart';
import 'shelf_menu.dart';

/// 书架左栏（设计稿 G Shelf，260 宽）：书架头 + 搜索 + 书架行 + 容量脚。
class LibraryShelf extends ConsumerWidget {
  const LibraryShelf({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = shelfBooks(ref);
    final allBooks = books;
    final selected = ref.watch(selectedBookProvider);
    final query = ref.watch(shelfQueryProvider);
    final hasError = shelfHasError(ref);

    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShelfHead(count: books.length),
          // 失败但有旧数据：横幅 + 旧书架并存（设计稿 §07）。
          if (hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ErrorBanner(
                error: shelfError(ref),
                onRetry: () => ref.read(libraryProvider.notifier).refresh(),
                showStaleHint: true,
              ),
            ),
          _ShelfSearch(query: query),
          Expanded(
            // 加载中显示**卡片骨架**（设计稿：书是卡片，不是表格行）。
            child: shelfLoading(ref) ? const SkeletonCards() : _ShelfBody(books: books, selected: selected),
          ),
          _ShelfFoot(books: allBooks),
        ],
      ),
    );
  }
}

class _ShelfHead extends StatelessWidget {
  const _ShelfHead({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // ver1.0 左栏只有一行 9.5 号计数文字（没有大标题）。
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Text(
        AppLocalizations.of(context).shelfCount(count),
        style: const TextStyle(fontSize: 9.5, color: AppTokens.textSecondary),
      ),
    );
  }
}

class _ShelfSearch extends ConsumerWidget {
  const _ShelfSearch({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 30,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Icon(LucideIcons.search, size: 12, color: AppTokens.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              onChanged: (v) => ref.read(shelfQueryProvider.notifier).set(v),
              style: const TextStyle(fontSize: 10, color: AppTokens.textPrimary),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).shelfSearchHint,
                hintStyle: const TextStyle(fontSize: 10, color: AppTokens.textSecondary),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (query.isNotEmpty)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => ref.read(shelfQueryProvider.notifier).set(''),
                child: const Icon(LucideIcons.x, size: 12, color: AppTokens.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// 书架主体：正常书目 +（开关打开时）已隐藏区。
class _ShelfBody extends ConsumerWidget {
  const _ShelfBody({required this.books, required this.selected});

  final List<LibBook> books;
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showHidden = ref.watch(showHiddenProvider);
    final hidden = ref.watch(hiddenComicsProvider);
    final l10n = AppLocalizations.of(context);

    if (books.isEmpty && (!showHidden || hidden.isEmpty)) {
      return Center(
        child: Text(l10n.shelfNoMatch, style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary)),
      );
    }

    // 搜索态：按「每本书一组 + 未归并组」分组（miao-dock `groupSearchResults`）；
    // 浏览态：平铺全部（单本 + 单话）。
    final searching = ref.watch(shelfQueryProvider).trim().isNotEmpty;
    final merged = books.where((b) => b.isBook).toList();
    final unmerged = books.where((b) => !b.isBook).toList();

    Widget rowFor(LibBook b) => _BookRow(
      key: ValueKey('shelf-row-${b.key}'),
      book: b,
      active: b.key == selected,
      onTap: () => ref.read(selectedBookProvider.notifier).select(b.key),
    );

    Widget groupTitle(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppTokens.textSecondary),
      ),
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      children: [
        if (searching) ...[
          for (final b in merged) ...[groupTitle(l10n.shelfGroupBook(b.name)), rowFor(b)],
          if (unmerged.isNotEmpty) ...[groupTitle(l10n.shelfGroupUnmerged), for (final b in unmerged) rowFor(b)],
        ] else
          for (final b in books) rowFor(b),
        if (showHidden && hidden.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            l10n.shelfHiddenSection,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTokens.textSecondary),
          ),
          const SizedBox(height: 4),
          for (final name in hidden)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(name, style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
                  ),
                  AppTextAction(
                    label: l10n.shelfRestore,
                    onTap: () async {
                      await ref.read(mangaSvcClientProvider).unhideBook(name);
                      await ref.read(libraryProvider.notifier).refresh();
                      if (context.mounted) {
                        showAppToast(context, l10n.shelfRestoredToast(name), tone: ToastTone.good);
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _BookRow extends ConsumerStatefulWidget {
  const _BookRow({super.key, required this.book, required this.active, required this.onTap});

  final LibBook book;
  final bool active;
  final VoidCallback onTap;

  @override
  ConsumerState<_BookRow> createState() => _BookRowState();
}

class _BookRowState extends ConsumerState<_BookRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final active = widget.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onSecondaryTapDown: (d) => ShelfContextMenu.show(context, ref, book, d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          // ver1.0 `.nav-item`：34 高、8 圆角；hover 变 card 底；
          // 选中 = card 底 + 1px 描边 + 主色图标。
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: (active || _hover) ? AppTokens.card : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: active ? AppTokens.divider : Colors.transparent),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onTap,
              child: Row(
                children: [
                  Icon(
                    book.isBook ? LucideIcons.bookText : LucideIcons.fileText,
                    size: 13,
                    color: active ? AppTokens.accent : AppTokens.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      book.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? AppTokens.textPrimary : AppTokens.textMuted,
                      ),
                    ),
                  ),
                  Text('${book.pageCount}', style: const TextStyle(fontSize: 9.5, color: AppTokens.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShelfFoot extends ConsumerWidget {
  const _ShelfFoot({required this.books});

  final List<LibBook> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = books.fold(0, (s, b) => s + b.totalBytes);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context).shelfUsedBytes(formatBytes(bytes)),
            style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
          ),
          const Spacer(),
          _TextLink(
            label: AppLocalizations.of(context).shelfGoDrop,
            color: AppTokens.accent,
            onTap: () => context.go('/manga/drop'),
          ),
          const SizedBox(width: 10),
          // 「显示已隐藏」开关（miao-dock：隐藏清单在服务端，这里只做开关）。
          _TextLink(
            label: AppLocalizations.of(context).shelfShowHidden,
            color: ref.watch(showHiddenProvider) ? AppTokens.accent : AppTokens.textSecondary,
            onTap: () => ref.read(showHiddenProvider.notifier).toggle(),
          ),
        ],
      ),
    );
  }
}

/// 文字链接（cursor 手型 + hover 提亮）。
class _TextLink extends StatefulWidget {
  const _TextLink({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_TextLink> createState() => _TextLinkState();
}

class _TextLinkState extends State<_TextLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: TextStyle(fontSize: 11.5, color: _hover ? AppTokens.textPrimary : widget.color),
        ),
      ),
    );
  }
}
