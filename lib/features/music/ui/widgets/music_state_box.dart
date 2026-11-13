import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/buttons.dart';
import 'music_source_manager.dart';

/// 音乐模块的状态空盒（对齐漫画 `OnlineStateBox` 的视觉与语义）。
///
/// 未导入源 / 加载失败 / 空数据共用；actionLabel 非空时带主按钮
/// （如「导入音乐源」拉起源管理弹窗）。
class MusicStateBox extends StatelessWidget {
  const MusicStateBox({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 22 : 30, color: palette.mut),
          SizedBox(height: compact ? 6 : 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? AppFont.px11_5 : AppFont.px13,
              fontWeight: FontWeight.w600,
              color: palette.ink,
            ),
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: compact ? AppFont.px10 : AppFont.px11_5, height: 1.7, color: palette.ink2),
          ),
          if (actionLabel != null) ...[
            SizedBox(height: compact ? 8 : 12),
            AppButton(
              label: actionLabel!,
              variant: AppButtonVariant.primary,
              height: compact ? 28 : 32,
              onTap: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

/// 「未导入音乐源」引导：发现 / 我的 / 搜索共用的入口空态。
class MusicNoSourcePrompt extends StatelessWidget {
  const MusicNoSourcePrompt({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MusicStateBox(
      icon: LucideIcons.disc3,
      title: l10n.musicNoSourceTitle,
      description: l10n.musicNoSourceHint,
      actionLabel: l10n.musicSourceMgrOpen,
      onAction: () => MusicSourceManagerModal.open(context),
    );
  }
}
