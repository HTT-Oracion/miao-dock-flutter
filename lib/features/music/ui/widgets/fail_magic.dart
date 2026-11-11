import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/buttons.dart';

/// 页面级失败态「断线唱片魔法阵」（设计稿 N28）：
/// 外环虚线缓转、中环刻度反向转、中心唱片缺口 + 断开的波形；
/// 给出失败原因 / 上次同步 / 可播数量与三个出口（重试 / 切本地 / 看服务状态）。
/// 重试时魔法阵加速旋转 1.1s（与设计稿一致），失败不清空已有内容。
class FailMagicCircle extends StatefulWidget {
  const FailMagicCircle({
    super.key,
    required this.reason,
    required this.lastSyncLabel,
    required this.queueHint,
    required this.retryLabel,
    required this.onRetry,
    this.switchLocalLabel,
    this.onSwitchLocal,
    this.viewStatusLabel,
    this.onViewStatus,
  });

  /// 失败原因（ARB 映射后的文案）。
  final String reason;
  final String lastSyncLabel;
  final String queueHint;
  final String retryLabel;
  final VoidCallback onRetry;
  final String? switchLocalLabel;
  final VoidCallback? onSwitchLocal;
  final String? viewStatusLabel;
  final VoidCallback? onViewStatus;

  @override
  State<FailMagicCircle> createState() => _FailMagicCircleState();
}

class _FailMagicCircleState extends State<FailMagicCircle> with TickerProviderStateMixin {
  late final AnimationController _outer = AnimationController(vsync: this, duration: const Duration(seconds: 22))
    ..repeat();
  late final AnimationController _inner = AnimationController(vsync: this, duration: const Duration(seconds: 14))
    ..repeat();
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void dispose() {
    _outer.dispose();
    _inner.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _retry() {
    _burst.forward(from: 0).whenComplete(() {});
    widget.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // N34：系统「减少动态效果」时不再转动（原地静止），只保留颜色/透明度变化。
    final reduce = context.reduceMotion;
    if (reduce) {
      _outer.stop();
      _inner.stop();
    } else {
      if (!_outer.isAnimating) _outer.repeat();
      if (!_inner.isAnimating) _inner.repeat();
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 148,
            height: 148,
            child: AnimatedBuilder(
              animation: Listenable.merge([_outer, _inner, _burst]),
              builder: (context, _) {
                final speedUp = 1.0 + _burst.value * 8;
                return CustomPaint(
                  painter: _MagicPainter(
                    outer: (_outer.value * speedUp) % 1,
                    inner: (1 - (_inner.value * speedUp) % 1),
                    bad: palette.bad,
                    line2: palette.line2,
                    ink2: palette.ink2,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Text(
            widget.reason,
            style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w600, color: palette.ink),
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.lastSyncLabel} · ${widget.queueHint}',
            style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(label: widget.retryLabel, variant: AppButtonVariant.primary, onTap: _retry),
              if (widget.onSwitchLocal != null) ...[
                const SizedBox(width: 8),
                AppButton(
                  label: widget.switchLocalLabel ?? '',
                  variant: AppButtonVariant.ghost,
                  onTap: widget.onSwitchLocal,
                ),
              ],
              if (widget.onViewStatus != null) ...[
                const SizedBox(width: 8),
                AppButton(
                  label: widget.viewStatusLabel ?? '',
                  variant: AppButtonVariant.ghost,
                  onTap: widget.onViewStatus,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MagicPainter extends CustomPainter {
  const _MagicPainter({
    required this.outer,
    required this.inner,
    required this.bad,
    required this.line2,
    required this.ink2,
  });

  final double outer;
  final double inner;
  final Color bad;
  final Color line2;
  final Color ink2;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // 外环：虚线圆，顺时针缓转（红）
    final dash = Paint()
      ..color = bad
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dashPath = Path();
    const segments = 24;
    for (var i = 0; i < segments; i++) {
      final a0 = (outer + i / segments) * 2 * math.pi;
      final a1 = a0 + (2 * math.pi / segments) * 0.55;
      dashPath.moveTo(c.dx + math.cos(a0) * (r - 2), c.dy + math.sin(a0) * (r - 2));
      dashPath.arcToPoint(
        Offset(c.dx + math.cos(a1) * (r - 2), c.dy + math.sin(a1) * (r - 2)),
        radius: Radius.circular(r - 2),
        largeArc: false,
      );
    }
    canvas.drawPath(dashPath, dash);

    // 中环：刻度，反向转
    final ticks = Paint()
      ..color = line2
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 36; i++) {
      final a = (inner + i / 36) * 2 * math.pi;
      final r0 = r * 0.72;
      final r1 = r * (i % 3 == 0 ? 0.80 : 0.76);
      canvas.drawLine(
        Offset(c.dx + math.cos(a) * r0, c.dy + math.sin(a) * r0),
        Offset(c.dx + math.cos(a) * r1, c.dy + math.sin(a) * r1),
        ticks,
      );
    }

    // 中心唱片：深底 + 缺口 + 断开波形
    canvas.drawCircle(c, r * 0.52, Paint()..color = line2.withValues(alpha: 0.35));
    final notch = Paint()
      ..color = bad
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    // 唱片缺口：右侧 40° 缺口弧
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.52),
      -0.35,
      2 * math.pi - 0.7,
      false,
      Paint()
        ..color = ink2.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // 断开的波形：两段错位的折线
    final wave = Path()
      ..moveTo(c.dx - r * 0.34, c.dy)
      ..lineTo(c.dx - r * 0.22, c.dy - 7)
      ..lineTo(c.dx - r * 0.12, c.dy + 6)
      ..lineTo(c.dx - r * 0.04, c.dy);
    canvas.drawPath(wave, notch);
    final wave2 = Path()
      ..moveTo(c.dx + r * 0.30, c.dy)
      ..lineTo(c.dx + r * 0.18, c.dy - 7);
    canvas.drawPath(wave2, notch);
  }

  @override
  bool shouldRepaint(covariant _MagicPainter old) => old.outer != outer || old.inner != inner;
}
