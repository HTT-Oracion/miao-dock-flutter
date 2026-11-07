import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol/protocol.dart' show fuzzyMatch;

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/buttons.dart' show kPillRadius;
import '../../../shared/widgets/error_state.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';
import '../domain/lib_book.dart';
import 'shelf_menu.dart';

/// 窄屏漫画库（设计稿 `.mlib`）：分段（全部/单本/单话，带计数）+ 常驻搜索
/// + 网格（单本 = 渐变底书名首字；未归并单话 = 第 1 页封面 + 虚线橙框 + 角标）。
///
/// 点卡片 → [LibraryScreen] 用 `.mdetail` 从右侧滑入详情；这里只负责陈列。
class LibraryGrid extends ConsumerStatefulWidget {
  const LibraryGrid({super.key});

  @override
  ConsumerState<LibraryGrid> createState() => _LibraryGridState();
}

class _LibraryGridState extends ConsumerState<LibraryGrid> {
  /// 分段：all / book / single（设计稿 `mSeg`）。
  String _segment = 'all';

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(libraryProvider);
    final books = state.value ?? ref.read(libraryProvider.notifier).lastGood;
    final query = ref.watch(shelfQueryProvider).trim();

    if (books.isEmpty && state.hasError) {
      return ErrorState(error: state.error, onRetry: () => ref.read(libraryProvider.notifier).refresh());
    }

    final pool = switch (_segment) {
      'book' => books.where((b) => b.isBook),
      'single' => books.where((b) => !b.isBook),
      _ => books,
    };
    final shown = query.isEmpty
        ? pool.toList()
        : pool.where((b) => fuzzyMatch(b.name, query) || fuzzyMatch(b.author, query)).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `.mseg`：card 底 + line2 描边 + 8 圆角；选中 = accent 底。
          Container(
            key: const ValueKey('lib-mseg'),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.line2),
            ),
            child: Row(
              children: [
                for (final (key, label, count) in [
                  ('all', l10n.libSegAll, books.length),
                  ('book', l10n.libSegBook, books.where((b) => b.isBook).length),
                  ('single', l10n.libSegChapter, books.where((b) => !b.isBook).length),
                ])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _segment = key),
                      child: Container(
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _segment == key ? palette.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$label $count',
                          style: TextStyle(
                            fontSize: AppFont.px10_5,
                            fontWeight: _segment == key ? FontWeight.w600 : FontWeight.w400,
                            color: _segment == key ? palette.onAcc : palette.ink2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AppInput(
            hint: l10n.shelfSearchHint,
            height: 30,
            fontSize: AppFont.px11,
            onChanged: (v) => ref.read(shelfQueryProvider.notifier).set(v),
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  books.isEmpty ? l10n.shelfEmpty : l10n.libSegEmpty,
                  style: TextStyle(fontSize: AppFont.px12, color: palette.mut),
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  // 设计稿 `.mlib-grid` = minmax(96px,1fr)：390 宽下 3 列（每列 ~115）。
                  // maxExtent 取 122 ⇒ ceil(366/132)=3；取 110 会算出 4 列（实测）。
                  maxCrossAxisExtent: 122,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  // 3:4.1 封面 + 名字 + 副标（实测 0.56 以下才不溢出）。
                  childAspectRatio: 0.56,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) => _MobileCard(key: ValueKey('grid-card-${shown[i].key}'), book: shown[i]),
              ),
            ),
        ],
      ),
    );
  }
}

/// `.mlib-card`：封面 3:4.1 / 8 圆角 / 1px `line` 框；
/// 单话 = 第 1 页封面 + 1.5px 虚线橙框 + `单话`（左上）+ `归并`（右下）。
class _MobileCard extends ConsumerStatefulWidget {
  const _MobileCard({super.key, required this.book});

  final LibBook book;

  @override
  ConsumerState<_MobileCard> createState() => _MobileCardState();
}

class _MobileCardState extends ConsumerState<_MobileCard> {
  // 🔴 封面 provider 缓存在 state：每次 build 新建 MemoryImage 会重新解码 → 闪烁。
  MemoryImage? _cover;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  void _loadCover() {
    // 🔴 A 级替身的取图方法会**同步 throw**（不是失败 Future），必须 try/catch。
    try {
      ref
          .read(mangaSvcClientProvider)
          .getBookCover(widget.book.key)
          .then((v) {
            if (!mounted) return;
            if (v != null && v.isNotEmpty) {
              setState(() {
                _cover = MemoryImage(Uint8List.fromList(v));
                _loaded = true;
              });
              return;
            }
            _loadFirstPageFallback();
          })
          .catchError((_) => _loadFirstPageFallback());
    } catch (_) {
      _loadFirstPageFallback();
    }
  }

  /// 🔴 单话卡片默认以第一页作封面（服务端 `/cover` 已回退，这里再兜客户端侧）。
  void _loadFirstPageFallback() {
    if (widget.book.isBook) {
      setState(() => _loaded = true);
      return;
    }
    try {
      ref
          .read(mangaSvcClientProvider)
          .getBookFile(widget.book.key, 1)
          .then((v) {
            if (!mounted) return;
            setState(() {
              _cover = v.isEmpty ? null : MemoryImage(Uint8List.fromList(v));
              _loaded = true;
            });
          })
          .catchError((_) {
            if (!mounted) return;
            setState(() => _loaded = true);
          });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final b = widget.book;
    final single = !b.isBook;

    return GestureDetector(
      onTap: () => ref.read(selectedBookProvider.notifier).select(b.key),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4.1,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: palette.cardCover,
                borderRadius: BorderRadius.circular(8),
                border: single
                    ? Border.all(color: palette.accent.withValues(alpha: 0.55), width: 1.5)
                    : Border.all(color: palette.line),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_cover != null)
                    Image(image: _cover!, fit: BoxFit.cover)
                  else if (_loaded)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [palette.cardCover, palette.bg],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          b.name.isEmpty ? '' : b.name.characters.first,
                          style: TextStyle(fontSize: AppFont.px19, fontWeight: FontWeight.w800, color: palette.ink2),
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  if (single) ...[
                    // `单话` 角标（左上）：8 号、accent 底、onAcc 字。
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: palette.accent.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(kPillRadius),
                        ),
                        child: Text(
                          l10n.libSegChapter,
                          style: TextStyle(fontSize: AppFont.px8, fontWeight: FontWeight.w700, color: palette.onAcc),
                        ),
                      ),
                    ),
                    // `归并` 快捷入口（右下）：点它不进详情。
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: GestureDetector(
                        onTap: () => showMergeDialog(context, src: b.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: palette.accent.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(kPillRadius),
                          ),
                          child: Text(
                            l10n.libMerge,
                            style: TextStyle(
                              fontSize: AppFont.px8_5,
                              fontWeight: FontWeight.w700,
                              color: palette.onAcc,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            b.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppFont.px10_5, color: palette.ink),
          ),
          Text(
            single
                ? l10n.libSingleMobileSub(b.pageCount)
                : l10n.shelfBookMeta(b.hasAuthor ? b.author : l10n.bookUnnamedAuthor, b.chapterCount, b.pageCount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppFont.px8_5, color: palette.mut),
          ),
        ],
      ),
    );
  }
}
