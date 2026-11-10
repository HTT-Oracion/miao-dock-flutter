import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/theme/tokens.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/widgets/buttons.dart';
import '../../../../../shared/responsive.dart';
import '../../../../../shared/widgets/skeleton.dart';
import '../../controller/online_browse_controller.dart';
import '../../domain/online_error.dart';
import '../../controller/online_detail_controller.dart';
import '../../controller/online_progress_controller.dart';
import '../../controller/online_sources_controller.dart';
import '../../domain/online_models.dart';
import 'online_browse_views.dart';
import 'online_common.dart';
import 'online_cover.dart';

typedef OnlineReadCallback = void Function(
  OnlineComicDetail detail,
  OnlineChapter chapter, {
  int? page,
  bool autoTranslate,
});
typedef OnlineDownloadCallback = void Function(OnlineComicDetail detail, OnlineChapter chapter, bool translate);

/// 桌面详情内容（主区滚动区，设计稿 `#detail-region`）。
class OnlineDesktopDetailView extends ConsumerWidget {
  const OnlineDesktopDetailView({
    super.key,
    required this.onBack,
    required this.onRead,
    required this.onDownload,
    required this.onManageSources,
  });

  final VoidCallback onBack;
  final OnlineReadCallback onRead;
  final OnlineDownloadCallback onDownload;
  final VoidCallback onManageSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(onlineDetailProvider);
    return detail.when(
      skipLoadingOnRefresh: true,
      loading: () => SingleChildScrollView(
        padding: onlinePagePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            SkeletonBox(height: 20, width: 120),
            SizedBox(height: 18),
            SkeletonBox(height: 200, radius: 10),
            SizedBox(height: 18),
            SkeletonBox(height: 36, radius: 8),
            SizedBox(height: 8),
            SkeletonBox(height: 36, radius: 8),
          ],
        ),
      ),
      error: (error, _) => SingleChildScrollView(
        padding: onlinePagePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: l10n.onlineBack,
                onTap: onBack,
                variant: AppButtonVariant.ghost,
                height: 32,
                horizontalPadding: 10,
                fontSize: AppFont.px11,
              ),
            ),
            const SizedBox(height: 16),
            if (errorCodeOf(error) == OnlineErrorCode.notFound)
              OnlineStateBox(
                icon: LucideIcons.searchX,
                title: l10n.onlineDetailEmpty,
                description: l10n.onlineDetailEmptyHint,
                actionLabel: l10n.onlineDetailBack,
                onAction: onBack,
              )
            else
              OnlineErrorBox(
                error: error,
                title: l10n.onlineDetailError,
                description: l10n.onlineDetailErrorHint,
                onRetry: () => ref.read(onlineDetailProvider.notifier).refresh(),
              ),
          ],
        ),
      ),
      data: (value) {
        if (value == null) return const SizedBox.shrink();
        if (!value.hasChapters && value.comic.title.isEmpty) {
          return _detailEmpty(context, l10n);
        }
        return SingleChildScrollView(
          padding: onlinePagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppButton(
                    label: l10n.onlineBack,
                    onTap: onBack,
                    variant: AppButtonVariant.ghost,
                    height: 28,
                    horizontalPadding: 9,
                    fontSize: AppFont.px11,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${ref.watch(activeOnlineSourceProvider)?.name ?? ''} / ${l10n.onlineDiscover} / ${l10n.onlineDetailTitle}',
                    style: TextStyle(fontSize: AppFont.px10_5, color: AppPalette.of(context).mut),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _DesktopHero(detail: value, onRead: onRead, onDownload: onDownload),
              const SizedBox(height: 20),
              OnlineBanner(text: l10n.onlineChapterGroupHint, icon: LucideIcons.info),
              _Chapters(detail: value, onRead: (chapter) => onRead(value, chapter)),
            ],
          ),
        );
      },
    );
  }

  Widget _detailEmpty(BuildContext context, AppLocalizations l10n) => SingleChildScrollView(
    padding: onlinePagePadding(context),
    child: OnlineStateBox(
      icon: LucideIcons.searchX,
      title: l10n.onlineDetailEmpty,
      description: l10n.onlineDetailEmptyHint,
      actionLabel: l10n.onlineDetailBack,
      onAction: onBack,
    ),
  );
}

class _DesktopHero extends ConsumerWidget {
  const _DesktopHero({required this.detail, required this.onRead, required this.onDownload});

