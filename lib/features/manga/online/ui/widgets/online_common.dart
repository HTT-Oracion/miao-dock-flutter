import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/theme/tokens.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/widgets/buttons.dart';
import '../../../../../shared/widgets/skeleton.dart';
import '../../controller/online_browse_controller.dart';
import '../../domain/online_models.dart';
import 'online_cover.dart';
import '../../../../../shared/responsive.dart';

// `OnlineTag` / `OnlineStateBox` 已上移到 shared/widgets/state_box.dart：
// 音乐源面板要用同一套空态与标签，而 feature 之间不得横向 import。
// 本文件自身要用故 import，同时 re-export 保持既有调用点不变。
import '../../../../../shared/widgets/state_box.dart';
export '../../../../../shared/widgets/state_box.dart';

/// 分区标题：标题 + 计数 + hint + 右侧动作。
class OnlineSectionHeader extends StatelessWidget {
  const OnlineSectionHeader({
    super.key,
    required this.title,
    this.tag,
    this.hint,
    this.action,
    this.margin = const EdgeInsets.only(top: 4, bottom: 12),
  });

  final String title;
  final String? tag;
  final String? hint;
  final Widget? action;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: margin,
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.ink),
          ),
          if (tag != null) ...[const SizedBox(width: 10), OnlineTag(tag!)],
          if (hint != null) const SizedBox(width: 10),
          // 用 tight Expanded 吃掉中段空白：Flexible + Spacer 时 loose flex 的
          // 剩余份额会留在行尾，导致「换一批」离页面右边还差一截。
          Expanded(
            child: hint == null
                ? const SizedBox.shrink()
                : Text(
                    hint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                  ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// 3px 进度条（设计稿 `.bar`）。
class OnlineProgressBar extends StatelessWidget {
  const OnlineProgressBar({super.key, required this.fraction, this.width});

  final double fraction;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(color: palette.hi, borderRadius: BorderRadius.circular(2)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0, 1),
          child: Container(
            decoration: BoxDecoration(color: palette.acc, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      ),
    );
  }
}

/// 错误态：标题 + 错误码 + 说明 + 重试。
class OnlineErrorBox extends StatelessWidget {
  const OnlineErrorBox({
    super.key,
    required this.error,
    required this.title,
    required this.description,
    required this.onRetry,
    this.compact = false,
  });

  final Object? error;
  final String title;
  final String description;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return OnlineStateBox(
      icon: LucideIcons.wifiOff,
      title: title,
      description: description,
      code: errorWireName(error),
      actionLabel: l10n.onlineErrorRetry,
      actionIcon: LucideIcons.refreshCw,
      primary: true,
      onAction: onRetry,
      compact: compact,
    );
  }
}

/// 首页 / 分类的加载骨架（固定高度，避免布局跳动）。
class OnlineGridSkeleton extends StatelessWidget {
  const OnlineGridSkeleton({super.key, this.count = 7, this.extent = 140});

  final int count;
  final double extent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = context.isMobile;
        final spacing = mobile ? 12.0 : 14.0;
        final columns = mobile ? 2 : ((constraints.maxWidth + spacing) / (extent + spacing)).ceil().clamp(2, 8);
        final itemWidth = (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: mobile ? 6 : count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: itemWidth * 4 / 3 + 41.4,
          ),
          itemBuilder: (context, index) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(builder: (context, cell) => SkeletonBox(height: cell.maxHeight, radius: 8)),
              ),
              const SizedBox(height: 9),
              const SkeletonBox(height: 11, width: 82),
              const SizedBox(height: 6),
              const SkeletonBox(height: 9, width: 56),
            ],
          ),
        );
      },
    );
  }
}

/// 书籍卡片（hover 上浮 3px + 阴影）。
class OnlineBookCard extends StatefulWidget {
  const OnlineBookCard({super.key, required this.comic, required this.onTap, this.showBadge = true});

  final OnlineComic comic;
  final VoidCallback onTap;
  final bool showBadge;

  @override
  State<OnlineBookCard> createState() => _OnlineBookCardState();
}

