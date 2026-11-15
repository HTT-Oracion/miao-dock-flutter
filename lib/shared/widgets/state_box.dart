import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'buttons.dart';

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

/// 数据源面板「已装源」单行的估算占位高度（桌面档）。
///
/// 卡片 = 上下内距 12×2 + 内容高约 38，再加列表项间距 9。
/// 弹窗用它把「超过 4 条」换算成列表区最大高度，见 `kSourceListMaxVisible`。
const double kSourceRowExtent = 71;

/// 弹窗里「已导入的源」一屏最多显示几条；超过则列表区滚动。
const int kSourceListMaxVisible = 4;

/// 所有异步区域的空 / 错 / 紧凑态。
///
/// 设计稿 `.statebox`：虚线描边、图标 30、标题 13、说明 11.5、错误码 10 等宽。
///
/// 漫画源与音乐源两个「数据源」页共用本组件，保证两侧空态视觉一致；
/// 放在 `shared/` 而不是任一 feature 内，避免 feature 之间横向 import。
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
    this.bordered = true,
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

  /// 是否画虚线边框。默认画（设置页等列表区需要框定范围）；
  /// 页面级空态（如「在线」未导入源）不画，避免整页只剩一个空心框。
  final bool bordered;

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
    final box = Container(
      constraints: BoxConstraints(minHeight: compact ? 104 : 220),
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20, vertical: compact ? 12 : 64),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 230 : 420),
        child: content,
      ),
    );
    if (!bordered) return box;
    return CustomPaint(
      painter: _DashedBorderPainter(color: palette.line2, radius: AppMetrics.radiusCard),
      child: box,
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
