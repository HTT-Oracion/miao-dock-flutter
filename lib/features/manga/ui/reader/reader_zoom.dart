import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/buttons.dart';

/// 桌面阅读器缩放状态（D-164）。
///
/// 变换语义与设计稿 `desktop.html` 的 `applyView(z, off)` 一致：
/// 屏幕坐标 = 中心 + off + (页内坐标 − 中心) × scale —— 即 [offset] 是
/// **缩放后的屏幕像素平移**，[scale] 以舞台中心为原点。
///
/// 为什么不用 [InteractiveViewer]：它按 `boundaryRect` 钳制缩放，子件被约束成
/// 视口尺寸时**最小只能 100%**（`_matrixScale` 里 `viewport/boundary` 那一项），
/// 设计稿要的 50%（调节器向下三档）根本到不了。
class ReaderZoom extends ChangeNotifier {
  ReaderZoom({this.minScale = 0.5, this.maxScale = 2.0});

  final double minScale;
  final double maxScale;

  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _viewport = Size.zero;

  double get scale => _scale;
  Offset get offset => _offset;
  int get percent => (_scale * 100).round();

  /// 是否处于放大态：翻页手势与滚轮语义在这里分叉（放大态滚轮 = 平移）。
  bool get zoomed => _scale > 1.0001;

  bool get atMin => _scale <= minScale + 0.0001;
  bool get atMax => _scale >= maxScale - 0.0001;

  /// 舞台尺寸：由 [ZoomablePage] 在布局阶段写入，只用于位移钳制（不通知）。
  set viewport(Size value) => _viewport = value;

  Offset get _center => Offset(_viewport.width / 2, _viewport.height / 2);

  /// 翻页 / 换话时归位（用户口径：翻页后调节自动回到 100%）。
  void reset() => _apply(1, Offset.zero);

  /// 顶栏调节器：25% 一档，锚点 = 舞台中心（设计稿 `stepZoom`）。
  void step(int dir) {
    final next = ((_scale * 100) / 25).round() + dir;
    _apply(next * 25 / 100, null);
  }

  /// 以 [focal]（舞台本地坐标）为锚点缩放，供 Ctrl/⌘+滚轮与触控板捏合使用：
  /// `off' = a − (a − off) × k`（a = 锚点相对中心，k = 新/旧比例）。
  void scaleAt(Offset focal, double factor) {
    final next = (_scale * factor).clamp(minScale, maxScale);
    if ((next - _scale).abs() < 0.0001) return;
    final anchor = focal - _center;
    final k = next / _scale;
    _apply(next, anchor - (anchor - _offset) * k);
  }

  /// 手势帧：把「起点焦距 / 起点比例」与当前焦距、当前捏合比例换算成一次变换。
  ///
  /// 一条公式同时覆盖捏合与拖动 —— 单指时 `spanScale == 1`，退化为平移。
  void gestureTo({
    required Offset startFocal,
    required double startScale,
    required Offset startOffset,
    required Offset focal,
    required double spanScale,
  }) {
    final target = (startScale * spanScale).clamp(minScale, maxScale);
    if (target <= 1) {
      _apply(1, Offset.zero);
      return;
    }
    // 起点焦距下方的那一点在页内的位置（相对中心、未缩放）。
    final scene = (startFocal - _center - startOffset) / startScale;
    _apply(target, (focal - _center) - scene * target);
  }

  /// 放大态平移（滚轮 / 拖动）。
  void panBy(Offset delta) {
    if (!zoomed) return;
    _apply(_scale, _offset + delta);
  }

  /// [offset] 为 null 表示「以中心为锚点」（调节器步进）。
  void _apply(double scale, Offset? offset) {
    final next = scale.clamp(minScale, maxScale);
    final k = next / _scale;
    final nextOffset = next <= 1 ? Offset.zero : (offset ?? _offset * k);
    if ((next - _scale).abs() < 0.0001 && nextOffset == _offset) return;
    _scale = next;
    _offset = nextOffset;
    _clampOffset();
    notifyListeners();
  }

