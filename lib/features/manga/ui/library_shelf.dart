import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/skeleton.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';
import '../domain/lib_book.dart';
import 'hidden_books_dialog.dart';
import 'shelf_menu.dart';

/// 书架左栏（设计稿 `.shelf`）：250 宽、panel 底、右侧一条 `line` 分隔。
///
/// 结构 = 头（`我的书架` + `N 部`）→ 搜索 → 列表（单本平铺 + `其他 · 未归并` 分组）
/// → 脚注（已用容量 / 未归并 N / 已隐藏 N）。
class LibraryShelf extends ConsumerWidget {
  const LibraryShelf({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = shelfBooks(ref);
    final query = ref.watch(shelfQueryProvider);
    final hasError = shelfHasError(ref);

    return Container(
      width: 250,
      color: AppPalette.of(context).panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShelfHead(count: books.where((b) => b.isBook).length),
          // 失败但有旧数据：横幅 + 旧书架并存。
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
          Expanded(child: shelfLoading(ref) ? const SkeletonCards() : _ShelfBody(books: books)),
          _ShelfFoot(books: ref.watch(libraryProvider).value ?? const <LibBook>[]),
        ],
      ),
    );
  }
}

/// `.shelf-head`：14/16/8 内距、12.5 号 700、书图标主色，右侧 `N 部` 10 号 mut。
class _ShelfHead extends StatelessWidget {
  const _ShelfHead({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Icon(LucideIcons.book, size: 15, color: palette.accent),
          const SizedBox(width: 8),
          Text(
            l10n.shelfTitle,
            style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.ink),
          ),
          const Spacer(),
          Text(
            l10n.shelfCount(count),
            style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
          ),
        ],
      ),
    );
  }
}

/// `.shelf-search`：高 30、card 底、line2 描边、8 圆角、左右 12 外边距。
class _ShelfSearch extends ConsumerWidget {
  const _ShelfSearch({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      // 设计稿搜索图标在**右侧**（`.shelf-search svg{position:absolute;right:8px}`）。
      child: AppInput(
        hint: AppLocalizations.of(context).shelfSearchHint,
        height: 30,
        fontSize: AppFont.px11,
        suffix: Icon(LucideIcons.search, size: 14, color: AppPalette.of(context).mut),
        onChanged: (v) => ref.read(shelfQueryProvider.notifier).set(v),
      ),
    );
  }
}

/// 书架主体：单本平铺，未归并单话归入 `其他 · 未归并` 分组（带分隔线）。
class _ShelfBody extends ConsumerWidget {
  const _ShelfBody({required this.books});

  final List<LibBook> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(selectedBookProvider);

    if (books.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.shelfNoMatch,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
          ),
        ),
      );
    }

    final merged = books.where((b) => b.isBook).toList();
    final unmerged = books.where((b) => !b.isBook).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: [
        for (final b in merged) _ShelfRow(book: b, active: b.key == selected),
        if (unmerged.isNotEmpty) ...[
          _ShelfGroupTitle(text: l10n.shelfGroupUnmerged),
          for (final b in unmerged) _ShelfRow(book: b, active: b.key == selected),
        ],
      ],
    );
  }
}

/// `.shelf-group`：9 号 / 2px 字距 / warn 色 / 右侧一条 `line` 分隔线延伸到底。
class _ShelfGroupTitle extends StatelessWidget {
  const _ShelfGroupTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(fontSize: AppFont.px9, fontWeight: FontWeight.w700, letterSpacing: 2, color: palette.warn),
          ),
          const SizedBox(width: 6),
          Expanded(child: Container(height: 1, color: palette.line)),
        ],
      ),
    );
  }
}

/// `.srow`：7/8 内距、10 圆角、gap 10；38×50 封面 + 两行文字 + hover 出现的 ⋯。
///
/// 选中 = `accSoft` 底；hover = `card` 底；单话封面 1.5px 虚线橙框。
class _ShelfRow extends ConsumerStatefulWidget {
  const _ShelfRow({required this.book, required this.active});

  final LibBook book;
  final bool active;

