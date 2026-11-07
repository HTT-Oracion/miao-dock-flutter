import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';

/// 页码滑条（设计稿 `.rslider`）：6px 轨道 + 22px 拇指 + 拖动页码气泡 + 竖拖微调。
///
/// 桌面顶栏与移动端底栏共用同一颗：两端的手感必须一致，
/// 各写一份的结果是「手机能竖拖微调、桌面不能」。

/// 页码滑条（设计稿 `.rslider`）：6px 轨道 + 22px 拇指 + 拖动气泡 + 竖拖微调。
class PageSlider extends StatefulWidget {
  const PageSlider({super.key, required this.value, required this.count, required this.onChanged});

  /// 0 基页码。
  final int value;
  final int count;
  final ValueChanged<int> onChanged;

  @override
  State<PageSlider> createState() => _PageSliderState();
}

class _PageSliderState extends State<PageSlider> {
  static const double _thumb = 22;
  static const double _track = 6;

  bool _dragging = false;
  double _dyAcc = 0;
  double _width = 0;

  int _pageAt(double dx) {
    final span = _width - _thumb;
    if (span <= 0 || widget.count <= 1) return 0;
    final p = ((dx - _thumb / 2) / span).clamp(0.0, 1.0);
    return (p * (widget.count - 1)).round().clamp(0, widget.count - 1);
  }

  void _emit(int page) {
    if (page != widget.value) widget.onChanged(page);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final fraction = widget.count <= 1 ? 0.0 : widget.value / (widget.count - 1);
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth;
        final thumbLeft = fraction * (box.maxWidth - _thumb);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            setState(() {
              _dragging = true;
              _dyAcc = 0;
            });
            _emit(_pageAt(d.localPosition.dx));
          },
          onHorizontalDragUpdate: (d) => _emit(_pageAt(d.localPosition.dx)),
          onHorizontalDragEnd: (_) => setState(() => _dragging = false),
          onHorizontalDragCancel: () => setState(() => _dragging = false),
          onTapDown: (d) => _emit(_pageAt(d.localPosition.dx)),
          // 竖拖微调：每 22px 一格（拇指粗，横竖都不打架）。
          onVerticalDragStart: (_) => _dyAcc = 0,
          onVerticalDragUpdate: (d) {
            _dyAcc += d.delta.dy;
            while (_dyAcc.abs() >= 22) {
              final step = _dyAcc.isNegative ? -1 : 1;
              _dyAcc -= step * 22;
              _emit((widget.value + step).clamp(0, widget.count - 1));
            }
          },
          child: SizedBox(
            height: 26,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // 轨道
                Positioned(
                  left: _thumb / 2,
                  right: _thumb / 2,
                  child: Container(
                    height: _track,
                    decoration: BoxDecoration(
                      color: palette.progressTrack,
                      borderRadius: BorderRadius.circular(_track / 2),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: fraction,
                      child: Container(
                        decoration: BoxDecoration(color: palette.acc, borderRadius: BorderRadius.circular(_track / 2)),
                      ),
                    ),
                  ),
                ),
                // 拇指
                Positioned(
                  left: thumbLeft,
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                      color: palette.acc,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: palette.shadow.withValues(alpha: 0.45), blurRadius: 8)],
                    ),
                  ),
                ),
                // 拖动气泡
                if (_dragging)
                  Positioned(
                    left: (thumbLeft + _thumb / 2 - 34).clamp(0.0, (box.maxWidth - 68).clamp(0.0, double.infinity)),
                    top: -22,
                    child: Container(
                      width: 68,
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(color: palette.acc, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        l10n.readerPage(widget.value + 1, widget.count),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppFont.px10,
                          fontWeight: FontWeight.w700,
                          color: palette.onAcc,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
