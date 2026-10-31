import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/empty_state.dart';

/// 我的歌单（`/music/playlist`）：本期仅承载路由。
///
/// 歌单数据来自音乐域（尚未落地），故不渲染任何占位曲目 —— 只给空态。
class MusicPlaylistScreen extends StatelessWidget {
  const MusicPlaylistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppMetrics.contentPadding, vertical: 18),
      child: EmptyState(icon: LucideIcons.listMusic, title: '我的歌单', description: '歌单随音乐域落地后在此展示。'),
    );
  }
}
