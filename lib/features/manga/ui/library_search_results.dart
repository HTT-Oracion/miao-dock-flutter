import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:protocol/protocol.dart' show jsNumStr;

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../controller/library_controller.dart';
import '../domain/manga_status.dart';
import '../domain/lib_book.dart';
import '../domain/manga_task.dart';

/// 搜索分组态（设计稿 G Row 4）：右栏按作品分组的命中结果。
/// 分组 = 作品命中（全话列出）或话号命中（仅命中话）；页脚常驻操作提示，Esc 退出。
class LibrarySearchResults extends ConsumerWidget {
  const LibrarySearchResults({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = searchGroups(ref);
    final hitCount = groups.fold<int>(0, (s, g) => s + g.chapters.length);
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          ref.read(shelfQueryProvider.notifier).set('');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: [
          Text(
            AppLocalizations.of(context).searchQuery(query),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTokens.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).searchSummary(groups.length, hitCount),
            style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
          ),
          const SizedBox(height: 14),
          for (final group in groups) ...[_GroupCard(group: group), const SizedBox(height: 12)],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).searchHint,
                  style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
                ),
              ),
              Text(
                AppLocalizations.of(context).searchEscHint,
                style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final ({LibBook book, List<LibChapter> chapters}) group;

  @override
  Widget build(BuildContext context) {
    final book = group.book;
    return Container(
      decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTokens.divider)),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: AppTokens.cardCover, borderRadius: BorderRadius.circular(5)),
                  alignment: Alignment.center,
                  child: Text(
                    book.name.characters.first,
                    style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '《${book.name}》',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).searchChapterHits(group.chapters.length),
                  style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
                ),
                const Spacer(),
                const _OpenShelfLink(),
              ],
            ),
          ),
          for (final chapter in group.chapters) _HitRow(chapter: chapter),
        ],
      ),
    );
  }
}

class _OpenShelfLink extends ConsumerWidget {
  const _OpenShelfLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => ref.read(shelfQueryProvider.notifier).set(''),
      child: Text(
        AppLocalizations.of(context).searchOpenShelf,
        style: const TextStyle(fontSize: 12, color: AppTokens.accent),
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  const _HitRow({required this.chapter});

  final LibChapter chapter;

  @override
  Widget build(BuildContext context) {
    final badge = chapter.done
        ? AppLocalizations.of(context).chapterDone
        : (chapter.donePages == 0
              ? AppLocalizations.of(context).chapterEmpty
              : AppLocalizations.of(context).chapterPendingPages(chapter.pageCount - chapter.donePages));
    final badgeColor = chapter.done
        ? MangaTaskStatus.done.color
        : (chapter.donePages == 0 ? MangaTaskStatus.cancelled.color : MangaTaskStatus.translating.color);
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTokens.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppLocalizations.of(context).chapterTitle(jsNumStr(chapter.no)),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppTokens.textPrimary),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(badge, style: TextStyle(fontSize: 11, color: badgeColor)),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: Text(
              AppLocalizations.of(context).chapterProgress(chapter.donePages, chapter.pageCount),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
