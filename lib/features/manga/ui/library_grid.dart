import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/error_state.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';
import '../domain/lib_book.dart';
import 'library_detail.dart';

/// 漫画库首页：**全部漫画网格**（ver1.0 `.lib-grid` / `.bookcard`）。
///
/// 封面 3:4、左上角话数胶囊、标题 10.5、副标 9；hover 上浮 3px + 描边变主色。
class LibraryGrid extends ConsumerWidget {
  const LibraryGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(libraryProvider);
    final books = state.value ?? ref.read(libraryProvider.notifier).lastGood;
    final query = ref.watch(shelfQueryProvider).trim();
    // 右侧网格**只显示单本**（未归并单话在左栏，不在这里出现）。
    final onlyBooks = books.where((b) => b.isBook).toList();
    final shown = query.isEmpty
        ? onlyBooks
        : onlyBooks.where((b) => b.name.toLowerCase().contains(query.toLowerCase())).toList();

    if (books.isEmpty && state.hasError) {
      return ErrorState(error: state.error, onRetry: () => ref.read(libraryProvider.notifier).refresh());
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行（ver1.0 `.lib-main` 头）：本地漫画库 + 计数 + 刷新 / 新建漫画。
          Row(
            children: [
              Text(
                l10n.libLocalLibrary,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTokens.textPrimary),
              ),
              const SizedBox(width: 8),
              Text(
                '${onlyBooks.length} · ${onlyBooks.fold<int>(0, (a, b) => a + b.pageCount)}',
                style: const TextStyle(fontSize: 9.5, color: AppTokens.textSecondary),
              ),
              const Spacer(),
              const LibraryHeaderActions(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // 搜索框（设计稿 `.shelf-search`）：本页只做本地过滤。
              SizedBox(
                width: 220,
                height: 30,
                child: TextField(
                  style: const TextStyle(fontSize: 11, color: AppTokens.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: AppTokens.card,
                    hintText: l10n.shelfSearchHint,
                    hintStyle: const TextStyle(fontSize: 10, color: AppTokens.textSecondary),
                    prefixIcon: const Icon(LucideIcons.search, size: 12, color: AppTokens.textSecondary),
                    prefixIconConstraints: const BoxConstraints(minWidth: 28),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => ref.read(shelfQueryProvider.notifier).set(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (shown.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  books.isEmpty ? l10n.shelfEmpty : l10n.shelfNoMatch,
                  style: const TextStyle(fontSize: 12.5, color: AppTokens.textSecondary),
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 170,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.62,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) => _BookCard(book: shown[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _BookCard extends ConsumerStatefulWidget {
  const _BookCard({required this.book});

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
                    border: Border.all(color: _hover ? AppTokens.accent : Colors.transparent),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTokens.accent, Color(0xFF3A2C14)],
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
                            style: const TextStyle(fontSize: 9, color: Colors.white),
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
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                b.isBook ? '${b.hasAuthor ? b.author : l10n.bookUnnamedAuthor} · ${b.pageCount}' : '${b.pageCount}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: AppTokens.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
