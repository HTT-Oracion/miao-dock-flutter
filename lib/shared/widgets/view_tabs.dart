import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 模块内视图/分组页签（重设计稿 modules/frames.css `.viewtabs`）：
/// 工具条右侧的分段按钮（投放 / 队列 / 漫画库），也用于设置页数据源分区
/// 的漫画源 / 音乐源切换。纯展示件：选中态与回调由调用方注入。
class ViewTabs extends StatelessWidget {
  const ViewTabs({super.key, required this.items, required this.activeId, required this.onSelect});

  /// (视图 id, 文案)。文案由调用方经 ARB 注入。
  final List<(String, String)> items;
  final String? activeId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, (id, label)) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 2),
            _Tab(label: label, active: activeId == id, onTap: () => onSelect(id)),
          ],
        ],
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final Color background;
    if (widget.active) {
      background = palette.acc;
    } else if (_hover) {
      background = palette.hi;
    } else {
      background = Colors.transparent;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.morphCurve,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: AppFont.px11_5,
              fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
              color: widget.active ? palette.onAcc : palette.ink2,
            ),
          ),
        ),
      ),
    );
  }
}
