import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import 'reader_mobile.dart';
import 'reader_prefs.dart';

/// 移动端阅读舞台（重设计稿 mobile.html §手势状态机）：
///
/// 一条 [Listener]（原始指针，不进竞技场）+ 一层 [GestureDetector]（scale 手势）
/// 组成状态机 `idle → turn | bright | pan | pinch | loupe`，五种相位互斥：
///   · 未放大：横向拖拽 = 跟手翻页（1:1 跟指，松手按位移/速度提交或回弹）；
///   · 放大态：拖拽 = 平移（钳在页边界内），点按只呼出工具栏、不翻页；
///   · 左缘 36px：竖滑 = 亮度（横滑仍可翻页，避免把边缘翻页的手感吃掉）；
///   · 双击：1× ⇄ 2.5×，锚点 = 双击处；已放大时双击 = 还原；
///   · 长按 250ms：放大镜 1.75×，抬起还原（移动即取消）。
///
/// 为什么不用 `PageView` + `InteractiveViewer`：两者的手势竞技会互相抢
/// —— 放大态的单指平移会被 PageView 判成翻页，而 PageView 的翻页拖动会被
/// InteractiveViewer 判成平移。要让「放大后的操作正常生效」，相位必须自己定。
class ReaderStage extends StatefulWidget {
  const ReaderStage({
    super.key,
    required this.pageCount,
    required this.index,
    required this.showOriginal,
    required this.prefs,
    required this.pageBuilder,
    required this.onPage,
    required this.onToggleBar,
    required this.onBrightnessDelta,
    required this.onEndReached,
    this.isTranslated,
    this.showPageBadge = false,
  });

  final int pageCount;

  /// 0 基当前页。
  final int index;
  final bool showOriginal;
  final ReaderPrefs prefs;

  /// 构建某一页的视觉内容；页码从 1 开始。
  final Widget Function(BuildContext context, int seq, bool showOriginal) pageBuilder;

  /// 该页是否已有译文；仅在 [showPageBadge] 为 true 时参与页角标记。
  final bool Function(int seq)? isTranslated;
  final bool showPageBadge;

  /// 提交翻页（绝对页码，0 基）。
  final ValueChanged<int> onPage;
  final VoidCallback onToggleBar;
  final ValueChanged<double> onBrightnessDelta;

  /// 末页继续往后拖（出章末衔接卡）。
  final VoidCallback onEndReached;

  @override
  State<ReaderStage> createState() => _ReaderStageState();
}

enum _Phase { none, turn, bright, pan, pinch, blocked }

class _ReaderStageState extends State<ReaderStage> with TickerProviderStateMixin {
  static const double _doubleTapZoom = 2.5;
  static const double _loupeZoom = 1.75;
  static const double _loupeRadius = 46;
  static const double _edge = 36;
  static const double _slop = 10;
  static const Duration _doubleTapWindow = Duration(milliseconds: 230);
  static const Duration _longPress = Duration(milliseconds: 250);

  // ── 缩放 ──
  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _size = Size.zero;

  late final AnimationController _zoomAnim;
  double _zFromScale = 1, _zToScale = 1;
  Offset _zFromOffset = Offset.zero, _zToOffset = Offset.zero;

  bool get _zoomed => _scale > 1.0001;

  // ── 拖拽翻页 ──
  late final AnimationController _pageAnim;
  double _dragDx = 0;
  bool _dragging = false;
  int _incoming = 0;
  int? _commitTo;
  double _animFrom = 0, _animTo = 0;

  // ── 手势相位 ──
  _Phase _phase = _Phase.none;
  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  Offset _downPos = Offset.zero;
  DateTime _downAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _moved = false;
  int _pointers = 0;

  // ── 放大镜 ──
  Offset? _loupe;
  Timer? _lpTimer;
  bool _lpFired = false;

  // ── 单击 / 双击 ──
  Timer? _tapTimer;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastTapPos = Offset.zero;

