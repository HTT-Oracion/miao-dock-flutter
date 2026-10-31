import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../core/utils/format.dart';
import '../controller/library_controller.dart';
import '../domain/manga_status.dart';
import 'library_search_results.dart';
import '../domain/lib_book.dart';
import '../domain/manga_task.dart';

/// 详情主区（设计稿 G Main）：Hero（封面 + 标题 + 元信息 + 动作）+ 章节卡（一行两话）。
class LibraryDetail extends ConsumerWidget {
  const LibraryDetail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(shelfQueryProvider).trim();
    if (query.isNotEmpty) {
      // 搜索态（设计稿 G Row 4）：右栏切换为分组命中结果。
      return LibrarySearchResults(query: query);
    }
    final state = ref.watch(libraryProvider);
    final books = state.value ?? ref.read(libraryProvider.notifier).lastGood;

    // 失败且从没成功过：给整块错误态，**不能用空态冒充**（design.html §07）。
    if (books.isEmpty && state.hasError) {
      return ErrorState(error: state.error, onRetry: () => ref.read(libraryProvider.notifier).refresh());
    }
    if (books.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).shelfEmpty,
          style: const TextStyle(fontSize: 12.5, color: AppTokens.textSecondary),
        ),
      );
    }
    final selected = ref.watch(selectedBookProvider);
    final book = books.where((b) => b.key == selected).firstOrNull ?? books.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        _Hero(book: book),
        const SizedBox(height: 16),
        _SectionHeader(book: book),
        const SizedBox(height: 10),
        _ChapterGrid(book: book),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 96,
            height: 112,
            decoration: BoxDecoration(color: AppTokens.cardCover, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: const Icon(LucideIcons.bookOpen, size: 24, color: AppTokens.textSecondary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.textPrimary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _MetaChip(AppLocalizations.of(context).bookAuthorLabel(book.author)),
                    _MetaChip(AppLocalizations.of(context).bookChapterCount(book.chapterCount)),
                    _MetaChip(AppLocalizations.of(context).bookPageCount(book.pageCount)),
                    _MetaChip(formatBytes(book.totalBytes)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTokens.accent,
                        foregroundColor: AppTokens.pageBg,
                      ),
                      onPressed: () {
                        /* TODO: 继续翻译，随补页端点落地 */
                      },
                      icon: const Icon(LucideIcons.fileUp, size: 13),
                      label: Text(AppLocalizations.of(context).bookContinueTranslate, style: TextStyle(fontSize: 12.5)),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.textPrimary,
                        side: const BorderSide(color: AppTokens.progressTrack),
                      ),
                      onPressed: () {
                        /* TODO: 查看漫画阅读器 */
                      },
                      icon: const Icon(LucideIcons.bookOpen, size: 13),
                      label: Text(AppLocalizations.of(context).bookViewComic, style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppTokens.navBg, borderRadius: BorderRadius.circular(5)),
      child: Text(text, style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          AppLocalizations.of(context).bookChapters,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
        ),
        const SizedBox(width: 8),
        Text(
          AppLocalizations.of(context).bookChapterCount(book.chapterCount),
          style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
        ),
        const Spacer(),
        Text(
          AppLocalizations.of(context).bookOneRowTwoChapters,
          style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
        ),
      ],
    );
  }
}

class _ChapterGrid extends StatelessWidget {
  const _ChapterGrid({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 100,
      ),
      itemCount: book.chapters.length,
      itemBuilder: (context, i) => _ChapterCard(chapter: book.chapters[i]),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({required this.chapter});

  final LibChapter chapter;

  @override
  Widget build(BuildContext context) {
    final color = chapter.done ? MangaTaskStatus.done.color : MangaTaskStatus.translating.color;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 64,
            decoration: BoxDecoration(color: AppTokens.cardCover, borderRadius: BorderRadius.circular(6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).chapterTitle(chapter.no),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  AppLocalizations.of(context).chapterMeta(chapter.pageCount, chapter.donePages),
                  style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      value: chapter.ratio,
                      backgroundColor: AppTokens.progressTrack,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
