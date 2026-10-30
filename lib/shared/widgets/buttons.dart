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
class AppTextAction extends StatelessWidget {
  const AppTextAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTokens.divider,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          child: Text(label, style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary)),
        ),
      ),
    );
  }
}
