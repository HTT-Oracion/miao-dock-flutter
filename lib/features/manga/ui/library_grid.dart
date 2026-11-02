import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:protocol/protocol.dart' show fuzzyMatch;

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/error_state.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';
import '../domain/lib_book.dart';
import 'library_detail.dart';

/// 漫画库首页：**全部漫画网格**（ver1.0 `.lib-grid` / `.bookcard`）。
///
/// 封面 3:4、左上角话数胶囊、标题 10.5、副标 9；hover 上浮 3px + 描边变主色。
class LibraryGrid extends ConsumerStatefulWidget {
  const LibraryGrid({super.key, this.mobile = false});

  /// 移动端形态：网格显示**全部（单本 + 未归并单话）**并带分段过滤与常驻搜索
  /// ——桌面「网格只显示单本」的分工在手机上会造成整页空白（库里没有书时）。
  final bool mobile;

  @override
  ConsumerState<LibraryGrid> createState() => _LibraryGridState();
}

class _LibraryGridState extends ConsumerState<LibraryGrid> {
  /// 分段：all / book / chapter（仅移动端）。
  String _segment = 'all';

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(libraryProvider);
    final books = state.value ?? ref.read(libraryProvider.notifier).lastGood;
    final query = ref.watch(shelfQueryProvider).trim();
    final mobile = widget.mobile;
    // 桌面：网格只显示单本（D-098 定案）；移动：显示全部并按分段过滤。
    final pool = mobile
        ? switch (_segment) {
            'book' => books.where((b) => b.isBook),
            'chapter' => books.where((b) => !b.isBook),
            _ => books,
          }
        : books.where((b) => b.isBook);
    final shown = query.isEmpty
        ? pool.toList()
        : pool.where((b) => fuzzyMatch(b.name, query) || fuzzyMatch(b.author, query)).toList();

    if (books.isEmpty && state.hasError) {
      return ErrorState(error: state.error, onRetry: () => ref.read(libraryProvider.notifier).refresh());
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, mobile ? 12 : 18, mobile ? 12 : 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行（ver1.0 `.lib-main` 头）：本地漫画库 + 计数 + 刷新 / 新建漫画。
          Row(
            children: [
              Text(
                l10n.libLocalLibrary,
                style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.textPrimary),
              ),
              const SizedBox(width: 8),
              Text(
                // 移动端计的是全部条目；桌面仍是单本口径（D-098 分工）。
                mobile
                    ? l10n.libItemCount(books.length, books.fold<int>(0, (a, b) => a + b.pageCount))
                    : '${books.where((b) => b.isBook).length} · '
                          '${books.where((b) => b.isBook).fold<int>(0, (a, b) => a + b.pageCount)}',
                style: TextStyle(fontSize: AppFont.px9_5, color: palette.textSecondary),
              ),
              const Spacer(),
              const LibraryHeaderActions(),
            ],
          ),
          if (mobile) ...[
            // 分段：全部 / 单本 / 单话（移动端专属；桌面分工不变）。
            Container(
              margin: const EdgeInsets.fromLTRB(0, 10, 0, 0),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: palette.panel, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  for (final (key, label, count) in [
                    ('all', l10n.libSegAll, books.length),
                    ('book', l10n.libSegBook, books.where((b) => b.isBook).length),
                    ('chapter', l10n.libSegChapter, books.where((b) => !b.isBook).length),
                  ])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _segment = key),
                        child: Container(
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _segment == key ? palette.card : Colors.transparent,
                            border: _segment == key
                                ? Border.all(color: palette.line2)
                                : Border.all(color: Colors.transparent),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$label $count',
                            style: TextStyle(
                              fontSize: AppFont.px10_5,
                              fontWeight: _segment == key ? FontWeight.w600 : FontWeight.w400,
                              color: _segment == key ? palette.textPrimary : palette.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 搜索常驻（桌面搜索在左栏，移动端没有左栏）。
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AppInput(
                hint: l10n.shelfSearchHint,
                height: 32,
                fontSize: AppFont.px11,
                prefixIcon: LucideIcons.search,
                prefixIconSize: 12,
                suffix: query.isNotEmpty
                    ? GestureDetector(
                        onTap: () => ref.read(shelfQueryProvider.notifier).set(''),
                        child: Icon(LucideIcons.x, size: 12, color: palette.textSecondary),
                      )
                    : null,
                onChanged: (v) => ref.read(shelfQueryProvider.notifier).set(v),
              ),
            ),
          ],
          if (shown.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  books.isEmpty ? l10n.shelfEmpty : (pool.isEmpty ? l10n.libSegEmpty : l10n.shelfNoMatch),
                  style: TextStyle(fontSize: AppFont.px12_5, color: palette.textSecondary),
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: mobile ? 150 : 170,
                  mainAxisSpacing: mobile ? 10 : 16,
                  crossAxisSpacing: mobile ? 10 : 16,
                  childAspectRatio: 0.62,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) => _BookCard(key: ValueKey('grid-card-${shown[i].key}'), book: shown[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _BookCard extends ConsumerStatefulWidget {
  const _BookCard({super.key, required this.book});

  final LibBook book;

  @override
  ConsumerState<_BookCard> createState() => _BookCardState();
}

class _BookCardState extends ConsumerState<_BookCard> {
  bool _hover = false;
  Future<List<int>?>? _cover;

  @override
  void initState() {
    super.initState();
    _cover = ref
        .read(mangaSvcClientProvider)
        .getBookCover(widget.book.key)
        .then<List<int>?>((v) => v)
        .catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final b = widget.book;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => ref.read(selectedBookProvider.notifier).select(b.key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 3 / 4,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _hover ? palette.accent : Colors.transparent),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [palette.accent, palette.coverEndDeep],
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FutureBuilder<List<int>?>(
                        future: _cover,
                        builder: (context, snap) {
                          final bytes = snap.data;
                          if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();
                          return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover);
                        },
                      ),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            b.isBook ? l10n.bookChapterCount(b.chapterCount) : l10n.libUnmerged,
                            style: const TextStyle(fontSize: AppFont.px9, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                b.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppFont.px10_5, fontWeight: FontWeight.w600, color: palette.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                b.isBook ? '${b.hasAuthor ? b.author : l10n.bookUnnamedAuthor} · ${b.pageCount}' : '${b.pageCount}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppFont.px9, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
