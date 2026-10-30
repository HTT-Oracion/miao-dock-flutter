import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/empty_state.dart';

/// 投放屏（设计稿 H 帧 · 空态起步）：拖入或选择漫画图片创建翻译任务。
class DropScreen extends StatelessWidget {
  const DropScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: EmptyState(
        icon: LucideIcons.fileUp,
        title: '拖入漫画图片开始投放',
        description: '支持批量选择与拖拽；任务进入串行队列后按「本 → 话 → 页」整理。',
        actionLabel: '选择图片',
      ),
    );
  }
}
