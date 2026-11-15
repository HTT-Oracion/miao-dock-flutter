import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import 'buttons.dart';

/// 数据源面板的「本地导入」虚线拖拽框。
///
/// 漫画源与音乐源**共用同一实现**：图标、内外距、字号、按钮变体与排布全部一致，
/// 只有文案由调用方传入 —— 这正是「音乐源像素级还原漫画源」的落点。
class SourceImportBox extends StatelessWidget {
  const SourceImportBox({
    super.key,
    required this.importing,
    required this.mobile,
    required this.onImport,
    required this.onOpenDir,
    required this.title,
    required this.description,
    required this.descriptionMobile,
    required this.steps,
    required this.importLabel,
    required this.importLabelMobile,
    required this.openDirLabel,
    required this.importingLabel,
    required this.waitLabel,
  });

  final bool importing;
  final bool mobile;
  final VoidCallback onImport;
  final VoidCallback? onOpenDir;

  final String title;
  final String description;
  final String descriptionMobile;
  final String steps;
  final String importLabel;
  final String importLabelMobile;
  final String openDirLabel;
  final String importingLabel;
  final String waitLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return CustomPaint(
      painter: _ImportDashedPainter(color: palette.line2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
        decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Icon(LucideIcons.upload, size: 26, color: palette.acc),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.ink),
            ),
            const SizedBox(height: 4),
            Text(
              mobile ? descriptionMobile : '$description\n$steps',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppFont.px10_5, height: 1.6, color: palette.mut),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                AppButton(
                  label: mobile ? importLabelMobile : importLabel,
                  icon: LucideIcons.plus,
                  onTap: importing ? null : onImport,
                  variant: AppButtonVariant.primary,
                  loading: importing,
                  height: mobile ? 44 : 32,
                  horizontalPadding: 13,
                  fontSize: AppFont.px12,
                  fontWeight: FontWeight.w600,
                ),
                if (onOpenDir != null)
                  AppButton(
                    label: openDirLabel,
                    icon: LucideIcons.folder,
                    onTap: onOpenDir,
                    variant: AppButtonVariant.ghost,
                    height: 32,
                    horizontalPadding: 13,
                    fontSize: AppFont.px12,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              importing ? importingLabel : waitLabel,
              style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportDashedPainter extends CustomPainter {
  const _ImportDashedPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 4;
      }
    }
  }

  @override
  bool shouldRepaint(_ImportDashedPainter oldDelegate) => oldDelegate.color != color;
}