  @override
  ConsumerState<_ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends ConsumerState<_ShelfRow> {
  bool _hover = false;
  MemoryImage? _cover;

  @override
  void initState() {
    super.initState();
    // 封面缓存进 state：每次 build 新建 MemoryImage 会重新解码 → 闪烁。
    ref
        .read(mangaSvcClientProvider)
        .getBookCover(widget.book.key)
        .then((v) {
          if (!mounted || v == null || v.isEmpty) return;
          setState(() => _cover = MemoryImage(Uint8List.fromList(v)));
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final book = widget.book;
    final active = widget.active;
    // 选中优先于 hover（设计稿 `.srow.on{background:var(--acc-soft)}`）。
    final bg = active ? palette.accSoft : (_hover ? palette.card : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => ref.read(selectedBookProvider.notifier).select(book.key),
        onSecondaryTapDown: (d) => ShelfContextMenu.show(context, ref, book, d.globalPosition),
        child: Container(
          key: ValueKey('shelf-row-${book.key}'),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              _ShelfCover(book: book, image: _cover),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      book.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px11_5, fontWeight: FontWeight.w600, color: palette.ink),
                    ),
                    Text(
                      // 浏览态副标：`作者 · N 话 · N 页`；单话：`单话 · 未归并 · N 页`。
                      book.isBook
                          ? l10n.shelfBookMeta(
                              book.hasAuthor ? book.author : l10n.bookUnnamedAuthor,
                              book.chapterCount,
                              book.pageCount,
                            )
                          : l10n.libSingleRowMeta(book.pageCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                    ),
                  ],
                ),
              ),
              // ⋯ 只在 hover 时出现（设计稿 `.srow .more{opacity:0}`）。
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _hover ? 1 : 0,
                child: _ShelfMoreButton(book: book),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.srow .scov`：38×50 / 7 圆角 / 渐变底 + 书名首字；
/// 单话 = 第一页封面 + 1.5px 虚线橙框（与单本区分）。
class _ShelfCover extends StatelessWidget {
  const _ShelfCover({required this.book, required this.image});

  final LibBook book;
  final MemoryImage? image;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: ValueKey('shelf-cov-${book.key}'),
      width: 38,
      height: 50,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.cardCover,
        borderRadius: BorderRadius.circular(7),
        border: book.isBook ? null : Border.all(color: palette.accent.withValues(alpha: 0.55), width: 1.5),
      ),
      child: image != null
          ? Image(image: image!, fit: BoxFit.cover)
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [palette.cardCover, palette.bg],
                ),
              ),
              child: Center(
                child: Text(
                  book.name.isEmpty ? '' : book.name.characters.first,
                  style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink2),
                ),
              ),
            ),
    );
  }
}

/// 书架行尾「⋯」：与右键是同一份菜单（设计稿注释：行尾 ⋯ 与右键同源）。
class _ShelfMoreButton extends ConsumerWidget {
  const _ShelfMoreButton({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Builder(
      builder: (ctx) => GestureDetector(
        onTapUp: (d) {
          final box = ctx.findRenderObject() as RenderBox;
          ShelfContextMenu.show(ctx, ref, book, box.localToGlobal(d.localPosition));
        },
        child: SizedBox(width: 24, height: 24, child: Icon(LucideIcons.ellipsis, size: 13, color: palette.mut)),
      ),
    );
  }
}

/// `.shelf-foot`：10/16 内距、`line` 顶线、10 号字；
/// 左 = 已用容量（mut），右 = `未归并 N` / `已隐藏 N`（主色可点）。
class _ShelfFoot extends ConsumerWidget {
  const _ShelfFoot({required this.books});

  final List<LibBook> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final unmergedCount = books.where((b) => !b.isBook).length;
    final hidden = ref.watch(hiddenComicsProvider);
    final bytes = books.fold<int>(0, (s, b) => s + b.totalBytes);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: [
          Text(
            l10n.shelfUsedBytes(formatBytes(bytes)),
            style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
          ),
          const Spacer(),
          _FootLink(
            label: l10n.shelfUnmergedFilter(unmergedCount),
            // 设计稿 `showSingles()`：脚注入口 → 右栏「未归并单话」陈列页。
            onTap: () => ref.read(libSinglesViewProvider.notifier).toggle(),
            active: ref.watch(libSinglesViewProvider),
          ),
          const SizedBox(width: 8),
          // 「已隐藏 N」→ 已隐藏作品弹窗（设计稿 `openHidden()`）。
          _FootLink(
            label: l10n.shelfHiddenFilter(hidden.length),
            onTap: () => showHiddenBooksDialog(context, hidden),
            active: false,
          ),
        ],
      ),
    );
  }
}

class _FootLink extends StatefulWidget {
  const _FootLink({required this.label, required this.onTap, required this.active});

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_FootLink> createState() => _FootLinkState();
}

class _FootLinkState extends State<_FootLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = (widget.active || _hover) ? palette.accent : palette.mut;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: TextStyle(fontSize: AppFont.px10, color: color),
        ),
      ),
    );
  }
}
