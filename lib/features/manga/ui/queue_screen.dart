import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/empty_state.dart';

/// 队列屏：任务按串行队列推进，展示每张图的翻译阶段。
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: EmptyState(icon: LucideIcons.layers, title: '队列是空的', description: '投放后任务在这里按串行队列推进，可查看每张图的翻译阶段。'),
    );
  }
}
