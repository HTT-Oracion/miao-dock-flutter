import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 下拉菜单项（与 [AppDropdownMenu] 配套）。
class AppDropdownItem {
  const AppDropdownItem({
    required this.value,
    required this.label,
    this.icon,
    this.sub,
    this.enabled = true,
    this.danger = false,
  }) : isDivider = false;

  const AppDropdownItem.divider()
    : value = '',
      label = '',
      icon = null,
      sub = null,
      enabled = false,
      danger = false,
      isDivider = true;

  final String value;
  final String label;
  final IconData? icon;

  /// 副标（如「待续做 3 张」），9.5 号灰字。
  final String? sub;
  final bool enabled;
  final bool danger;
  final bool isDivider;
}

/// Material 3 下拉菜单（**项目内唯一实现**，基于 [MenuAnchor]）。
///
/// 为什么用 `MenuAnchor` 而不是自绘 Overlay：
/// 自绘要手算锚点矩形，窗口缩放 / 滚动 / 位置变化时容易偏；
/// `MenuAnchor` 由框架拿**触发按钮的实际布局矩形**定位，
/// `alignment: Alignment.bottomLeft` ⇒ 菜单在按钮**正下方、左边缘对齐**，
/// 空间不足时框架自动翻转，不需要自己算。
///
/// 用法：把触发按钮作为 [child] 传入，菜单项通过 [items] 提供。
class AppDropdownMenu extends StatefulWidget {
  const AppDropdownMenu({
    super.key,
    required this.child,
    required this.items,
    required this.onSelected,
    this.minWidth,
    this.alignWidthToChild = true,
    this.enabled = true,
  });

  /// 触发按钮（自己处理外观，如 `AppButton`）。
  final Widget child;
  final List<AppDropdownItem> items;
  final ValueChanged<String> onSelected;

  /// 菜单最小宽度；为 null 时取触发按钮宽度（[alignWidthToChild] 为 true）。
  final double? minWidth;

  /// 菜单宽度是否与触发按钮对齐。
  final bool alignWidthToChild;

  final bool enabled;

  @override
  State<AppDropdownMenu> createState() => _AppDropdownMenuState();
}

class _AppDropdownMenuState extends State<AppDropdownMenu> {
  final _controller = MenuController();
  final _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MenuAnchor(
      controller: _controller,
      // 正下方 + 左边缘对齐；由框架负责越界翻转。
      alignmentOffset: const Offset(0, 4),
      // 点外部关闭；触发起自身的开合由 builder 里显式 toggle 控制。
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.panel),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: palette.line2),
          ),
        ),
      ),
      menuChildren: [
        for (final it in widget.items)
          it.isDivider
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Divider(height: 1, thickness: 1, color: palette.divider),
                )
              : _MenuRow(
                  item: it,
                  onTap: () {
                    _controller.close();
                    widget.onSelected(it.value);
                  },
                ),
      ],
      builder: (context, controller, child) => GestureDetector(
        key: _childKey,
        onTap: widget.enabled ? () => controller.isOpen ? controller.close() : controller.open() : null,
        child: widget.child,
      ),
    );
  }
}

/// 菜单行：**左对齐、整行铺满菜单宽度**（hover 整行高亮）。
class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.item, required this.onTap});

  final AppDropdownItem item;
  final VoidCallback onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final it = widget.item;
    final enabled = it.enabled;
    final Color fg;
    if (!enabled) {
      fg = palette.textSecondary;
    } else if (it.danger) {
      // 危险项：平时正常色，hover 才转危险色。
      fg = _hover ? palette.bad : palette.textPrimary;
    } else {
      fg = palette.textPrimary;
    }
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => enabled ? setState(() => _hover = true) : null,
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minWidth: 160),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: enabled && _hover ? palette.divider : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              if (it.icon != null) ...[Icon(it.icon, size: 13, color: fg), const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  it.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: fg),
                ),
              ),
              if (it.sub != null) ...[
                const SizedBox(width: 6),
                Text(it.sub!, style: TextStyle(fontSize: 9.5, color: palette.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 在**指定屏幕位置**弹出同一套 M3 菜单（用于右键：没有触发按钮可做锚点）。
///
/// 做法：临时插一个 1×1 的透明锚点 widget（定位于 [position]），
/// 再由 [MenuAnchor] 以它为锚展开 —— 菜单样式/行为与 [AppDropdownMenu] 完全一致。
Future<String?> showAppMenuAt(
  BuildContext context, {
  required Offset position,
  required List<AppDropdownItem> items,
  double minWidth = 180,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) => _PositionedMenuProbe(position: position, items: items, minWidth: minWidth),
  );
}

class _PositionedMenuProbe extends StatefulWidget {
  const _PositionedMenuProbe({required this.position, required this.items, required this.minWidth});

  final Offset position;
  final List<AppDropdownItem> items;
  final double minWidth;

  @override
  State<_PositionedMenuProbe> createState() => _PositionedMenuProbeState();
}

class _PositionedMenuProbeState extends State<_PositionedMenuProbe> {
  final _controller = MenuController();

  @override
  void initState() {
    super.initState();
    // 下一帧打开：保证锚点完成布局后菜单才定位。
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.open());
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Stack(
      children: [
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy,
          child: MenuAnchor(
            controller: _controller,
            alignmentOffset: const Offset(0, 4),
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(palette.panel),
              elevation: const WidgetStatePropertyAll(0),
              padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(color: palette.line2),
                ),
              ),
            ),
            menuChildren: [
              for (final it in widget.items)
                it.isDivider
                    ? Padding(
                        padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        child: Divider(height: 1, thickness: 1, color: palette.divider),
                      )
                    : _MenuRow(
                        item: it,
                        onTap: () {
                          _controller.close();
                          Navigator.of(context).pop(it.value);
                        },
                      ),
            ],
            builder: (context, controller, child) => const SizedBox(width: 1, height: 1),
          ),
        ),
      ],
    );
  }
}
