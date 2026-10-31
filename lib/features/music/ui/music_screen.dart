import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/empty_state.dart';

/// 音乐模块内的视图（与 [musicViews] 的 id 一一对应）。
enum MusicScreenView { discover, playlist, local, history }

/// 音乐屏：本期（应用主体框架）只承载路由与空态。
///
/// **不造假数据**：官方榜单 / 推荐歌单 / 每日推荐都需要真实音源接口
/// （原项目 `modules/music/store.ts` + 四平台代理），音乐域尚未落地，
/// 故按 design.html §07 的空态规范给出「尚未接入」的说明与引导动作。
class MusicScreen extends StatelessWidget {
  const MusicScreen({super.key, required this.view});

  final MusicScreenView view;

  static const _meta = {
    MusicScreenView.discover: (LucideIcons.compass, '发现', '官方榜单与推荐歌单需要接入音乐源后才可用。'),
    MusicScreenView.local: (LucideIcons.hardDrive, '本地音乐', '本地曲库尚未接入；接入后在此选择文件或文件夹导入。'),
    MusicScreenView.history: (LucideIcons.history, '播放历史', '播放历史随音乐域落地后在此展示。'),
    MusicScreenView.playlist: (LucideIcons.listMusic, '我的歌单', '歌单随音乐域落地后在此展示。'),
  };

  @override
  Widget build(BuildContext context) {
    final meta = _meta[view]!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppMetrics.contentPadding, vertical: 18),
      child: EmptyState(icon: meta.$1, title: meta.$2, description: meta.$3),
    );
  }
}