  void _clampOffset() {
    if (_scale <= 1) {
      _offset = Offset.zero;
      return;
    }
    if (_viewport.isEmpty) return;
    final maxX = _viewport.width * (_scale - 1) / 2;
    final maxY = _viewport.height * (_scale - 1) / 2;
    _offset = Offset(_offset.dx.clamp(-maxX, maxX), _offset.dy.clamp(-maxY, maxY));
  }
}

/// 桌面舞台页：**放大态平移** + 单击呼出工具栏。
///
/// 🔴 这里**不挂 `onScale*`**：ScaleGestureRecognizer 会把触控板的
/// `PointerPanZoom` 一并吃掉，导致 PageView 收不到横滑手势 ——
/// 表现就是「macOS 触控板左右滑动翻页突然失效」。
/// 桌面真正的缩放入口是 Ctrl/⌘+滚轮、`+/-`、顶栏调节器，
/// 以及舞台层 `Listener.onPointerPanZoom*` 处理的触控板捏合。
class ZoomablePage extends StatefulWidget {
  const ZoomablePage({super.key, required this.zoom, required this.child, this.onTap});

  final ReaderZoom zoom;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<ZoomablePage> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        widget.zoom.viewport = box.biggest;
        return ListenableBuilder(
          listenable: widget.zoom,
          builder: (context, child) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            // 只在放大态接拖动（那时 PageView 已关滚动，不会抢）；
            // 未放大不注册 pan，把拖拽与触控板横扫留给 PageView。
            onPanUpdate: widget.zoom.zoomed ? (d) => widget.zoom.panBy(d.delta) : null,
            child: AnimatedBuilder(
              animation: widget.zoom,
              builder: (context, child) => Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translateByDouble(widget.zoom.offset.dx, widget.zoom.offset.dy, 0, 1)
                  ..scaleByDouble(widget.zoom.scale, widget.zoom.scale, 1, 1),
                child: child,
              ),
              child: child,
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// 移动端舞台页：双指捏合缩放（[InteractiveViewer]），点按/双击都不放大。
class PinchPage extends StatelessWidget {
  const PinchPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => InteractiveViewer(maxScale: 5, child: child);
}

/// 顶栏缩放调节器（设计稿 `.zoomchip`）：`− / 100% / ＋`，25% 步进。
class ZoomChip extends StatelessWidget {
  const ZoomChip({super.key, required this.zoom});

  final ReaderZoom zoom;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: zoom,
      builder: (context, _) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.line2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChipButton(
              icon: LucideIcons.minus,
              tooltip: l10n.readerZoomOut,
              onTap: zoom.atMin ? null : () => zoom.step(-1),
            ),
            SizedBox(
              width: 42,
              child: Text(
                l10n.readerZoomPercent(zoom.percent),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppFont.px11,
                  color: palette.ink2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _ChipButton(
              icon: LucideIcons.plus,
              tooltip: l10n.readerZoomIn,
              onTap: zoom.atMax ? null : () => zoom.step(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 22,
          height: 22,
          child: Icon(icon, size: 13, color: onTap == null ? palette.line2 : palette.ink2),
        ),
      ),
    );
  }
}

/// 缩放 OSD（设计稿 `.zosd`）：顶栏隐藏时捏合也有百分比反馈，800ms 后淡出。
class ZoomOsd extends StatefulWidget {
  const ZoomOsd({super.key, required this.zoom});

  final ReaderZoom zoom;

  @override
  State<ZoomOsd> createState() => _ZoomOsdState();
}

class _ZoomOsdState extends State<ZoomOsd> {
  bool _show = false;
  int _last = 100;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _last = widget.zoom.percent;
    widget.zoom.addListener(_onZoom);
  }

  @override
  void dispose() {
    widget.zoom.removeListener(_onZoom);
    _timer?.cancel();
    super.dispose();
  }

  void _onZoom() {
    final pct = widget.zoom.percent;
    if (pct == _last) return;
    _last = pct;
    if (!_show) setState(() => _show = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _show = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _show ? 1 : 0,
        duration: AppMotion.fast,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xC70A0C0F),
            borderRadius: BorderRadius.circular(kPillRadius),
            border: Border.all(color: const Color(0xFF313A45)),
          ),
          child: Text(
            l10n.readerZoomPercent(_last),
            style: TextStyle(
              fontSize: AppFont.px12,
              color: Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
