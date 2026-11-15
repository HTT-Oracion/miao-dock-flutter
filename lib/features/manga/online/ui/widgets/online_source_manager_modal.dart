import 'package:flutter/material.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/widgets/app_dialog.dart';
import '../../../../../shared/widgets/state_box.dart' show kSourceListMaxVisible;
import 'online_source_panel.dart';

/// 漫画源管理弹窗（桌面端）。
///
/// 与 `MusicSourceManagerModal` 同构：同一个面板在「设置页」与「弹窗」两处复用，
/// 弹窗只提供外壳（标题 + 关闭 + 固定宽度），面板自身不感知宿主。
///
/// 「在线」页未导入源时的「导入音乐源 / 导入漫画源」按钮直接拉起本弹窗，
/// 不再跳去设置页 —— 用户在这一步的意图是「马上加一个源」，跳页会丢失上下文。
class OnlineSourceManagerModal extends StatelessWidget {
  const OnlineSourceManagerModal({super.key});

  static Future<void> open(BuildContext context) =>
      showAppDialog<void>(context: context, builder: (_) => const OnlineSourceManagerModal());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppDialog(
      title: l10n.onlineSourceMgrTitle,
      onClose: () => Navigator.of(context).maybePop(),
      child: const SizedBox(
        width: 480,
        // 已装源超过 4 条时列表区滚动，弹窗本身不无限长。
        child: OnlineSourcePanel(maxVisibleSources: kSourceListMaxVisible),
      ),
    );
  }
}
