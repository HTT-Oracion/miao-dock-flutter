import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/widgets/buttons.dart';

/// 空态插画（设计稿 `core.js emptyArtHTML`）：单环 + 音符轨道。
///
/// 与失败态（断线唱片魔法阵，带旋转动画）严格分开：空态**不做动画循环**，
/// 只用静止的单环与两道音符轨道表达「这里还没有内容」（N30）。
class MusicEmptyArt extends StatelessWidget {
  const MusicEmptyArt({super.key, this.size = 132});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _EmptyArtPainter(mut: palette.mut, acc: palette.acc),
      ),
    );
  }
}

class _EmptyArtPainter extends CustomPainter {
  const _EmptyArtPainter({required this.mut, required this.acc});

  final Color mut;
  final Color acc;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 160;
    final c = Offset(80 * s, 80 * s);
    // 外环：细虚线，静态（空态不转）。
    final ring = Paint()
      ..color = mut.withValues(alpha: 0.26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * s;
    const dashes = 40;
    for (var i = 0; i < dashes; i++) {
      final a0 = i * 2 * math.pi / dashes;
      final a1 = a0 + (2 * math.pi / dashes) * 0.22;
      canvas.drawArc(Rect.fromCircle(center: c, radius: 70 * s), a0, a1 - a0, false, ring);
    }
    final inner = Paint()
      ..color = mut.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * s;
    canvas.drawCircle(c, 52 * s, inner);

    // 音符轨道：两个符头 + 符杆 + 横梁（设计稿 `.art` 的 acc 线条）。
    final note = Paint()
      ..color = acc.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * s
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = acc.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(65 * s, 92 * s), 7 * s, note);
    final stem = Path()
      ..moveTo(72 * s, 92 * s)
      ..lineTo(72 * s, 58 * s)
      ..lineTo(94 * s, 53 * s)
      ..lineTo(94 * s, 83 * s);
    canvas.drawPath(stem, note);
    canvas.drawCircle(Offset(87 * s, 83 * s), 7 * s, note);
    canvas.drawCircle(c, 2.4 * s, fill);
  }

  @override
  bool shouldRepaint(covariant _EmptyArtPainter old) => old.mut != mut || old.acc != acc;
}

/// 空态块（设计稿 `.state` / `.m-state`）：插画 + 标题 + 说明 + 一个明确动作。
///
/// 「没有匹配」与「还没有内容」用不同文案由调用方给（N30 边界）；
/// 失败态不要用本件 —— 它有原因和重试，走 [FailMagicCircle]。
class MusicEmptyState extends StatelessWidget {
  const MusicEmptyState({
    super.key,
    required this.title,
    required this.description,
    this.meta,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.mobileStacked = false,
  });

  final String title;
  final String description;

  /// 补充说明（格式 / 限额这类小字）。
  final String? meta;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  /// 移动端：按钮整宽竖排（设计稿 `.m-state .a`），拇指可达。
  final bool mobileStacked;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final mobile = mobileStacked;
    final buttons = <Widget>[
      if (actionLabel != null)
        AppButton(
          label: actionLabel!,
          icon: LucideIcons.filePlus,
          variant: AppButtonVariant.primary,
          height: mobile ? 38 : 30,
          width: mobile ? double.infinity : null,
          fontSize: AppFont.px11_5,
          onTap: onAction,
        ),
      if (secondaryActionLabel != null)
        AppButton(
          label: secondaryActionLabel!,
          icon: LucideIcons.folderPlus,
          variant: AppButtonVariant.ghost,
          height: mobile ? 38 : 30,
          width: mobile ? double.infinity : null,
          fontSize: AppFont.px11_5,
          onTap: onSecondaryAction,
        ),
    ];
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: mobile ? 22 : 20, vertical: mobile ? 26 : 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MusicEmptyArt(size: mobile ? 132 : 118),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: mobile ? AppFont.px15 : AppFont.px14,
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: mobile ? AppFont.px12 : AppFont.px11_5, height: 1.7, color: palette.ink2),
              ),
            ),
            if (buttons.isNotEmpty) ...[
              const SizedBox(height: 14),
              if (mobile)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Column(
                    children: [
                      for (final (i, b) in buttons.indexed) ...[if (i > 0) const SizedBox(height: 8), b],
                    ],
                  ),
                )
              else
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: buttons),
            ],
            if (meta != null) ...[
              const SizedBox(height: 10),
              Text(
                meta!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
