import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/empty_state.dart';

/// 漫画库屏（书架）：作品按「本 → 话 → 页」整理。
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: EmptyState(
        icon: LucideIcons.bookOpen,
        title: '书架还是空的',
        description: '投放几张漫画图片，翻译完成后作品会自动按「本 → 话 → 页」整理在这里。',
        actionLabel: '去投放',
        onAction: () => context.go('/manga/drop'),
      ),
    );
  }
}
