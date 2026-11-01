import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';

/// 队列空态（设计稿 H Note 06，逐字文案）：只给「还没有翻译任务」+ 两个引导动作。
class QueueEmpty extends StatelessWidget {
  const QueueEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: palette.progressTrack, width: 2),
            ),
            child: Icon(LucideIcons.inbox, size: 28, color: palette.textSecondary),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.queueEmptyTitle,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(l10n.queueEmptyDesc, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: palette.accent, foregroundColor: palette.pageBg),
                onPressed: () => context.go('/settings'),
                child: Text(l10n.queueGoSettings),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.textPrimary,
                  side: BorderSide(color: palette.progressTrack),
                ),
                onPressed: () => context.go('/manga/drop'),
                child: Text(l10n.queueSourceLocal),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
