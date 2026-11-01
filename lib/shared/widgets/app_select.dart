import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import 'app_dropdown.dart';
import 'buttons.dart' show kButtonRadius;

/// 下拉选择（design.html `.select` 外观）。
///
/// 菜单本体走 **[AppDropdownMenu] 同款的 M3 `MenuAnchor`** ——
/// 之前用 `PopupMenuButton` 时弹层位置靠硬编码 `offset`，按钮移动就错位，
/// 且与操作菜单（更多 / 章节）两套外观。现在两者统一。
///
/// [searchable] 为 true 时菜单顶部带搜索框（选项多时用，如归并目标漫画）。
class AppSelect<T> extends StatefulWidget {
  const AppSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width,
    this.enabled = true,
  });

  final T value;

  /// 值与显示文案。
  final List<(T, String)> items;
  final ValueChanged<T>? onChanged;

  /// 固定宽度；null = 自适应内容。
  final double? width;
  final bool enabled;

  @override
  State<AppSelect<T>> createState() => _AppSelectState<T>();
}

class _AppSelectState<T> extends State<AppSelect<T>> {
  final _controller = MenuController();

  String get _label {
    for (final (v, label) in widget.items) {
      if (v == widget.value) return label;
    }
    return widget.items.isEmpty ? '' : widget.items.first.$2;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final active = widget.enabled && widget.onChanged != null;

    return MenuAnchor(
      controller: _controller,
      // 正下方 + 左对齐；位置由框架按按钮矩形算，不再硬编码 offset。
      alignmentOffset: const Offset(0, 4),
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.panel),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kButtonRadius),
            side: BorderSide(color: palette.line2),
          ),
        ),
      ),
      menuChildren: [
        for (final (v, label) in widget.items)
          _MenuRow(
            label: label,
            selected: v == widget.value,
            onTap: () {
              _controller.close();
              widget.onChanged?.call(v);
            },
          ),
      ],
      builder: (context, controller, child) => MouseRegion(
        cursor: active ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: GestureDetector(
          onTap: active ? () => controller.isOpen ? controller.close() : controller.open() : null,
          child: Container(
            height: 28,
            width: widget.width,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: palette.card,
              border: Border.all(color: palette.line2),
              borderRadius: BorderRadius.circular(kButtonRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px10, color: widget.enabled ? palette.ink : palette.mut),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(LucideIcons.chevronDown, size: 10, color: palette.mut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 菜单里的一行（与 `.select` 同字号）。
class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: palette.line,
        splashColor: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: _hover ? palette.line : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFont.px10,
                    color: widget.selected ? palette.acc : palette.ink,
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.selected) Icon(LucideIcons.check, size: 10, color: palette.acc),
            ],
          ),
        ),
      ),
    );
  }
}
