import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 小型幽灵按钮（26 高）：队列顶栏「多选 / 全选本页」、分页器「N 条 / 页」等次级操作。
class AppGhostButton extends StatelessWidget {
  const AppGhostButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      // 启用 = 可点（手型）；禁用 = 禁止光标（不是普通箭头，否则用户以为可点）。
      cursor: onTap == null ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: Text(label, style: TextStyle(fontSize: 12, color: palette.textPrimary)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 行内小动作钮（24 高，divider 底）：表格行「取消 / 打开 / 更多」等。
class AppTextAction extends StatefulWidget {
  const AppTextAction({super.key, required this.label, required this.onTap, this.highlight = false});

  final String label;

  /// 为 null 时**不吸收点击**（用于外层自带手势的场景，如包着 PopupMenuButton）。
  final VoidCallback? onTap;

  /// 高亮 = 该行**语义主操作**（miao-dock 主按钮：重试 / 查看）。
  final bool highlight;

  @override
  State<AppTextAction> createState() => _AppTextActionState();
}

class _AppTextActionState extends State<AppTextAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final highlight = widget.highlight;
    // ver1.0：主按钮 hover 提亮；ghost hover 底色变 card（设计稿 `.btn.ghost:hover`）。
    final bg = highlight ? (_hover ? palette.accHover : palette.accent) : (_hover ? palette.card : palette.divider);
    return MouseRegion(
      cursor: widget.onTap == null ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          mouseCursor: widget.onTap == null ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
          onTap: widget.onTap,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: TextStyle(fontSize: 12, color: highlight ? palette.pageBg : palette.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// 全项目按钮圆角**唯一来源**（以 `shared/buttons` 为准，禁止各页自定）。
const double kButtonRadius = 6;

/// 胶囊形按钮圆角（设计稿 `.chapcap` 等**固有形状**，不适用 [kButtonRadius]）。
const double kPillRadius = 999;

/// 按钮变体。
enum AppButtonVariant {
  /// 主操作：accent 底 + pageBg 字（新建漫画 / 查看 / 重试）。
  primary,

  /// 次级操作：divider 底 + textPrimary 字，hover 变 card（更多 / 取消 / 继续）。
  secondary,

  /// 幽灵：无底色，hover 变 card（返回书架 / 弹窗取消）。
  ghost,

  /// 文字链接：无底无内边距，hover 提亮（去投放 / 显示已隐藏）。
  link,
}

/// 通用按钮（**漫画与队列模块的唯一按钮实现**）。
///
/// 尺寸可按调用点传入（26/24/32），但**圆角恒为 [kButtonRadius]**，
/// 需要不同圆角请明确说明后改常量，不要在调用点覆盖。
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    this.label = '',
    required this.onTap,
    this.variant = AppButtonVariant.secondary,
    this.icon,
    this.height = 26,
    this.horizontalPadding = 10,
    this.fontSize = 12,
    this.color,
    this.border = false,
    this.width,
    this.clickable = true,
  });

  /// 文案；**留空 = 纯图标按钮**（此时必须给 [icon]）。
  final String label;
  final VoidCallback? onTap;
  final AppButtonVariant variant;
  final IconData? icon;
  final double height;
  final double horizontalPadding;
  final double fontSize;

  /// 覆盖文字色（如 danger 项）。
  final Color? color;

  /// 是否描边（ghost 变体常用）。
  final bool border;

  /// 固定宽度（纯图标按钮用，如章节卡「⋯」22×22）。
  final double? width;

  /// 是否「可点」。
  ///
  /// 🔴 与 `onTap == null` **不是一回事**：
  /// - `onTap == null && clickable == true` → 点击交给外层（如 `MenuAnchor` 触发器），
  ///   光标仍是**手型**、颜色仍按启用态；
  /// - `clickable == false` → 真禁用：光标 `forbidden`、文字变灰。
  final bool clickable;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = widget.clickable;
    final v = widget.variant;

    if (v == AppButtonVariant.link) {
      final base = widget.color ?? palette.accent;
      return MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.fontSize,
              // hover 提亮到 ink，与原 _TextLink 行为一致。
              color: _hover ? palette.textPrimary : base,
            ),
          ),
        ),
      );
    }

    final Color bg;
    final Color fg;
    switch (v) {
      case AppButtonVariant.primary:
        bg = enabled ? (_hover ? palette.accHover : palette.accent) : palette.divider;
        fg = enabled ? palette.pageBg : palette.textSecondary;
      case AppButtonVariant.secondary:
        bg = enabled && _hover ? palette.card : palette.divider;
        fg = enabled ? (widget.color ?? palette.textPrimary) : palette.textSecondary;
      case AppButtonVariant.ghost:
        bg = enabled && _hover ? palette.card : Colors.transparent;
        fg = enabled ? (widget.color ?? palette.textPrimary) : palette.textSecondary;
      case AppButtonVariant.link:
        throw StateError('link variant must be handled above');
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => enabled ? setState(() => _hover = true) : null,
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(kButtonRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kButtonRadius),
          // 🔴 必须显式传：InkWell 默认用 `WidgetStateMouseCursor.adaptiveClickable`，
          // 它在**桌面平台返回 basic**（只有 Web 才 click），且内层 MouseRegion
          // 优先于外层 ⇒ 不传就永远没有手型。
          mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
          // onTap 为 null 时 InkWell 不吸收手势，交给外层（如 MenuAnchor 的触发器）。
          onTap: widget.onTap,
          child: Container(
            width: widget.width,
            height: widget.height,
            padding: EdgeInsets.symmetric(horizontal: widget.width != null ? 0 : widget.horizontalPadding),
            alignment: Alignment.center,
            decoration: widget.border
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(kButtonRadius),
                    border: Border.all(color: palette.divider),
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: widget.fontSize + 1, color: fg),
                  if (widget.label.isNotEmpty) const SizedBox(width: 5),
                ],
                if (widget.label.isNotEmpty)
                  Text(
                    widget.label,
                    style: TextStyle(fontSize: widget.fontSize, color: fg),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
