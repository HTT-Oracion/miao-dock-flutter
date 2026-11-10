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
import '../../domain/online_models.dart';
import '../../domain/online_source.dart';
import 'online_common.dart';

/// 在线视图左栏（设计稿 `.shelf`，宽 246）。
class OnlineShelf extends ConsumerWidget {
  const OnlineShelf({super.key, required this.onManageSources, required this.onOpenComic, required this.onContinue});

  final VoidCallback onManageSources;
  final void Function(String sourceId, String comicId) onOpenComic;
  final void Function(ReadingProgress progress) onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final sources = ref.watch(onlineSourcesProvider);
    final active = ref.watch(activeOnlineSourceProvider);
    final nav = ref.watch(onlineNavProvider);
    final recent = ref.watch(onlineRecentProvider);
    final downloads = ref.watch(onlineDownloadsProvider).value ?? const [];
    final activeDownloads = downloads.where((task) => task.isActive).length;

    return Container(
      width: 246,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(right: BorderSide(color: palette.line2)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(
                children: [
                  Text(
                    l10n.onlineSourceTitle,
                    style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.ink),
                  ),
                  const Spacer(),
                  AppButton(
                    icon: LucideIcons.plus,
                    onTap: onManageSources,
                    variant: AppButtonVariant.ghost,
                    border: false,
                    width: 34,
                    height: 34,
                    horizontalPadding: 0,
                    fontSize: AppFont.px15,
                    color: palette.ink2,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                sources.when(
                  skipLoadingOnRefresh: true,
                  data: (items) => items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: OnlineStateBox(
                            icon: LucideIcons.inbox,
                            title: l10n.onlineSourceEmpty,
                            description: l10n.onlineSourceEmptyHintShort,
                            actionLabel: l10n.onlineGoImportShort,
                            actionIcon: LucideIcons.plus,
                            onAction: onManageSources,
                            compact: true,
                          ),
                        )
                      : Column(
                          children: [
                            for (final (index, source) in items.indexed)
                              _PlatformRow(
                                source: source,
                                index: index,
                                active: active?.id == source.id,
                                onTap: source.enabled
                                    ? () {
                                        ref.read(onlineSourceSelectionProvider.notifier).select(source.id);
                                        ref.read(onlineNavProvider.notifier).selectView(OnlineView.discover);
                                      }
                                    : null,
                              ),
                          ],
                        ),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Column(children: [_PlatformSkeleton(), _PlatformSkeleton(), _PlatformSkeleton()]),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: OnlineErrorBox(
                      error: error,
                      title: l10n.onlinePlatformLoadFailed,
                      description: l10n.onlinePlatformLoadFailedHint,
                      onRetry: () => ref.read(onlineSourcesProvider.notifier).refresh(),
                      compact: true,
                    ),
                  ),
                ),
                Container(
                  height: 1,
                  color: palette.line,
                  margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                  child: Text(
                    l10n.onlineSectionBrowse,
                    style: TextStyle(
                      fontSize: AppFont.px10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: palette.accInk,
                    ),
                  ),
                ),
                _BrowseRow(
                  icon: LucideIcons.compass,
                  label: l10n.onlineDiscover,
                  active: nav.view == OnlineView.discover && nav.query.isEmpty,
                  onTap: () => ref.read(onlineNavProvider.notifier).selectView(OnlineView.discover),
                ),
                _BrowseRow(
                  icon: LucideIcons.layers,
                  label: l10n.onlineCategories,
                  active: nav.view == OnlineView.categories && nav.query.isEmpty,
                  onTap: () => ref.read(onlineNavProvider.notifier).selectView(OnlineView.categories),
                ),
                _BrowseRow(
                  icon: LucideIcons.history,
                  label: l10n.onlineRecent,
                  active: nav.view == OnlineView.recent,
                  onTap: () => ref.read(onlineNavProvider.notifier).selectView(OnlineView.recent),
                ),
                _BrowseRow(
                  icon: LucideIcons.download,
                  label: l10n.onlineDownloads,
                  active: nav.view == OnlineView.downloads,
                  badge: activeDownloads > 0 ? activeDownloads : null,
                  onTap: () => ref.read(onlineNavProvider.notifier).selectView(OnlineView.downloads),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Text(
                    l10n.onlineSectionRecent,
                    style: TextStyle(
                      fontSize: AppFont.px10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: palette.accInk,
                    ),
                  ),
                ),
                recent.when(
                  data: (items) => items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            l10n.onlineRecentEmpty,
                            style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                          ),
                        )
                      : Column(
                          children: [
                            for (final progress in items.take(3))
                              _RecentRow(
                                progress: progress,
                                onOpen: () => onOpenComic(progress.sourceId, progress.comicId),
                                onContinue: () => onContinue(progress),
                              ),
                          ],
                        ),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Column(children: [_RecentSkeleton(), _RecentSkeleton(), _RecentSkeleton()]),
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformRow extends StatefulWidget {
  const _PlatformRow({required this.source, required this.index, required this.active, required this.onTap});

  final OnlineSource source;
  final int index;
  final bool active;
  final VoidCallback? onTap;

  @override
  State<_PlatformRow> createState() => _PlatformRowState();
}

class _PlatformRowState extends State<_PlatformRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final source = widget.source;
    final enabled = source.enabled;
    final bg = widget.active ? palette.accSoft : (_hover && enabled ? palette.hi : Colors.transparent);
    final subtitle = source.isAbnormal
        ? l10n.onlineSourceSummaryAbnormal(source.version, source.capabilities.length)
        : l10n.onlineSourceSummary(source.version, source.capabilities.length);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: Row(
              children: [
                OnlineSourceLogo(glyph: source.glyph, size: 26, tone: widget.index),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFont.px11_5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppFont.px9_5, height: 1.5, color: palette.mut),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: source.isAbnormal ? palette.bad : (enabled ? palette.good : palette.mut),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrowseRow extends StatefulWidget {
  const _BrowseRow({required this.icon, required this.label, required this.active, required this.onTap, this.badge});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? badge;

  @override
  State<_BrowseRow> createState() => _BrowseRowState();
}

class _BrowseRowState extends State<_BrowseRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bg = widget.active ? palette.accSoft : (_hover ? palette.hi : Colors.transparent);
    final fg = widget.active ? palette.accInk : palette.ink2;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
          child: Row(
            children: [
              Icon(widget.icon, size: 15, color: fg),
              const SizedBox(width: 9),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: AppFont.px11_5,
                  color: fg,
                  fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const Spacer(),
              if (widget.badge != null) OnlineTag('${widget.badge}', tone: OnlineTagTone.warn),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentRow extends StatefulWidget {
  const _RecentRow({required this.progress, required this.onOpen, required this.onContinue});

  final ReadingProgress progress;
  final VoidCallback onOpen;
  final VoidCallback onContinue;

  @override
  State<_RecentRow> createState() => _RecentRowState();
}

class _RecentRowState extends State<_RecentRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final progress = widget.progress;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: _hover ? palette.hi : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OnlineMiniCover(
                tone: progress.coverTone,
                label: progress.comicTitle.length > 2 ? progress.comicTitle.substring(0, 2) : progress.comicTitle,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.comicTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFont.px10_5,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: palette.ink,
                      ),
                    ),
                    Text(
                      '${progress.chapterTitle} · P${progress.page}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px9_5, height: 1.5, color: palette.mut),
                    ),
                    const SizedBox(height: 4),
                    OnlineProgressBar(fraction: progress.fraction),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onContinue,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, top: 2),
                    child: Icon(LucideIcons.play, size: 13, color: palette.mut),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformSkeleton extends StatelessWidget {
  const _PlatformSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SkeletonBox(width: 26, height: 26, radius: 7),
          SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [SkeletonBox(width: 72, height: 10), SizedBox(height: 6), SkeletonBox(width: 110, height: 8)],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSkeleton extends StatelessWidget {
  const _RecentSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SkeletonBox(width: 30, height: 40, radius: 4),
          SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [SkeletonBox(width: 80, height: 9), SizedBox(height: 6), SkeletonBox(width: 56, height: 8)],
            ),
          ),
        ],
      ),
    );
  }
}
