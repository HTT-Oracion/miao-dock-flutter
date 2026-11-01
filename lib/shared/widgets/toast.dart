import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 提示语气（对应设计稿 `.toast .dot` 的颜色）。
enum ToastTone { info, good, warn, bad }

/// 应用吐司：轻提示统一入口。
///
/// ## 为什么不用 `SnackBar`
/// 设计稿的 `.toast` 有自己的规格（右下浮出、面板底色、1px 描边、6px 圆点、滑入动画），
/// 而 `SnackBar` 的背景/圆角/动画都受 Material 主题支配，改不到位。
/// 这里用 `Overlay` 自绘，才能 1:1。
///
/// ```css
/// .toast{display:flex;align-items:center;gap:8px;padding:9px 12px;border-radius:8px;
///        background:var(--panel);border:1px solid var(--line2);box-shadow:var(--shadow);
///        font-size:12px;color:var(--ink2)}
/// .toast .dot{width:6px;height:6px}
/// @keyframes toastIn{from{opacity:0;transform:translateX(16px)}to{opacity:1;transform:none}}
/// ```
void showAppToast(BuildContext context, String message, {ToastTone tone = ToastTone.info}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late OverlayEntry entry;
  var closing = false;

  void close() {
    if (closing) return;
    closing = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) => _ToastHost(message: message, tone: tone, onDone: close),
  );
  overlay.insert(entry);

  // 自动消失；`_ToastHost` 负责淡出后再通知移除。
  Timer(const Duration(milliseconds: 3200), () {
    if (!closing) entry.remove();
  });
}

class _ToastHost extends StatefulWidget {
  const _ToastHost({required this.message, required this.tone, required this.onDone});

  final String message;
  final ToastTone tone;
  final VoidCallback onDone;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dot = switch (widget.tone) {
      ToastTone.info => palette.acc,
      ToastTone.good => palette.good,
      ToastTone.warn => palette.warn,
      ToastTone.bad => palette.bad,
    };

    // 设计稿 `#toasts{top:14px;right:14px}`：**右上角**，不是右下角。
    return Positioned(
      right: 14,
      top: 14,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Opacity(
            opacity: _c.value,
            child: Transform.translate(offset: Offset(16 * (1 - _c.value), 0), child: child),
          ),
          // 🔴 必须有 Material 祖先：Overlay 里的裸 Text 找不到 Material，
          // Flutter 会画「黄色双下划线」提示缺少文本样式（实测踩到）。
          // 用 transparency，避免多出一层不透明底色盖掉自绘面板。
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: palette.panel,
                border: Border.all(color: palette.line2),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(widget.message, style: TextStyle(fontSize: 12, color: palette.ink2)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