  @override
  void initState() {
    super.initState();
    _pageAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
      ..addListener(() {
        final v = Curves.easeOutCubic.transform(_pageAnim.value);
        setState(() => _dragDx = _animFrom + (_animTo - _animFrom) * v);
      })
      ..addStatusListener((s) {
        if (s != AnimationStatus.completed) return;
        final to = _commitTo;
        _commitTo = null;
        setState(() {
          _dragDx = 0;
          _dragging = false;
        });
        if (to != null) widget.onPage(to);
      });
    _zoomAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() {
        final v = Curves.easeOutCubic.transform(_zoomAnim.value);
        setState(() {
          _scale = _zFromScale + (_zToScale - _zFromScale) * v;
          _offset = Offset.lerp(_zFromOffset, _zToOffset, v) ?? Offset.zero;
        });
      });
  }

  @override
  void didUpdateWidget(covariant ReaderStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换页（滑条 / 换话 / 点按）→ 缩放归位，和桌面「翻页即归位」同口径。
    if (oldWidget.index != widget.index) {
      if (_zoomed) {
        _zoomAnim.stop();
        setState(() {
          _scale = 1;
          _offset = Offset.zero;
        });
      }
    }
  }

  @override
  void dispose() {
    _lpTimer?.cancel();
    _tapTimer?.cancel();
    _pageAnim.dispose();
    _zoomAnim.dispose();
    super.dispose();
  }

  Offset get _center => Offset(_size.width / 2, _size.height / 2);

  void _clampOffset() {
    if (_scale <= 1.0001) {
      _offset = Offset.zero;
      return;
    }
    final maxX = _size.width * (_scale - 1) / 2;
    final maxY = _size.height * (_scale - 1) / 2;
    _offset = Offset(_offset.dx.clamp(-maxX, maxX), _offset.dy.clamp(-maxY, maxY));
  }

  /// 以 [focal] 为锚点缩放到 [target]（设计稿 `o′ = a − (a−o)·k`）。
  Offset _offsetFor(Offset focal, double target) {
    final anchor = focal - _center;
    final k = target / _scale;
    return anchor - (anchor - _offset) * k;
  }

  void _animateZoom(double target, Offset offset) {
    _zFromScale = _scale;
    _zFromOffset = _offset;
    _zToScale = target;
    _zToOffset = offset;
    _clampTargetOffset(target, offset);
    _zoomAnim.forward(from: 0);
  }

  void _clampTargetOffset(double scale, Offset offset) {
    if (_size.isEmpty) return;
    if (scale <= 1.0001) {
      _zToOffset = Offset.zero;
      return;
    }
    final maxX = _size.width * (scale - 1) / 2;
    final maxY = _size.height * (scale - 1) / 2;
    _zToOffset = Offset(offset.dx.clamp(-maxX, maxX), offset.dy.clamp(-maxY, maxY));
  }

  // ────────────────────────── 指针（单击 / 双击 / 长按） ──────────────────────────

  void _onPointerDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers > 1) {
      // 第二根手指进来：单指语义全部作废（捏合接管）。
      _lpTimer?.cancel();
      _tapTimer?.cancel();
      setState(() {
        _loupe = null;
        _lpFired = false;
      });
      return;
    }
    _downPos = e.localPosition;
    _downAt = DateTime.now();
    _moved = false;
    _lpFired = false;
    _lpTimer?.cancel();
    _lpTimer = Timer(_longPress, () {
      if (!mounted || _moved || _pointers != 1) return;
      _lpFired = true;
      setState(() => _loupe = _downPos);
    });
  }

  void _onPointerMove(PointerMoveEvent e) {
    if ((e.localPosition - _downPos).distance > _slop && !_moved) {
      _moved = true;
      _lpTimer?.cancel();
      if (_loupe != null) setState(() => _loupe = null);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointers = _pointers > 0 ? _pointers - 1 : 0;
    _lpTimer?.cancel();
    final hadLoupe = _loupe != null;
    if (hadLoupe) setState(() => _loupe = null);
    // 长按触发过就只当放大镜：抬手不额外当点按。
    if (_lpFired || hadLoupe || _moved) return;
    final dt = DateTime.now().difference(_downAt);
    if (dt > const Duration(milliseconds: 400)) return;
    _handleTap(e.localPosition);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers = _pointers > 0 ? _pointers - 1 : 0;
    _lpTimer?.cancel();
    if (_loupe != null) setState(() => _loupe = null);
  }

  void _handleTap(Offset pos) {
    final now = DateTime.now();
    final isSecond =
        _tapTimer?.isActive == true &&
        now.difference(_lastTapAt) <= _doubleTapWindow &&
        (pos - _lastTapPos).distance < 48;
    if (isSecond) {
      _tapTimer?.cancel();
      _tapTimer = null;
      _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
      _handleDoubleTap(pos);
      return;
    }
    _lastTapAt = now;
    _lastTapPos = pos;
    // 单点动作延后一个双击窗口再执行：否则双击的第一下已经把页翻了。
    _tapTimer?.cancel();
    _tapTimer = Timer(_doubleTapWindow, () {
      if (mounted) _handleSingleTap(pos);
    });
  }

  void _handleDoubleTap(Offset pos) {
    if (_zoomed) {
      _animateZoom(1, Offset.zero);
      return;
    }
    final target = _doubleTapZoom;
    _animateZoom(target, _offsetFor(pos, target));
  }

  void _handleSingleTap(Offset pos) {
    if (_zoomed) {
      // 放大态：点按只呼出/收起工具栏，绝不翻页（否则平移时会误翻）。
      widget.onToggleBar();
      return;
    }
    final rel = pos.dx / _size.width;
    if (rel > 0.3 && rel < 0.7) {
      widget.onToggleBar();
      return;
    }
    if (!widget.prefs.tapTurn) return;
    final leftSide = rel <= 0.3;
    // RTL：左区 = 下一页。
    final forward = widget.prefs.rtl ? leftSide : !leftSide;
    _turn(forward ? 1 : -1);
  }

  /// 点按翻页（按设置里的动画档位收尾；拖拽跟手不经过这里）。
  void _turn(int dir) {
    final total = widget.pageCount;
    final target = widget.index + dir;
    if (target < 0) {
      _nudge(-1);
      return;
    }
    if (target >= total) {
      widget.onEndReached();
      return;
    }
    if (widget.prefs.turnAnim == ReaderTurnAnim.none) {
      widget.onPage(target);
      return;
    }
    _incoming = target;
    _commitTo = target;
    _animFrom = 0;
    _animTo = -dir * _size.width;
    setState(() => _dragging = true);
    _pageAnim.forward(from: 0);
  }

  /// 首末页轻推（设计稿 `nudge`：橡皮筋 3%）。
  void _nudge(int dir) {
    _animFrom = 0;
    _animTo = -dir * _size.width * 0.03;
    _commitTo = null;
    setState(() => _dragging = false);
    _pageAnim.forward(from: 0).then((_) {
      if (!mounted) return;
      _animFrom = _dragDx;
      _animTo = 0;
      _pageAnim.forward(from: 0);
    });
  }

  // ────────────────────────── scale 手势（翻页 / 亮度 / 平移 / 捏合） ──────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint;
    if (d.pointerCount >= 2) {
      _phase = _Phase.pinch;
      return;
    }
    // iOS 左缘 20px 让路给系统侧滑返回（设计稿标注项）。
    if (defaultTargetPlatform == TargetPlatform.iOS && d.localFocalPoint.dx < 20) {
      _phase = _Phase.blocked;
      return;
    }
    if (_zoomed) {
      _phase = _Phase.pan;
      return;
    }
    _phase = d.localFocalPoint.dx < _edge ? _Phase.bright : _Phase.turn;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_phase == _Phase.blocked) return;
    if (d.pointerCount >= 2) _phase = _Phase.pinch;
    switch (_phase) {
      case _Phase.pinch:
        final target = (_startScale * d.scale).clamp(1.0, _doubleTapZoom);
        if (target <= 1.0001) {
          if (_scale != 1 || _offset != Offset.zero) setState(() => _scale = 1);
          setState(() => _offset = Offset.zero);
          return;
        }
        final scene = (_startFocal - _center - _startOffset) / _startScale;
        var next = (d.localFocalPoint - _center) - scene * target;
        final maxX = _size.width * (target - 1) / 2;
        final maxY = _size.height * (target - 1) / 2;
        next = Offset(next.dx.clamp(-maxX, maxX), next.dy.clamp(-maxY, maxY));
        setState(() {
          _scale = target;
          _offset = next;
        });
      case _Phase.pan:
        setState(() {
          _offset += d.focalPointDelta;
          _clampOffset();
        });
      case _Phase.bright:
        // 竖滑优先；横滑立刻改判翻页，不把边缘翻页手感吃掉。
        if (d.focalPointDelta.dx.abs() > d.focalPointDelta.dy.abs()) {
          _phase = _Phase.turn;
          return;
        }
        widget.onBrightnessDelta(-d.focalPointDelta.dy / 260);
      case _Phase.turn:
        if (d.focalPointDelta.dx.abs() < d.focalPointDelta.dy.abs() * 0.6) return;
        _drag(d.focalPointDelta.dx);
      case _Phase.none:
      case _Phase.blocked:
        return;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_phase == _Phase.turn && _dragging) {
      _settle(d.velocity.pixelsPerSecond.dx);
    } else if (_phase == _Phase.pinch) {
      if (_scale <= 1.0001) {
        setState(() {
          _scale = 1;
          _offset = Offset.zero;
        });
      }
    }
    _phase = _Phase.none;
  }

  /// 跟手位移要**累加**：`focalPointDelta` 是「上一帧到这一帧」的增量，
  /// 真机一次滑动会吐几十帧、每帧几像素 —— 直接赋值等于永远停在几个像素，
  /// 进度过不了 28% 阈值，松手必然回弹（表现为「滑了没反应」）。
  void _drag(double delta) {
    if (_size.width <= 0) return;
    final total = widget.pageCount;
    final nextX = _dragDx + delta;
    // RTL：向右拖 = 下一页。
    final forward = widget.prefs.rtl ? nextX > 0 : nextX < 0;
    final candidate = forward ? widget.index + 1 : widget.index - 1;
    if (candidate < 0 || candidate >= total) {
      // 边界外：留 12% 橡皮筋，不再跟手到底。
      final limit = _size.width * 0.12;
      setState(() {
        _dragDx = nextX.clamp(-limit, limit);
        _dragging = true;
        _incoming = widget.index;
      });
      return;
    }
    setState(() {
      _dragDx = nextX;
      _dragging = true;
      _incoming = candidate;
    });
  }

  void _settle(double velocityX) {
    final w = _size.width;
    final progress = (_dragDx.abs() / w).clamp(0.0, 1.0);
    final forward = widget.prefs.rtl ? _dragDx > 0 : _dragDx < 0;
    final fast = velocityX.abs() > 700 && velocityX.sign == _dragDx.sign;
    final total = widget.pageCount;
    final target = widget.index + (forward ? 1 : -1);

    final passed = progress > 0.28 || fast;
    if (passed && target >= 0 && target < total) {
      _commitTo = target;
      _animFrom = _dragDx;
      _animTo = forward ? -w : w;
      _pageAnim.forward(from: 0);
      return;
    }
    // 末页继续往后拖 → 章末衔接卡。边界上位移被橡皮筋钳在 12%，
    // 所以「拉满过 11%」本身就是明确意图，不要求一定过 28%。
    final pastEdge = forward && target >= total && _dragDx.abs() >= w * 0.11;
    if (pastEdge) widget.onEndReached();
    _commitTo = null;
    _animFrom = _dragDx;
    _animTo = 0;
    _pageAnim.forward(from: 0);
  }

  // ────────────────────────── 渲染 ──────────────────────────

  Widget _page(int seq) {
    final untranslated = !widget.showOriginal && !(widget.isTranslated?.call(seq) ?? true);
    return Stack(
      children: [
        Positioned.fill(
          child: KeyedSubtree(
            key: ValueKey('reader-stage-page-$seq-${widget.showOriginal}'),
            child: widget.pageBuilder(context, seq, widget.showOriginal),
          ),
        ),
        if (widget.showPageBadge && untranslated) const Positioned(left: 14, top: 12, child: PageBadge()),
      ],
    );
  }

  Widget _zoomWrap(Widget child) => Transform(
    key: const Key('reader-zoom'),
    alignment: Alignment.center,
    transform: Matrix4.identity()
      ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
      ..scaleByDouble(_scale, _scale, 1, 1),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final bg = readerStageColor(widget.prefs.stageBg);
    return LayoutBuilder(
      builder: (context, box) {
        _size = box.biggest;
        return ColoredBox(
          color: bg,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: ClipRect(
                child: Stack(
                  children: [
                    // 跟手翻页时出现在旁边的下一页 / 上一页。
                    if (_dragging && _dragDx != 0 && _incoming != widget.index) Positioned.fill(child: _incomingPage()),
                    Positioned.fill(child: _zoomWrap(_page(widget.index + 1))),
                    if (_loupe != null) Positioned.fill(child: _loupeLayer()),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _incomingPage() {
    final w = _size.width;
    final fromRight = _dragDx < 0;
    final x = fromRight ? w + _dragDx : -w + _dragDx;
    if (widget.prefs.turnAnim == ReaderTurnAnim.fade) {
      final p = (_dragDx.abs() / w).clamp(0.0, 1.0);
      return Opacity(opacity: p, child: _page(_incoming + 1));
    }
    return Transform.translate(offset: Offset(x, 0), child: _page(_incoming + 1));
  }

  /// 放大镜：以按住点为锚把当前页放大 1.75×，只露出一个圆。
  Widget _loupeLayer() {
    final p = _loupe!;
    final align = Alignment(
      _size.width <= 0 ? 0 : (p.dx / _size.width) * 2 - 1,
      _size.height <= 0 ? 0 : (p.dy / _size.height) * 2 - 1,
    );
    final palette = AppPalette.of(context);
    return IgnorePointer(
      child: Stack(
        children: [
          ClipPath(
            clipper: _CircleClipper(center: p, radius: _loupeRadius),
            child: _zoomWrap(Transform.scale(scale: _loupeZoom, alignment: align, child: _page(widget.index + 1))),
          ),
          Positioned(
            left: p.dx - _loupeRadius,
            top: p.dy - _loupeRadius,
            child: Container(
              key: const Key('reader-loupe'),
              width: _loupeRadius * 2,
              height: _loupeRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: palette.acc.withValues(alpha: 0.9), width: 2),
                boxShadow: [BoxShadow(color: palette.acc.withValues(alpha: 0.18), blurRadius: 16, spreadRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleClipper extends CustomClipper<Path> {
  const _CircleClipper({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) => Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(covariant _CircleClipper oldClipper) => oldClipper.center != center || oldClipper.radius != radius;
}