  final OnlineComicDetail detail;
  final OnlineReadCallback onRead;
  final OnlineDownloadCallback onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final translateEnabled = ref.watch(activeOnlineSourceProvider)?.translationEnabled ?? false;
    final comic = detail.comic;
    final progress = _progressFor(ref, comic.id);
    final firstChapter = detail.chapters.isNotEmpty ? detail.chapters.first : null;
    final readChapter = progress == null
        ? firstChapter
        : OnlineChapter(id: progress.chapterId, title: progress.chapterTitle, group: ChapterGroup.serial);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          height: 200,
          child: OnlineCover(
            comic: comic,
            radius: 10,
            showChapterCount: true,
            titleSize: AppFont.px14,
            padding: 12,
            showBadge: false,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                comic.title,
                style: TextStyle(fontSize: AppFont.px18, fontWeight: FontWeight.w700, color: palette.ink),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OnlineTag(switch (comic.status) {
                    ComicStatus.ongoing => l10n.onlineStatusOngoing,
                    ComicStatus.completed => l10n.onlineStatusCompleted,
                    ComicStatus.unknown => l10n.onlineStatusUnknown,
                  }, tone: OnlineTagTone.acc),
                  for (final tag in comic.tags) OnlineTag(tag),
                  Text(
                    comic.author == null
                        ? l10n.onlineChapterCount(comic.chapterCount)
                        : l10n.onlineComicMeta(comic.author!, comic.chapterCount),
                    style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 660),
                child: Text(
                  comic.description,
                  style: TextStyle(fontSize: AppFont.px11_5, height: 1.8, color: palette.ink2),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  AppButton(
                    label: l10n.onlineStartRead,
                    icon: LucideIcons.bookOpen,
                    onTap: firstChapter == null ? null : () => onRead(detail, firstChapter),
                    variant: AppButtonVariant.primary,
                    height: 32,
                    horizontalPadding: 13,
                    fontSize: AppFont.px12,
                    fontWeight: FontWeight.w600,
                  ),
                  if (progress != null && readChapter != null)
                    AppButton(
                      label: l10n.onlineContinueReadingWith(progress.chapterTitle, progress.page),
                      icon: LucideIcons.play,
                      onTap: () => onRead(detail, readChapter, page: progress.page),
                      variant: AppButtonVariant.ghost,
                      height: 32,
                      horizontalPadding: 13,
                      fontSize: AppFont.px12,
                    ),
                  AppButton(
                    label: l10n.onlineDownloadAction,
                    icon: LucideIcons.download,
                    onTap: readChapter == null ? null : () => onDownload(detail, readChapter, false),
                    variant: AppButtonVariant.ghost,
                    height: 32,
                    horizontalPadding: 13,
                    fontSize: AppFont.px12,
                  ),
                  if (translateEnabled)
                    AppButton(
                      label: l10n.onlineTranslateAndDownload,
                      icon: LucideIcons.languages,
                      onTap: readChapter == null ? null : () => onDownload(detail, readChapter, true),
                      variant: AppButtonVariant.ghost,
                      height: 32,
                      horizontalPadding: 13,
                      fontSize: AppFont.px12,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 移动端详情滑层（设计稿 `#m-detail-slide`，从右滑入）。
class OnlineMobileDetailSlide extends ConsumerWidget {
  const OnlineMobileDetailSlide({
    super.key,
    required this.onBack,
    required this.onRead,
    required this.onDownload,
    required this.onCache,
    required this.onManageSources,
  });

  final VoidCallback onBack;
  final OnlineReadCallback onRead;
  final OnlineDownloadCallback onDownload;
  final OnlineDownloadCallback onCache;
  final VoidCallback onManageSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(onlineDetailProvider);
    final comic = detail.value?.comic;
    final progress = comic == null ? null : _progressFor(ref, comic.id);
    final firstChapter = detail.value?.chapters.isNotEmpty == true ? detail.value!.chapters.first : null;
    return Material(
      color: palette.bg,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: palette.panel,
              border: Border(bottom: BorderSide(color: palette.line2)),
            ),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: l10n.onlineBack,
                  child: AppButton(
                    icon: LucideIcons.arrowLeft,
                    onTap: onBack,
                    variant: AppButtonVariant.ghost,
                    border: false,
                    width: 44,
                    height: 44,
                    horizontalPadding: 0,
                    fontSize: AppFont.px18,
                    color: palette.ink2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.onlineDetailTitle,
                    style: TextStyle(fontSize: AppFont.px13_5, fontWeight: FontWeight.w700, color: palette.ink),
                  ),
                ),
                Semantics(
                  button: true,
                  label: l10n.onlineDetailEye,
                  child: AppButton(
                    icon: LucideIcons.eye,
                    onTap: () {
                      final value = detail.value;
                      if (value == null || value.chapters.isEmpty) return;
                      onRead(value, firstChapter!, page: progress?.page);
                    },
                    variant: AppButtonVariant.ghost,
                    border: false,
                    width: 44,
                    height: 44,
                    horizontalPadding: 0,
                    fontSize: AppFont.px17,
                    color: palette.ink2,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: detail.when(
              skipLoadingOnRefresh: true,
              loading: () => const Padding(
                padding: EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SkeletonBox(height: 140, radius: 10),
                    SizedBox(height: 14),
                    SkeletonBox(height: 44, radius: 8),
                    SizedBox(height: 12),
                    SkeletonBox(height: 44, radius: 8),
                    SizedBox(height: 12),
                    SkeletonBox(height: 44, radius: 8),
                  ],
                ),
              ),
              error: (error, _) => SingleChildScrollView(
                padding: onlinePagePadding(context),
                child: OnlineErrorBox(
                  error: error,
                  title: l10n.onlineDetailError,
                  description: l10n.onlineDetailErrorHint,
                  onRetry: () => ref.read(onlineDetailProvider.notifier).refresh(),
                ),
              ),
              data: (value) {
                if (value == null) return const SizedBox.shrink();
                return SingleChildScrollView(
                  padding: onlinePagePadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MobileHero(
                        detail: value,
                        progress: progress,
                        onRead: onRead,
                        onCache: onCache,
                        onTranslate: onDownload,
                      ),
                      const SizedBox(height: 12),
                      OnlineBanner(text: l10n.onlineMobileDetailNote, icon: LucideIcons.info),
                      const SizedBox(height: 6),
                      OnlineSectionHeader(
                        title: l10n.onlineChapters,
                        tag: l10n.onlineChapterCount(value.comic.chapterCount),
                        margin: const EdgeInsets.only(top: 4, bottom: 10),
                      ),
                      _Chapters(detail: value, onRead: (chapter) => onRead(value, chapter), mobile: true),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileHero extends ConsumerWidget {
  const _MobileHero({
    required this.detail,
    required this.progress,
    required this.onRead,
    required this.onCache,
    required this.onTranslate,
  });

  final OnlineComicDetail detail;
  final ReadingProgress? progress;
  final OnlineReadCallback onRead;
  final OnlineDownloadCallback onCache;
  final OnlineDownloadCallback onTranslate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final translateEnabled = ref.watch(activeOnlineSourceProvider)?.translationEnabled ?? false;
    final comic = detail.comic;
    final firstChapter = detail.chapters.isNotEmpty ? detail.chapters.first : null;
    final readChapter = progress == null
        ? firstChapter
        : OnlineChapter(id: progress!.chapterId, title: progress!.chapterTitle, group: ChapterGroup.serial);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              height: 140,
              child: OnlineCover(
                comic: comic,
                radius: 10,
                showChapterCount: true,
                titleSize: AppFont.px12,
                padding: 9,
                showBadge: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w700, color: palette.ink),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      OnlineTag(switch (comic.status) {
                        ComicStatus.ongoing => l10n.onlineStatusOngoing,
                        ComicStatus.completed => l10n.onlineStatusCompleted,
                        ComicStatus.unknown => l10n.onlineStatusUnknown,
                      }, tone: OnlineTagTone.acc),
                      for (final tag in comic.tags.take(2)) OnlineTag(tag),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    comic.description,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px10_5, height: 1.7, color: palette.ink2),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: l10n.onlineStartRead,
                icon: LucideIcons.bookOpen,
                onTap: firstChapter == null ? null : () => onRead(detail, firstChapter),
                variant: AppButtonVariant.primary,
                height: 44,
                horizontalPadding: 8,
                fontSize: AppFont.px11_5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppButton(
                label: progress == null ? l10n.onlineContinue : l10n.onlineContinuePage(progress!.page),
                icon: LucideIcons.play,
                onTap: readChapter == null ? null : () => onRead(detail, readChapter, page: progress?.page),
                variant: AppButtonVariant.ghost,
                height: 44,
                horizontalPadding: 8,
                fontSize: AppFont.px11_5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: l10n.onlineCache,
                icon: LucideIcons.download,
                onTap: readChapter == null ? null : () => onCache(detail, readChapter, false),
                variant: AppButtonVariant.ghost,
                height: 44,
                horizontalPadding: 8,
                fontSize: AppFont.px11_5,
              ),
            ),
            if (translateEnabled) ...[
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: l10n.onlineReaderTranslationOfChapter,
                  icon: LucideIcons.languages,
                  onTap: readChapter == null ? null : () => onTranslate(detail, readChapter, true),
                  variant: AppButtonVariant.ghost,
                  height: 44,
                  horizontalPadding: 8,
                  fontSize: AppFont.px11_5,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Chapters extends ConsumerStatefulWidget {
  const _Chapters({required this.detail, required this.onRead, this.mobile = false});

  final OnlineComicDetail detail;
  final ValueChanged<OnlineChapter> onRead;
  final bool mobile;

  @override
  ConsumerState<_Chapters> createState() => _ChaptersState();
}

class _ChaptersState extends ConsumerState<_Chapters> {
  final Set<ChapterGroup> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final onRead = widget.onRead;
    final mobile = widget.mobile;
    final l10n = AppLocalizations.of(context);
    final read = ref.watch(onlineReadChaptersProvider).value;
    final sourceId = ref.watch(activeOnlineSourceIdProvider) ?? '';
    final readSet = read?[readChaptersKey(sourceId: sourceId, comicId: detail.comic.id)] ?? const <String>{};
    if (!detail.hasChapters) {
      return OnlineStateBox(
        icon: LucideIcons.list,
        title: l10n.onlineChapterEmpty,
        description: l10n.onlineChapterEmptyHint,
      );
    }
    final groups = [
      (ChapterGroup.serial, l10n.onlineChapterGroupSerial),
      (ChapterGroup.extra, l10n.onlineChapterGroupExtra),
      (ChapterGroup.volume, l10n.onlineChapterGroupVolume),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (group, label) in groups)
          if (detail.groupOf(group).isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() {
                if (!_collapsed.add(group)) _collapsed.remove(group);
              }),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: EdgeInsets.only(top: group == ChapterGroup.serial ? 4 : 18, bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      _collapsed.contains(group) ? LucideIcons.chevronRight : LucideIcons.chevronDown,
                      size: 14,
                      color: AppPalette.of(context).mut,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppFont.px12_5,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.of(context).ink,
                      ),
                    ),
                    const SizedBox(width: 9),
                    OnlineTag('${detail.groupOf(group).length}'),
                    const Spacer(),
                    Text(
                      l10n.onlineChapterOrder,
                      style: TextStyle(fontSize: AppFont.px10, color: AppPalette.of(context).mut),
                    ),
                  ],
                ),
              ),
            ),
            if (!_collapsed.contains(group))
              _ChapterGrid(chapters: detail.groupOf(group), readSet: readSet, onRead: onRead, mobile: mobile),
          ],
      ],
    );
  }
}

