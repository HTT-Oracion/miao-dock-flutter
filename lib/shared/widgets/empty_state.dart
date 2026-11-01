import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 通用空态（设计稿空书架变体）：图标 + 标题 + 说明 + 可选主按钮。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: palette.textSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: palette.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.6, color: palette.textSecondary),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: palette.accent, foregroundColor: palette.pageBg),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
