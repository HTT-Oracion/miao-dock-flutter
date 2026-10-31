import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../core/utils/format.dart';
import '../controller/library_controller.dart';
import '../domain/lib_book.dart';

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
            child: shelfLoading(ref) ? const _ShelfCardSkeleton() : _ShelfList(books: books, selected: selected),
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
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(LucideIcons.bookOpen, size: 14, color: AppTokens.textSecondary),
          const SizedBox(width: 8),
          Text(
            AppLocalizations.of(context).shelfTitle,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
          ),
          const Spacer(),
          Text(
            AppLocalizations.of(context).shelfCount(count),
            style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
          ),
        ],
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
      height: 40,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Icon(LucideIcons.search, size: 13, color: AppTokens.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: (v) => ref.read(shelfQueryProvider.notifier).set(v),
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).shelfSearchHint,
                hintStyle: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (query.isNotEmpty)
            GestureDetector(
              onTap: () => ref.read(shelfQueryProvider.notifier).set(''),
              child: const Icon(LucideIcons.x, size: 13, color: AppTokens.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _ShelfList extends ConsumerWidget {
  const _ShelfList({required this.books, required this.selected});

  final List<LibBook> books;
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (books.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).shelfNoMatch,
          style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      itemCount: books.length,
      itemExtent: 56,
      itemBuilder: (context, i) => _BookRow(
        book: books[i],
        active: books[i].key == selected,
        onTap: () => ref.read(selectedBookProvider.notifier).select(books[i].key),
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.book, required this.active, required this.onTap});

  final LibBook book;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final index = book.key.hashCode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? AppTokens.navActive : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                _CoverThumb(seed: index),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppLocalizations.of(context).shelfBookMeta(
                          book.hasAuthor ? book.author : AppLocalizations.of(context).bookUnnamedAuthor,
                          book.chapterCount,
                          book.pageCount,
                        ),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 13, color: active ? AppTokens.accent : AppTokens.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 封面占位（封面图随服务端点落地；以 key 稳定取色）。
class _CoverThumb extends StatelessWidget {
  const _CoverThumb({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    const palette = [Color(0xFF3E4956), Color(0xFF4A4438), Color(0xFF3B4A42), Color(0xFF463B4A)];
    return Container(
      width: 40,
      height: 44,
      decoration: BoxDecoration(color: palette[seed.abs() % palette.length], borderRadius: BorderRadius.circular(6)),
    );
  }
}

class _ShelfFoot extends StatelessWidget {
  const _ShelfFoot({required this.books});

  final List<LibBook> books;

  @override
  Widget build(BuildContext context) {
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
          GestureDetector(
            onTap: () => context.go('/manga/drop'),
            child: Text(
              AppLocalizations.of(context).shelfGoDrop,
              style: TextStyle(fontSize: 11.5, color: AppTokens.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片式骨架：每张卡 = 封面块 + 两行文字占位。
class _ShelfCardSkeleton extends StatelessWidget {
  const _ShelfCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: palette.hi, borderRadius: BorderRadius.circular(4)),
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      children: [
        for (var i = 0; i < 6; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.panel,
              border: Border.all(color: palette.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 46,
                  decoration: BoxDecoration(color: palette.hi, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [bar(120, 10), const SizedBox(height: 8), bar(72, 8)],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
