import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/buttons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';

/// 队列空态（重设计稿 queue.html `.qt-empty` 1:1）：
/// 魔法阵（120、26s 慢旋、CustomPainter 按设计稿 SVG 逐元素绘制）+
/// 标题 14/700 + 说明 10.5 + 双引导按钮（28 高）。
class QueueEmpty extends StatefulWidget {
  const QueueEmpty({super.key});

  @override
  State<QueueEmpty> createState() => _QueueEmptyState();
}

class _QueueEmptyState extends State<QueueEmpty> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 26))..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _spin,
            child: CustomPaint(
              size: const Size(120, 120),
              painter: _MagicCirclePainter(color: palette.accent),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.queueEmptyTitle,
            style: TextStyle(fontSize: AppFont.px14, fontWeight: FontWeight.w700, color: palette.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.queueEmptyDesc,
            style: TextStyle(fontSize: AppFont.px10_5, color: palette.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: l10n.queueGoSettings,
                onTap: () => context.go('/settings'),
                variant: AppButtonVariant.primary,
                height: 28,
                horizontalPadding: 14,
              ),
              const SizedBox(width: 10),
              AppButton(
                label: l10n.queueSourceLocal,
                onTap: () => context.go('/manga/drop'),
                variant: AppButtonVariant.ghost,
                border: true,
                height: 28,
                horizontalPadding: 14,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 魔法阵画笔：设计稿 SVG 逐元素 1:1（viewBox 100 → 120 缩放 1.2）：
/// 外圈 r46(.5) / 虚线圈 r34 4-5(.6) / 内圈 r20 / 十字+对角线(.25) / 上三角(.5) / 下三角(.3)。
class _MagicCirclePainter extends CustomPainter {
  const _MagicCirclePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * s
      ..color = color;

    void circle(double r, double alpha) {
      canvas.drawCircle(c, r * s, paint..color = color.withValues(alpha: alpha));
    }

    circle(46, 0.5);
    // 虚线圈：r34，dash 4 / gap 5（沿圆周分段画弧）。
    final dashed = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * s
      ..color = color.withValues(alpha: 0.6);
    const dash = 4.0;
    final r = 34 * s;
    final circumference = 2 * pi * r;
    final seg = 2 * pi / (circumference / (dash + 5.0));
    for (var a = 0.0; a < 2 * pi; a += seg) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, dash / r, false, dashed);
    }
    circle(20, 1);

    // 十字 + 对角线（α .25）：M50 8v84 M8 50h84 M20 20l60 60 M80 20L20 80。
    final cross = Paint()
      ..strokeWidth = 1 * s
      ..color = color.withValues(alpha: 0.25);
    canvas.drawLine(Offset(c.dx, 8 * s), Offset(c.dx, 92 * s), cross);
    canvas.drawLine(Offset(8 * s, c.dy), Offset(92 * s, c.dy), cross);
    canvas.drawLine(Offset(20 * s, 20 * s), Offset(80 * s, 80 * s), cross);
    canvas.drawLine(Offset(80 * s, 20 * s), Offset(20 * s, 80 * s), cross);

    // 上三角（50,16 81,68 19,68 / .5）与下三角（50,84 19,32 81,32 / .3）。
    final triUp = Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: 0.5);
    canvas.drawPath(
      Path()
        ..moveTo(50 * s, 16 * s)
        ..lineTo(81 * s, 68 * s)
        ..lineTo(19 * s, 68 * s)
        ..close(),
      triUp,
    );
    final triDown = Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: 0.3);
    canvas.drawPath(
      Path()
        ..moveTo(50 * s, 84 * s)
        ..lineTo(19 * s, 32 * s)
        ..lineTo(81 * s, 32 * s)
        ..close(),
      triDown,
    );
  }

  @override
  bool shouldRepaint(covariant _MagicCirclePainter oldDelegate) => oldDelegate.color != color;
}
