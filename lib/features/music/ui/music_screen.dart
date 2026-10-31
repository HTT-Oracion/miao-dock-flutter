import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/empty_state.dart';

/// 音乐模块内的视图（与 `musicViews` 的 id 一一对应）。
enum MusicScreenView { discover, playlist, local, history }

/// 音乐屏：本期（应用主体框架）只承载路由与空态。
///
/// **不造假数据**：官方榜单 / 推荐歌单 / 每日推荐都需要真实音源接口
/// （原项目 `modules/music/store.ts` + 四平台代理），音乐域尚未落地，
/// 故按 design.html §07 的空态规范给出「尚未接入」的说明与引导动作。
class MusicScreen extends StatelessWidget {
  const MusicScreen({super.key, required this.view});

  final MusicScreenView view;

  /// 视图 → 图标（图标不随语言变化，可静态）。
  static const _icons = {
    MusicScreenView.discover: LucideIcons.compass,
    MusicScreenView.playlist: LucideIcons.listMusic,
    MusicScreenView.local: LucideIcons.hardDrive,
    MusicScreenView.history: LucideIcons.history,
  };

  /// 视图 → ARB 文案（标题 + 说明）。
  static ({String title, String description}) _textOf(AppLocalizations l10n, MusicScreenView v) => switch (v) {
    MusicScreenView.discover => (title: l10n.viewDiscover, description: l10n.musicDiscoverEmpty),
    MusicScreenView.playlist => (title: l10n.viewPlaylist, description: l10n.musicPlaylistEmpty),
    MusicScreenView.local => (title: l10n.viewLocal, description: l10n.musicLocalEmpty),
    MusicScreenView.history => (title: l10n.viewHistory, description: l10n.musicHistoryEmpty),
  };

  @override
  Widget build(BuildContext context) {
    final text = _textOf(AppLocalizations.of(context), view);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppMetrics.contentPadding, vertical: 18),
      child: EmptyState(icon: _icons[view]!, title: text.title, description: text.description),
    );
  }
}
