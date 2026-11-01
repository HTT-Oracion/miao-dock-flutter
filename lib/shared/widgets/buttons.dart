import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 小型幽灵按钮（26 高）：队列顶栏「多选 / 全选本页」、分页器「N 条 / 页」等次级操作。
class AppGhostButton extends StatelessWidget {
  const AppGhostButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
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
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary)),
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
    final highlight = widget.highlight;
    // ver1.0：主按钮 hover 提亮；ghost hover 底色变 card（设计稿 `.btn.ghost:hover`）。
    final bg = highlight
        ? (_hover ? const Color(0xFFF0B96A) : AppTokens.accent)
        : (_hover ? AppTokens.card : AppTokens.divider);
    return MouseRegion(
      cursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: widget.onTap,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: TextStyle(fontSize: 12, color: highlight ? AppTokens.pageBg : AppTokens.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
