import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/theme/tokens.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/widgets/buttons.dart';
import '../../../../../shared/widgets/skeleton.dart';
import '../../controller/online_browse_controller.dart';
import '../../controller/online_download_controller.dart';
import '../../controller/online_progress_controller.dart';
import '../../controller/online_sources_controller.dart';
import '../../domain/online_download.dart';
import '../../domain/online_models.dart';
import 'online_common.dart';
import '../../../../../shared/responsive.dart';

/// 浏览页统一内距（桌面 20/22/40，移动 12/14）。
EdgeInsets onlinePagePadding(BuildContext context) =>
    context.isMobile ? const EdgeInsets.fromLTRB(14, 12, 14, 24) : const EdgeInsets.fromLTRB(22, 20, 22, 40);

class OnlineDiscoverView extends ConsumerWidget {
  const OnlineDiscoverView({super.key, required this.onOpenComic, required this.onManageSources});

  final ValueChanged<OnlineComic> onOpenComic;
  final VoidCallback onManageSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final source = ref.watch(activeOnlineSourceProvider);
    final feed = ref.watch(onlineFeedProvider);
    if (source == null) {
      return SingleChildScrollView(
        padding: onlinePagePadding(context),
        child: OnlineStateBox(
          icon: LucideIcons.inbox,
          title: l10n.onlineSourceEmpty,
          description: l10n.onlineSourceEmptyHint,
          actionLabel: l10n.onlineGoImport,
          actionIcon: LucideIcons.plus,
          onAction: onManageSources,
        ),
      );
    }
    return feed.when(
      skipLoadingOnRefresh: true,
      loading: () => SingleChildScrollView(padding: onlinePagePadding(context), child: const OnlineGridSkeleton()),
      error: (error, _) => SingleChildScrollView(
        padding: onlinePagePadding(context),
        child: OnlineErrorBox(
          error: error,
          title: l10n.onlineFeedError,
          description: l10n.onlineFeedErrorHint,
          onRetry: () => ref.read(onlineFeedProvider.notifier).refresh(),
        ),
      ),
      data: (state) {
        if (state.feed.isEmpty) {
          return SingleChildScrollView(
            padding: onlinePagePadding(context),
            child: OnlineStateBox(
              icon: LucideIcons.inbox,
              title: l10n.onlineFeedEmpty,
              description: l10n.onlineFeedEmptyHint,
              actionLabel: l10n.onlineGoImportShort,
              onAction: onManageSources,
            ),
          );
        }
        return OnlineAutoLoadMore(
          enabled: state.feed.hasMore && !state.loadingMore,
          onLoadMore: () => ref.read(onlineFeedProvider.notifier).loadMore(),
          child: SingleChildScrollView(
            padding: onlinePagePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, section) in state.feed.sections.indexed) ...[
                  OnlineSectionHeader(
                    title: section.title,
                    tag: l10n.onlineItemsPerPage(section.pageSize),
                    hint: context.isMobile ? null : section.hint,
                    margin: EdgeInsets.only(top: index == 0 ? 4 : 26, bottom: 12),
                    action: index == 0
                        ? AppButton(
                            label: l10n.onlineRefresh,
                            onTap: () => ref.read(onlineFeedProvider.notifier).refresh(),
                            variant: AppButtonVariant.link,
                            fontSize: AppFont.px11,
                            horizontalPadding: 0,
                          )
                        : null,
                  ),
                  OnlineBookGrid(comics: section.items, onOpen: onOpenComic, showBadges: index == 0),
                ],
                _LoadMoreRow(
                  loading: state.loadingMore,
                  error: state.loadMoreError,
                  hasMore: state.feed.hasMore,
                  page: state.feed.page,
                  total: state.feed.total,
                  onPressed: () => ref.read(onlineFeedProvider.notifier).loadMore(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class OnlineCategoryView extends ConsumerWidget {
  const OnlineCategoryView({super.key, required this.onOpenComic});

  final ValueChanged<OnlineComic> onOpenComic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nav = ref.watch(onlineNavProvider);
    final categories = ref.watch(onlineCategoriesProvider);
    final results = ref.watch(onlineCategoryResultsProvider);
    final fallback = ref.watch(onlineCategoriesFallbackProvider);
    final source = ref.watch(activeOnlineSourceProvider);
    if (source == null) {
      return SingleChildScrollView(
        padding: onlinePagePadding(context),
        child: OnlineStateBox(
          icon: LucideIcons.inbox,
          title: l10n.onlineSourceEmpty,
          description: l10n.onlineSourceEmptyHint,
        ),
      );
    }
    final chips = categories.when(
      skipLoadingOnRefresh: true,
      data: (groups) => _CategoryChips(groups: groups, selected: nav.categoryId),
      loading: () => const _ChipSkeletons(),
      error: (error, _) => const SizedBox.shrink(),
    );

    if (categories.hasError) {
      return SingleChildScrollView(
        padding: onlinePagePadding(context),
        child: OnlineErrorBox(
          error: categories.error,
          title: l10n.onlineCategoryError,
          description: l10n.onlineCategoryErrorHint,
          onRetry: () => ref.read(onlineCategoriesProvider.notifier).refresh(),
        ),
      );
    }

    return SingleChildScrollView(
      padding: onlinePagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          chips,
          if (fallback) OnlineBanner(text: l10n.onlineCategoryFallback, tone: OnlineBannerTone.warn),
          results.when(
            skipLoadingOnRefresh: true,
            loading: () => const OnlineGridSkeleton(),
            error: (error, _) => OnlineErrorBox(
              error: error,
              title: l10n.onlineCategoryError,
              description: l10n.onlineCategoryErrorHint,
              onRetry: () => ref.invalidate(onlineCategoryResultsProvider),
            ),
            data: (state) {
              final categoryName = _categoryName(categories.value, nav.categoryId);
              if (state.page.items.isEmpty) {
                return OnlineStateBox(
                  icon: LucideIcons.layers,
                  title: l10n.onlineCategoryEmpty,
                  description: l10n.onlineCategoryEmptyHint,
                );
              }
              return OnlineAutoLoadMore(
                enabled: state.page.hasMore && !state.loadingMore,
                onLoadMore: () => ref.read(onlineCategoryResultsProvider.notifier).loadMore(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OnlineSectionHeader(
                      title: categoryName,
                      tag: l10n.onlineCategoryTagCount(_categoryCount(categories.value)),
                      hint: context.isMobile ? null : 'category(ctx:{id,page})',
                      margin: const EdgeInsets.only(top: 16, bottom: 12),
                    ),
                    OnlineBookGrid(comics: state.page.items, onOpen: onOpenComic),
                    _LoadMoreRow(
                      loading: state.loadingMore,
                      error: state.loadMoreError,
                      hasMore: state.page.hasMore,
                      page: state.page.page,
                      total: state.page.total,
                      onPressed: () => ref.read(onlineCategoryResultsProvider.notifier).loadMore(),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _categoryName(List<CategoryGroup>? groups, String id) {
    for (final group in groups ?? const <CategoryGroup>[]) {
      for (final item in group.items) {
        if (item.id == id) return item.name;
      }
    }
    return id;
  }

  int _categoryCount(List<CategoryGroup>? groups) =>
      groups?.fold<int>(0, (sum, group) => sum + group.items.length) ?? 0;
}

class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({required this.groups, required this.selected});

  final List<CategoryGroup> groups;
  final String selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final items = [for (final group in groups) ...group.items];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: context.isMobile ? 12 : 10,
        runSpacing: context.isMobile ? 12 : 10,
        children: [
          for (final item in items)
            OnlineChip(
              label: item.name,
              selected: item.id == selected,
              onTap: () {
                ref.read(onlineNavProvider.notifier).selectCategory(item.id);
                ref.invalidate(onlineCategoryResultsProvider);
              },
            ),
          if (groups.isEmpty)
            Text(
              '',
              style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
            ),
        ],
      ),
    );
  }
}

class _ChipSkeletons extends StatelessWidget {
  const _ChipSkeletons();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: const [
          SkeletonBox(width: 52, height: 28, radius: 999),
          SkeletonBox(width: 62, height: 28, radius: 999),
          SkeletonBox(width: 52, height: 28, radius: 999),
          SkeletonBox(width: 62, height: 28, radius: 999),
          SkeletonBox(width: 52, height: 28, radius: 999),
        ],
      ),
    );
  }
}

class OnlineRecentView extends ConsumerWidget {
  const OnlineRecentView({super.key, required this.onOpenComic, required this.onContinue});

  final void Function(String sourceId, String comicId) onOpenComic;
  final ValueChanged<ReadingProgress> onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final recent = ref.watch(onlineRecentProvider);
    return recent.when(
      skipLoadingOnRefresh: true,
      loading: () => SingleChildScrollView(
        padding: onlinePagePadding(context),
        child: const Column(children: [_RecentSkeletonRow(), _RecentSkeletonRow(), _RecentSkeletonRow()]),
      ),
      error: (error, _) => SingleChildScrollView(
        padding: onlinePagePadding(context),
        child: OnlineErrorBox(
          error: error,
          title: l10n.onlineErrorCrashed,
          description: l10n.onlineRecentEmptyHint,
          onRetry: () => ref.read(onlineRecentProvider.notifier).refresh(),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return SingleChildScrollView(
            padding: onlinePagePadding(context),
            child: OnlineStateBox(
              icon: LucideIcons.history,
              title: l10n.onlineRecentEmpty,
              description: l10n.onlineRecentEmptyHint,
            ),
          );
        }
        return SingleChildScrollView(
          padding: onlinePagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OnlineSectionHeader(
                title: l10n.onlineRecent,
                hint: context.isMobile ? null : l10n.onlineRecentHint,
                margin: const EdgeInsets.only(top: 4, bottom: 12),
              ),
              for (final progress in items)
                _RecentListRow(
                  progress: progress,
                  onOpen: () => onOpenComic(progress.sourceId, progress.comicId),
                  onContinue: () => onContinue(progress),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RecentListRow extends StatefulWidget {
  const _RecentListRow({required this.progress, required this.onOpen, required this.onContinue});

  final ReadingProgress progress;
  final VoidCallback onOpen;
  final VoidCallback onContinue;

  @override
  State<_RecentListRow> createState() => _RecentListRowState();
}

class _RecentListRowState extends State<_RecentListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final progress = widget.progress;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          margin: const EdgeInsets.only(bottom: 9),
          padding: EdgeInsets.symmetric(horizontal: context.isMobile ? 12 : 14, vertical: context.isMobile ? 10 : 12),
          decoration: BoxDecoration(
            color: _hover ? palette.hi : palette.card,
            border: Border.all(color: palette.line2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              OnlineMiniCover(
                tone: progress.coverTone,
                width: context.isMobile ? 38 : 40,
                height: context.isMobile ? 52 : 54,
                radius: 6,
                label: progress.comicTitle.length > 2 ? progress.comicTitle.substring(0, 2) : progress.comicTitle,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.comicTitle,
                      style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w600, color: palette.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.isMobile
                          ? l10n.onlineReadAtShort(progress.sourceName, progress.chapterTitle, progress.page)
                          : l10n.onlineReadAt(progress.sourceName, progress.chapterTitle, progress.page),
                      style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: context.isMobile ? double.infinity : 220),
                      child: OnlineProgressBar(fraction: progress.fraction),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AppButton(
                label: context.isMobile ? l10n.onlineContinueShort : l10n.onlineContinue,
                onTap: widget.onContinue,
                variant: AppButtonVariant.primary,
                height: context.isMobile ? 44 : 26,
                horizontalPadding: 10,
                fontSize: AppFont.px11,
                fontWeight: FontWeight.w600,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSkeletonRow extends StatelessWidget {
  const _RecentSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).extension<AppPalette>()?.line2 ?? AppPalette.dark.line2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          SkeletonBox(width: 40, height: 54, radius: 6),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [SkeletonBox(width: 110, height: 10), SizedBox(height: 8), SkeletonBox(width: 180, height: 8)],
            ),
          ),
        ],
      ),
    );
  }
}

class OnlineDownloadsView extends ConsumerWidget {
  const OnlineDownloadsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.watch(onlineDownloadsProvider);
    return tasks.when(
      skipLoadingOnRefresh: true,
      loading: () => SingleChildScrollView(
        padding: onlinePagePadding(context),
        child: const Column(
          children: [
            SkeletonBox(height: 56, radius: 8),
            SizedBox(height: 8),
            SkeletonBox(height: 56, radius: 8),
            SizedBox(height: 8),
            SkeletonBox(height: 56, radius: 8),
          ],
        ),
      ),
      error: (error, _) => SingleChildScrollView(
        padding: onlinePagePadding(context),
        child: OnlineErrorBox(
          error: error,
          title: l10n.onlineDownloadError,
          description: l10n.onlineDownloadErrorHint,
          onRetry: () => ref.read(onlineDownloadsProvider.notifier).refresh(),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return SingleChildScrollView(
            padding: onlinePagePadding(context),
            child: OnlineStateBox(
              icon: LucideIcons.download,
              title: l10n.onlineDownloadEmpty,
              description: l10n.onlineDownloadEmptyHint,
            ),
          );
        }
        return SingleChildScrollView(
          padding: onlinePagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OnlineBanner(
                text: context.isMobile ? l10n.onlineDownloadNoticeMobile : l10n.onlineDownloadNotice,
                icon: LucideIcons.info,
              ),
              OnlineDownloadPanel(tasks: items),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  AppButton(
                    label: l10n.onlineResumeAll,
                    onTap: () => ref.read(onlineDownloadsProvider.notifier).resumeAll(),
                    variant: AppButtonVariant.ghost,
                    height: 28,
                    horizontalPadding: 10,
                    fontSize: AppFont.px11,
                  ),
                  AppButton(
                    label: l10n.onlinePauseAll,
                    onTap: () => ref.read(onlineDownloadsProvider.notifier).pauseAll(),
                    variant: AppButtonVariant.ghost,
                    height: 28,
                    horizontalPadding: 10,
                    fontSize: AppFont.px11,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class OnlineDownloadPanel extends ConsumerWidget {
  const OnlineDownloadPanel({super.key, required this.tasks});

  final List<DownloadTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final (index, task) in tasks.indexed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
              decoration: BoxDecoration(
                border: index == tasks.length - 1 ? null : Border(bottom: BorderSide(color: palette.line)),
              ),
              child: OnlineDownloadRow(task: task),
            ),
        ],
      ),
    );
  }
}

class OnlineDownloadRow extends ConsumerWidget {
  const OnlineDownloadRow({super.key, required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final mobile = context.isMobile;
    final status = downloadStatusLabel(l10n, task, mobile);
    final tone = switch (task.status) {
      DownloadStatus.done => OnlineTagTone.good,
      DownloadStatus.partial => OnlineTagTone.warn,
      DownloadStatus.downloading || DownloadStatus.queued => OnlineTagTone.blue,
      DownloadStatus.failed => OnlineTagTone.bad,
      _ => OnlineTagTone.plain,
    };
    final progress = downloadProgressLabel(l10n, task, mobile);
    final taskPageCount = task.total;
    return Row(
      children: [
        OnlineMiniCover(tone: task.coverTone, width: 30, height: 40, radius: 5),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.comicTitle,
                style: TextStyle(fontSize: AppFont.px11_5, fontWeight: FontWeight.w600, color: palette.ink),
              ),
              Text(
                l10n.onlineDownloadAt(task.chapterTitle, taskPageCount, progress),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
              ),
              const SizedBox(height: 5),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: mobile ? double.infinity : 140),
                child: OnlineProgressBar(fraction: task.fraction),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        OnlineTag(status, tone: tone),
        const SizedBox(width: 4),
        if (task.canPause)
          _TaskIconButton(
            icon: LucideIcons.pause,
            label: l10n.onlinePause,
            onTap: () => ref.read(onlineDownloadsProvider.notifier).pause(task.id),
          )
        else if (task.canResume)
          _TaskIconButton(
            icon: LucideIcons.play,
            label: l10n.onlineResume,
            onTap: () => ref.read(onlineDownloadsProvider.notifier).resume(task.id),
          ),
        if (task.canCancel)
          _TaskIconButton(
            icon: LucideIcons.x,
            label: l10n.onlineCancelTask,
            onTap: () => ref.read(onlineDownloadsProvider.notifier).cancel(task.id),
          ),
      ],
    );
  }
}

class _TaskIconButton extends StatelessWidget {
  const _TaskIconButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      label: label,
      button: true,
      child: AppButton(
        icon: icon,
        onTap: onTap,
        variant: AppButtonVariant.ghost,
        border: false,
        width: context.isMobile ? 44 : 30,
        height: context.isMobile ? 44 : 30,
        horizontalPadding: 0,
        fontSize: context.isMobile ? AppFont.px15 : AppFont.px13,
        color: palette.ink2,
      ),
    );
  }
}

String downloadStatusLabel(AppLocalizations l10n, DownloadTask task, bool mobile) => switch (task.status) {
  DownloadStatus.queued => l10n.onlineDownloadStatusQueued,
  DownloadStatus.downloading => mobile ? l10n.onlineCacheStatusCaching : l10n.onlineDownloadStatusDownloading,
  DownloadStatus.paused => l10n.onlineDownloadStatusPaused,
  DownloadStatus.done => mobile ? l10n.onlineCacheStatusDone : l10n.onlineDownloadStatusDone,
  DownloadStatus.partial => l10n.onlineDownloadStatusPartial,
  DownloadStatus.canceled => l10n.onlineDownloadStatusCanceled,
  DownloadStatus.failed => l10n.onlineDownloadStatusFailed,
};

String downloadProgressLabel(AppLocalizations l10n, DownloadTask task, bool mobile) {
  if (mobile && task.status == DownloadStatus.done) {
    return l10n.onlineCacheDoneProgress(task.done);
  }
  return switch (task.status) {
    DownloadStatus.downloading =>
      mobile
          ? l10n.onlineCacheProgress(task.done, task.total)
          : l10n.onlineDownloadProgressDownloading(task.done, task.total),
    DownloadStatus.done => l10n.onlineDownloadProgressDone(task.done, task.total),
    DownloadStatus.partial => l10n.onlineDownloadProgressPartial(task.done, task.total),
    DownloadStatus.paused => l10n.onlineDownloadProgressPaused(task.done, task.total),
    DownloadStatus.queued => l10n.onlineDownloadProgressQueued,
    DownloadStatus.canceled => l10n.onlineDownloadProgressCanceled,
    _ => l10n.onlineDownloadProgressDownloading(task.done, task.total),
  };
}

class OnlineSearchView extends ConsumerWidget {
  const OnlineSearchView({super.key, required this.onOpenComic});

  final ValueChanged<OnlineComic> onOpenComic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nav = ref.watch(onlineNavProvider);
    final source = ref.watch(activeOnlineSourceProvider);
    final search = ref.watch(onlineSearchProvider);
    return search.when(
      skipLoadingOnRefresh: true,
      loading: () => SingleChildScrollView(padding: onlinePagePadding(context), child: const OnlineGridSkeleton()),
      error: (error, _) => SingleChildScrollView(
        padding: onlinePagePadding(context),
        child: OnlineErrorBox(
          error: error,
          title: l10n.onlineFeedError,
          description: l10n.onlineFeedErrorHint,
          onRetry: () => ref.invalidate(onlineSearchProvider),
        ),
      ),
      data: (state) {
        if (state == null) return const SizedBox.shrink();
        if (state.page.items.isEmpty) {
          return SingleChildScrollView(
            padding: onlinePagePadding(context),
            child: OnlineStateBox(
              icon: LucideIcons.searchX,
              title: l10n.onlineSearchEmpty,
              description: l10n.onlineSearchEmptyHint,
            ),
          );
        }
        return OnlineAutoLoadMore(
          enabled: state.page.hasMore && !state.loadingMore,
          onLoadMore: () => ref.read(onlineSearchProvider.notifier).loadMore(),
          child: SingleChildScrollView(
            padding: onlinePagePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OnlineSectionHeader(
                  title: l10n.onlineSearchTitle(nav.query, source?.name ?? ''),
                  tag: l10n.onlineSearchResultCount(state.page.items.length, '${state.page.hasMore}'),
                  hint: context.isMobile ? null : 'search(ctx:{keyword,page})',
                  margin: const EdgeInsets.only(top: 4, bottom: 12),
                ),
                OnlineBookGrid(comics: state.page.items, onOpen: onOpenComic),
                _LoadMoreRow(
                  loading: state.loadingMore,
                  error: state.loadMoreError,
                  hasMore: state.page.hasMore,
                  page: state.page.page,
                  total: state.page.total,
                  onPressed: () => ref.read(onlineSearchProvider.notifier).loadMore(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoadMoreRow extends StatelessWidget {
  const _LoadMoreRow({
    required this.loading,
    required this.error,
    required this.hasMore,
    required this.page,
    required this.total,
    required this.onPressed,
  });

  final bool loading;
  final Object? error;
  final bool hasMore;
  final int page;
  final int total;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final label = error != null
        ? l10n.onlineRetryLoad
        : (loading
              ? l10n.onlineLoading
              : (hasMore ? l10n.onlineLoadMorePage(page + 1, total) : l10n.onlineNoMore(total)));
    if (!hasMore && error == null && !loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Center(
        child: AppButton(
          label: label,
          onTap: loading ? null : onPressed,
          loading: loading,
          variant: AppButtonVariant.ghost,
          height: 32,
          horizontalPadding: 13,
          fontSize: AppFont.px12,
        ),
      ),
    );
  }
}

/// 触底自动加载（桌面 200px / 移动 160px；按钮仍在，二者共用同一状态机）。
class OnlineAutoLoadMore extends StatelessWidget {
  const OnlineAutoLoadMore({super.key, required this.enabled, required this.onLoadMore, required this.child});

  final bool enabled;
  final VoidCallback onLoadMore;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final threshold = context.isMobile ? 160.0 : 200.0;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical && notification.metrics.extentAfter < threshold) {
          onLoadMore();
        }
        return false;
      },
      child: child,
    );
  }
}
