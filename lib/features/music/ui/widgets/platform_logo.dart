import 'package:flutter/material.dart';

import '../../domain/music_models.dart';

/// 平台品牌圆底 logo（设计稿 N40 / icons.js `platSvg` 最终稿）：
/// 扁平圆底 + 稍浅品牌纯色 + 白色识别符号，无渐变、无高光、无投影。
///
/// 符号几何与设计稿 SVG 一比一（24 视框）：网易云音符+云卷、酷狗 K、
/// QQ 音乐音符、咪咕 M。未知平台回退灰圆底 + 音符。
class PlatformLogo extends StatelessWidget {
  const PlatformLogo({super.key, required this.platform, this.size = 18});

  final MusicPlatform platform;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = platformBrands[platform];
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BrandLogoPainter(brand: brand)),
    );
  }
}

class _BrandLogoPainter extends CustomPainter {
  const _BrandLogoPainter({required this.brand});

  final PlatformBrand? brand;

  static const _scale = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _scale;
    final glyph = brand?.glyph;
    // 圆底
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      Paint()..color = brand?.color ?? const Color(0xFF858B98),
    );
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void path(List<List<double>> pts, {bool close = true}) {
      final p = Path()..moveTo(pts[0][0] * s, pts[0][1] * s);
      for (final pt in pts.skip(1)) {
        p.lineTo(pt[0] * s, pt[1] * s);
      }
      if (close) p.close();
      canvas.drawPath(p, white);
    }

    void dot(double cx, double cy, double r) => canvas.drawCircle(Offset(cx * s, cy * s), r * s, white);

    void bar(double x, double y, double w, double h, {double rx = .9}) => canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x * s, y * s, w * s, h * s), Radius.circular(rx * s)),
      white,
    );

    switch (glyph) {
      case BrandGlyph.noteCloud:
        // 音符（符头 + 符杆 + 内卷符尾）
        dot(9.2, 16.4, 3);
        bar(11.2, 5.8, 1.8, 10.9);
        final tail = Path()
          ..moveTo(12.6 * s, 6.9 * s)
          ..cubicTo(14.9 * s, 7.1 * s, 16.6 * s, 8.2 * s, 17.6 * s, 10.1 * s)
          ..cubicTo(18.0 * s, 10.9 * s, 17.7 * s, 11.8 * s, 16.8 * s, 12.1 * s)
          ..cubicTo(16.1 * s, 12.3 * s, 15.4 * s, 12.0 * s, 15.1 * s, 11.3 * s)
          ..cubicTo(14.6 * s, 10.2 * s, 13.7 * s, 9.5 * s, 12.4 * s, 9.3 * s)
          ..close();
        canvas.drawPath(tail, white);
      case BrandGlyph.letterK:
        path([
          [7.3, 6.4],
          [9.7, 6.4],
          [9.7, 17.6],
          [7.3, 17.6],
        ]);
        path([
          [10.7, 12.9],
          [15.2, 6.4],
          [18.1, 6.4],
          [13.4, 12.7],
          [18.3, 17.6],
          [15.2, 17.6],
        ]);
      case BrandGlyph.note:
        dot(9.6, 16.5, 3.1);
        bar(11.7, 5.6, 1.9, 11.1);
        final flag = Path()
          ..moveTo(13.6 * s, 6.2 * s)
          ..cubicTo(16.1 * s, 6.7 * s, 17.8 * s, 8.1 * s, 18.6 * s, 10.2 * s)
          ..lineTo(16.6 * s, 11.0 * s)
          ..cubicTo(16.0 * s, 9.4 * s, 14.9 * s, 8.4 * s, 13.4 * s, 8.0 * s)
          ..close();
        canvas.drawPath(flag, white);
      case BrandGlyph.letterM:
        final m = Path()
          ..moveTo(6.8 * s, 17.4 * s)
          ..lineTo(6.8 * s, 7.3 * s)
          ..cubicTo(6.8 * s, 6.5 * s, 7.7 * s, 6.1 * s, 8.3 * s, 6.6 * s)
          ..lineTo(12 * s, 10 * s)
          ..lineTo(15.7 * s, 6.6 * s)
          ..cubicTo(16.3 * s, 6.1 * s, 17.2 * s, 6.5 * s, 17.2 * s, 7.3 * s)
          ..lineTo(17.2 * s, 17.4 * s)
          ..lineTo(14.9 * s, 17.4 * s)
          ..lineTo(14.9 * s, 11.4 * s)
          ..lineTo(12.7 * s, 13.4 * s)
          ..cubicTo(12.3 * s, 13.8 * s, 11.7 * s, 13.8 * s, 11.3 * s, 13.4 * s)
          ..lineTo(9.1 * s, 11.4 * s)
          ..lineTo(9.1 * s, 17.4 * s)
          ..close();
        canvas.drawPath(m, white);
      case null:
        dot(12, 12, 7.2 * 0.86);
    }
  }

  @override
  bool shouldRepaint(covariant _BrandLogoPainter old) => old.brand != brand;
}
