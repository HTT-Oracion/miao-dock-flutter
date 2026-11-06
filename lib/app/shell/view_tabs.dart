import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 模块内视图页签（重设计稿 modules/frames.css `.viewtabs`）：
/// 视图从侧栏视图组迁到工具条（2026-11-07 设计稿定稿）——
/// 侧栏收敛为「品牌 / 模块组 / 迷你播放器 / 设置」，模块内的投放 / 队列 / 漫画库
/// 改在工具条右侧以分段按钮呈现（工作流时序：投放 → 队列 → 漫画库）。
///
/// 纯展示件：路由状态与回调由 [AppShell] 注入。
class ShellViewTabs extends StatelessWidget {
  const ShellViewTabs({super.key, required this.items, required this.activeId, required this.onSelect});

  /// (视图 id, 文案)。文案由壳层经 ARB 注入。
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
