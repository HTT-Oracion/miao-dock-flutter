import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 统一下拉菜单（对齐 miao-dock `.ui-menu` / `.ui-menu-item`，配色换成本项目 token）。
///
/// - 面板：`card` 底、1px `divider` 描边、6 圆角、padding 4、项间距 2；
/// - 项：高 30、左右 9、图标 13、字号 11.5；hover 底色 `navBg`；
/// - 危险项 hover 时文字转 `bad`；禁用项文字 `textSecondary` 且不响应 hover。
///
/// 全项目菜单只走这一处，避免各页各写一套导致观感不一致。
class AppMenu extends StatelessWidget {
  const AppMenu({super.key, required this.items, required this.onSelected, this.minWidth = 180});

  final List<AppMenuItem> items;
  final ValueChanged<String> onSelected;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: minWidth),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTokens.card,
        border: Border.all(color: AppTokens.divider),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final it in items)
            it.isSeparator
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                    child: Container(height: 1, color: AppTokens.divider),
                  )
                : _MenuRow(item: it, onTap: () => onSelected(it.value!)),
        ],
      ),
    );
  }
}

/// 一个菜单项。
class AppMenuItem {
  const AppMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.sub,
    this.enabled = true,
    this.danger = false,
  }) : isSeparator = false;

  const AppMenuItem.separator()
    : value = null,
      label = '',
      icon = null,
      sub = null,
      enabled = false,
      danger = false,
      isSeparator = true;

  final String? value;
  final String label;
  final IconData? icon;

  /// 副标（如「待续做 3 张」），9.5 号灰字。
  final String? sub;
  final bool enabled;
  final bool danger;
  final bool isSeparator;
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.item, required this.onTap});

  final AppMenuItem item;
  final VoidCallback onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final enabled = it.enabled;
    final Color fg;
    if (!enabled) {
      fg = AppTokens.textSecondary;
    } else if (it.danger) {
      fg = _hover ? AppTokens.bad : AppTokens.bad;
    } else {
      fg = AppTokens.textPrimary;
    }
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => enabled ? setState(() => _hover = true) : null,
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: enabled && _hover ? AppTokens.navBg : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              if (it.icon != null) ...[Icon(it.icon, size: 13, color: fg), const SizedBox(width: 8)],
              Text(it.label, style: TextStyle(fontSize: 11.5, color: fg)),
              if (it.sub != null) ...[
                const SizedBox(width: 6),
                Text(it.sub!, style: const TextStyle(fontSize: 9.5, color: AppTokens.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 打开统一样式的下拉菜单（自绘 Overlay：位置跟随锚点，点击外部关闭）。
Future<String?> showAppMenu(
  BuildContext context, {
  required Offset position,
  required List<AppMenuItem> items,
  double minWidth = 180,
}) {
  final overlay = Overlay.of(context);
  final box = overlay.context.findRenderObject()! as RenderBox;
  final size = box.size;
  final completer = Completer<String?>();
  late OverlayEntry entry;

  void close(String? v) {
    if (completer.isCompleted) return;
    entry.remove();
    completer.complete(v);
  }

  // 预估高度：项 30 + 间距，向上翻转避免越界。
  final estHeight = items.fold<double>(8, (a, it) => a + (it.isSeparator ? 7 : 30));
  final left = position.dx.clamp(8.0, size.width - minWidth - 8);
  final top = (position.dy + estHeight > size.height)
      ? (position.dy - estHeight).clamp(8.0, size.height - 8)
      : position.dy;

  entry = OverlayEntry(
    builder: (context) => Stack(
      children: [
        // 点空白关闭
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => close(null),
            onSecondaryTap: () => close(null),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: AppMenu(items: items, minWidth: minWidth, onSelected: (v) => close(v)),
          ),
        ),
      ],
    ),
  );
  overlay.insert(entry);
  return completer.future;
}