class _ChapterGrid extends StatelessWidget {
  const _ChapterGrid({required this.chapters, required this.readSet, required this.onRead, required this.mobile});

  final List<OnlineChapter> chapters;
  final Set<String> readSet;
  final ValueChanged<OnlineChapter> onRead;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = mobile ? 2 : ((constraints.maxWidth + 8) / (166 + 8)).ceil().clamp(2, 6);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: chapters.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: mobile ? 12 : 8,
            mainAxisSpacing: mobile ? 12 : 8,
            mainAxisExtent: mobile ? 44 : 36,
          ),
          itemBuilder: (context, index) {
            final chapter = chapters[index];
            return _ChapterCard(chapter: chapter, read: readSet.contains(chapter.id), onTap: () => onRead(chapter));
          },
        );
      },
    );
  }
}

class _ChapterCard extends StatefulWidget {
  const _ChapterCard({required this.chapter, required this.read, required this.onTap});

  final OnlineChapter chapter;
  final bool read;
  final VoidCallback onTap;

  @override
  State<_ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends State<_ChapterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = widget.read ? palette.mut : palette.ink;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          height: context.isMobile ? 44 : 36,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: _hover ? palette.hi : palette.card,
            border: Border.all(color: _hover ? palette.acc : palette.line2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFont.px11_5, color: fg),
                ),
              ),
              if (widget.read) ...[const SizedBox(width: 4), Icon(LucideIcons.check, size: 14, color: palette.good)],
            ],
          ),
        ),
      ),
    );
  }
}

ReadingProgress? _progressFor(WidgetRef ref, String comicId) {
  final items = ref.watch(onlineRecentProvider).value;
  if (items == null) return null;
  for (final item in items) {
    if (item.comicId == comicId) return item;
  }
  return null;
}
