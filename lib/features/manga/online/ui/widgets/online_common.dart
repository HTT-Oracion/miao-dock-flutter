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

enum OnlineTagTone { plain, acc, good, warn, blue, bad }

/// 设计稿 `.tag`：10 号、1px 描边、胶囊。
class OnlineTag extends StatelessWidget {
  const OnlineTag(this.label, {super.key, this.tone = OnlineTagTone.plain, this.icon});

  final String label;
  final OnlineTagTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (Color bg, Color border, Color fg) = switch (tone) {
      OnlineTagTone.plain => (palette.card, palette.line2, palette.ink2),
      OnlineTagTone.acc => (palette.accSoft, palette.acc.withValues(alpha: 0.45), palette.accInk),
      OnlineTagTone.good => (palette.good.withValues(alpha: 0.12), Colors.transparent, palette.good),
      OnlineTagTone.warn => (palette.warn.withValues(alpha: 0.12), Colors.transparent, palette.warn),
      OnlineTagTone.blue => (palette.blue.withValues(alpha: 0.12), Colors.transparent, palette.blue),
      OnlineTagTone.bad => (palette.bad.withValues(alpha: 0.12), Colors.transparent, palette.bad),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: AppFont.px11, color: fg), const SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(fontSize: AppFont.px10, height: 1.5, color: fg, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

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
          if (hint != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
              ),
            ),
          ],
          const Spacer(),
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

/// 所有异步区域的空 / 错 / 紧凑态。
///
/// 设计稿 `.statebox`：虚线描边、图标 30、标题 13、说明 11.5、错误码 10 等宽。
class OnlineStateBox extends StatelessWidget {
  const OnlineStateBox({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.code,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.primary = false,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? code;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final bool primary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: compact ? 22 : 30, color: code != null ? palette.bad : palette.good),
        SizedBox(height: compact ? 6 : 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? AppFont.px11_5 : AppFont.px13,
            fontWeight: FontWeight.w600,
            color: palette.ink,
          ),
        ),
        if (code != null && code!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(4)),
            child: Text(
              code!,
              style: TextStyle(fontSize: AppFont.px10, color: palette.bad, fontFamily: 'monospace'),
            ),
          ),
        ],
        SizedBox(height: compact ? 4 : 6),
        Text(
          description,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: compact ? AppFont.px10 : AppFont.px11_5, height: 1.7, color: palette.ink2),
        ),
        if (actionLabel != null) ...[
          SizedBox(height: compact ? 8 : 12),
          AppButton(
            label: actionLabel!,
            icon: actionIcon,
            onTap: onAction,
            variant: primary ? AppButtonVariant.primary : AppButtonVariant.ghost,
            height: compact ? 28 : 32,
            horizontalPadding: compact ? 10 : 13,
            fontSize: compact ? AppFont.px11 : AppFont.px12,
          ),
        ],
      ],
    );
    return CustomPaint(
      painter: _DashedBorderPainter(color: palette.line2, radius: AppMetrics.radiusCard),
      child: Container(
        constraints: BoxConstraints(minHeight: compact ? 104 : 220),
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20, vertical: compact ? 12 : 64),
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 230 : 420),
          child: content,
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 4.0;
      const gap = 4.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => oldDelegate.color != color || oldDelegate.radius != radius;
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
                child: OnlineCover(comic: widget.comic, showBadge: widget.showBadge),
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
