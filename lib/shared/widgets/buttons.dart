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
              child: Text(
                label,
                style: TextStyle(fontSize: AppFont.px12, color: palette.textPrimary),
              ),
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
    // hover 一律**提亮**：主按钮提亮主色，次级由 divider 提亮到 line2。
    // 不用 card —— 弹窗底色就是 card，变 card 会与背景融合。
    final bg = highlight ? (_hover ? palette.accHover : palette.accent) : (_hover ? palette.line2 : palette.divider);
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
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: widget.onTap,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: TextStyle(fontSize: AppFont.px12, color: highlight ? palette.pageBg : palette.textPrimary),
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

  /// **危险确认**：仅用于「不可逆操作」弹窗的确认按钮（删除整本 / 删除本话）。
  /// `bad` 底 + pageBg 字，hover 提亮 `badHover`。
  ///
  /// 判定口径：操作会**造成数据不可恢复的丢失**才用它。
  /// 只是观感上严重（取消翻译 / 停止服务 / 重新下载）用 primary 或 secondary。
  /// 右键菜单 / 下拉里的删除项不走这个变体 —— 那里用 `AppDropdownItem(danger: true)`。
  danger,

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
    this.fontSize = AppFont.px12,
    this.fontWeight,
    this.color,
    this.border = false,
    this.width,
    this.clickable = true,
    this.loading = false,
  });

  /// 文案；**留空 = 纯图标按钮**（此时必须给 [icon]）。
  final String label;
  final VoidCallback? onTap;
  final AppButtonVariant variant;
  final IconData? icon;
  final double height;
  final double horizontalPadding;
  final double fontSize;

  /// 字重；缺省跟随平台默认。设置页按钮用 w600（对齐 `_primaryStyle`）。
  final FontWeight? fontWeight;

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

  /// 加载中：按钮内显示 spinner + 文案，**不可点**（防止重复提交），
  /// 但外观保持启用色（启动引擎等长任务时按钮不能灰成不可用）。
  final bool loading;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // loading 外观按启用画、行为按禁用走。
    final enabled = widget.clickable && !widget.loading;
    final showEnabled = enabled || widget.loading;
    final v = widget.variant;

    if (v == AppButtonVariant.link) {
      final base = widget.color ?? palette.accent;
      return MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: enabled ? widget.onTap : null,
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.fontSize,
              fontWeight: widget.fontWeight,
              // hover 用主色提亮（与 primary 的 hover 背景同色）；
              // 不用 textPrimary —— 它在浅色主题下接近黑色，看起来像变黑。
              color: _hover ? palette.accHover : base,
            ),
          ),
        ),
      );
    }

    final Color bg;
    final Color fg;
    switch (v) {
      case AppButtonVariant.primary:
        bg = showEnabled ? (_hover && enabled ? palette.accHover : palette.accent) : palette.divider;
        fg = showEnabled ? palette.pageBg : palette.textSecondary;
      case AppButtonVariant.danger:
        bg = showEnabled ? (_hover && enabled ? palette.badHover : palette.bad) : palette.divider;
        fg = showEnabled ? palette.pageBg : palette.textSecondary;
      case AppButtonVariant.secondary:
        // hover 提亮到 line2（不是 card）：弹窗底色就是 card，
        // 变 card 会与背景融合，按钮看起来消失。
        bg = showEnabled && _hover && enabled ? palette.line2 : palette.divider;
        fg = showEnabled ? (widget.color ?? palette.textPrimary) : palette.textSecondary;
      case AppButtonVariant.ghost:
        // 同上：提亮到 hi，避免在 card 底的弹窗里 hover 后看不见。
        bg = showEnabled && _hover && enabled ? palette.hi : Colors.transparent;
        fg = showEnabled ? (widget.color ?? palette.textPrimary) : palette.textSecondary;
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
          // 背景由外层 Material 控制，禁用 InkWell 的 hover 覆盖层（否则会盖住主色）。
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          // onTap 为 null 时 InkWell 不吸收手势，交给外层（如 MenuAnchor 的触发器）。
          onTap: enabled ? widget.onTap : null,
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
                if (widget.loading) ...[
                  SizedBox(
                    width: widget.fontSize + 2,
                    height: widget.fontSize + 2,
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: fg),
                  ),
                  if (widget.label.isNotEmpty) const SizedBox(width: 6),
                ] else if (widget.icon != null) ...[
                  Icon(widget.icon, size: widget.fontSize + 1, color: fg),
                  if (widget.label.isNotEmpty) const SizedBox(width: 5),
                ],
                if (widget.label.isNotEmpty)
                  Text(
                    widget.label,
                    style: TextStyle(fontSize: widget.fontSize, fontWeight: widget.fontWeight, color: fg),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
