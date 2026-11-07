import 'package:flutter/material.dart';

/// 持续旋转的图标（loader 语义的「正在进行」提示）。
///
/// lucide 的 `loader` 是静态字形：不转就会被读成「卡住了」而不是「在跑」。
/// 只要这个图标代表一次**进行中**的动作（远程校验 / 引擎启动）就必须转。
///
/// `spinning == false` 时**停表**：状态已落地还留着 ticker，等于给一个
/// 不会变的图标每秒推 60 帧重绘。
class SpinningIcon extends StatefulWidget {
  const SpinningIcon(this.icon, {super.key, required this.size, required this.color, this.spinning = true});

  final IconData icon;
  final double size;
  final Color color;
  final bool spinning;

  @override
  State<SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<SpinningIcon> with SingleTickerProviderStateMixin {
  /// 0.9s / 圈：比 Material 自带 spinner（约 1.3s）快一档，与 `_PulseDot`
  /// 的脉冲同量级 —— 能看出在动，又不抢主内容的注意力。
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant SpinningIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning == oldWidget.spinning) return;
    if (widget.spinning) {
      _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: Icon(widget.icon, size: widget.size, color: widget.color),
    );
  }
}