class _OnlineBookCardState extends State<OnlineBookCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: AppMotion.pageSwitch,
                curve: AppMotion.morphCurve,
                transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _hover
                      ? [BoxShadow(color: palette.shadow, blurRadius: 24, offset: const Offset(0, 8))]
                      : const [],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    OnlineCover(comic: widget.comic, showBadge: widget.showBadge),
                    if (widget.comic.rank != null)
                      Positioned(left: 6, top: 6, child: _OnlineRankBadge(rank: widget.comic.rank!)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            SizedBox(
              height: 18.4,
              child: Text(
                widget.comic.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: context.isMobile ? AppFont.px11 : AppFont.px11_5,
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                ),
              ),
            ),
            SizedBox(
              height: 16,
              child: Text(
                comicSubtitle(context, widget.comic),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppFont.px10, height: 1.6, color: palette.mut),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineRankBadge extends StatelessWidget {
  const _OnlineRankBadge({required this.rank});

  final int rank;

  static const _topColors = <Color>[
    Color(0xFFE7B84B),
    Color(0xFFC9D1DF),
    Color(0xFFC98252),
    Color(0xFF5B8FD6),
    Color(0xFF8C6BC8),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final index = rank - 1;
    final bg = index >= 0 && index < _topColors.length ? _topColors[index] : palette.ink2.withValues(alpha: 0.82);
    final fg = index >= 0 && index < 3 ? const Color(0xFF241A08) : Colors.white;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(color: palette.shadow.withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Text(
        'No.$rank',
        style: TextStyle(fontSize: AppFont.px11, height: 1, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.2),
      ),
    );
  }
}

String comicSubtitle(BuildContext context, OnlineComic comic) {
  final l10n = AppLocalizations.of(context);
  if (comic.status == ComicStatus.completed) {
    return l10n.onlineStatusCompletedAll(comic.chapterCount);
  }
  final status = switch (comic.status) {
    ComicStatus.ongoing => l10n.onlineStatusOngoing,
    ComicStatus.completed => l10n.onlineStatusCompleted,
    ComicStatus.unknown => l10n.onlineStatusUnknown,
  };
  final latest = comic.latestChapter;
  return latest == null ? status : l10n.onlineLatestChapter(latest, status);
}

/// 自适应书籍栅格（桌面 7 列 / 移动 2 列）。
class OnlineBookGrid extends StatelessWidget {
  const OnlineBookGrid({super.key, required this.comics, required this.onOpen, this.showBadges = true});

  final List<OnlineComic> comics;
  final ValueChanged<OnlineComic> onOpen;
  final bool showBadges;

  @override
  Widget build(BuildContext context) {
    if (comics.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = context.isMobile;
        final spacing = mobile ? 12.0 : 14.0;
        final columns = mobile ? 2 : ((constraints.maxWidth + spacing) / (140 + spacing)).ceil().clamp(2, 8);
        final itemWidth = (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: comics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: itemWidth * 4 / 3 + 41.4,
          ),
          itemBuilder: (context, index) =>
              OnlineBookCard(comic: comics[index], onTap: () => onOpen(comics[index]), showBadge: showBadges),
        );
      },
    );
  }
}

/// 平台 / 源图标（26 / 32 / 38 三档）。
class OnlineSourceLogo extends StatelessWidget {
  const OnlineSourceLogo({super.key, required this.glyph, this.size = 26, this.tone = 0, this.radius = 7});

  final String glyph;
  final double size;
  final int tone;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final gradient = switch (tone % 3) {
      1 => onlineCoverGradient(CoverTone.blue),
      2 => onlineCoverGradient(CoverTone.purple),
      _ => LinearGradient(
        begin: const Alignment(-0.7, -0.9),
        end: const Alignment(0.7, 0.9),
        colors: [palette.acc, palette.coverEnd],
      ),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(radius)),
      alignment: Alignment.center,
      child: Text(
        glyph,
        style: TextStyle(
          fontSize: size <= 26 ? AppFont.px11 : AppFont.px12,
          height: 1,
          fontWeight: FontWeight.w700,
          color: palette.paperCard,
        ),
      ),
    );
  }
}

/// 题材 / 平台筛选 chip。
class OnlineChip extends StatefulWidget {
  const OnlineChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.leading,
    this.height,
    this.horizontalPadding = 12,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final double? height;
  final double horizontalPadding;

  @override
  State<OnlineChip> createState() => _OnlineChipState();
}

class _OnlineChipState extends State<OnlineChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bg = widget.selected ? palette.acc : (_hover ? palette.hi : Colors.transparent);
    final fg = widget.selected ? palette.onBtn : palette.ink2;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          height: widget.height ?? (context.isMobile ? 32 : 28),
          padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: widget.selected ? palette.acc : palette.line2),
            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 5)],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: AppFont.px11,
                  height: 1.4,
                  color: fg,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 最近阅读 / 缓存行里的迷你封面。
class OnlineMiniCover extends StatelessWidget {
  const OnlineMiniCover({
    super.key,
    required this.tone,
    this.width = 30,
    this.height = 40,
    this.radius = 4,
    this.label,
  });

  final CoverTone tone;
  final double width;
  final double height;
  final double radius;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(gradient: onlineCoverGradient(tone), borderRadius: BorderRadius.circular(radius)),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(2),
      child: label == null
          ? null
          : Text(
              label!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppFont.px8, height: 1.2, color: palette.paperCard),
            ),
    );
  }
}

/// 相对时间（设计稿「2 小时前」）。
String onlineRelativeTime(AppLocalizations l10n, DateTime time, {DateTime? now}) {
  final delta = (now ?? DateTime.now()).difference(time);
  if (delta.inMinutes < 1) return l10n.onlineDateJustNow;
  if (delta.inMinutes < 60) return l10n.onlineDateMinutesAgo(delta.inMinutes);
  if (delta.inHours < 24) return l10n.onlineDateHoursAgo(delta.inHours);
  return l10n.onlineDateDaysAgo(delta.inDays);
}

/// 横幅（设计稿 `.banner`：info / warn / bad）。
enum OnlineBannerTone { info, warn, bad, ok }

class OnlineBanner extends StatelessWidget {
  const OnlineBanner({super.key, required this.text, this.tone = OnlineBannerTone.info, this.icon = LucideIcons.info});

  final String text;
  final OnlineBannerTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = switch (tone) {
      OnlineBannerTone.info => palette.blue,
      OnlineBannerTone.warn => palette.warn,
      OnlineBannerTone.bad => palette.bad,
      OnlineBannerTone.ok => palette.good,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppFont.px11_5, height: 1.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 舞台黑色（设计稿 `--stage-bg` 独立于主题）。
Color onlineReaderStageColor() => const Color(0xFF000000);
