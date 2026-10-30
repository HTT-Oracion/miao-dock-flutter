import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';

/// 队列空态（设计稿 H Note 06，逐字文案）：还没有翻译任务。
class QueueEmpty extends StatelessWidget {
  const QueueEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTokens.progressTrack, width: 2),
            ),
            child: const Icon(LucideIcons.layers, size: 28, color: AppTokens.textSecondary),
          ),
          const SizedBox(height: 14),
          const Text(
            '还没有翻译任务',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text('在漫画页用插件提交，或把图片拖进这个窗口', style: TextStyle(fontSize: 12, color: AppTokens.textSecondary)),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTokens.accent, foregroundColor: AppTokens.pageBg),
                onPressed: () => context.go('/settings'),
                child: const Text('去设置里配对插件'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTokens.textPrimary,
                  side: const BorderSide(color: AppTokens.progressTrack),
                ),
                onPressed: () => context.go('/manga/drop'),
                child: const Text('本机投放'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
