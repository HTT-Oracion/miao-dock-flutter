import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/music_player.dart';
import '../../controller/music_session.dart';
import '../music_screen.dart' show MusicScreenView;
import '../views/discover_view.dart';
import '../views/history_view.dart';
import '../views/local_view.dart';
import '../views/playlist_view.dart';
import '../widgets/music_shared.dart';
import 'full_player.dart';
import 'mini_bar.dart';
import 'music_sheets.dart';

/// 音乐模块移动端分支内容容器（M01–M17）。
///
/// 结构：Stack = 视图主体（discover / playlist / local / history，由路由
/// builder 传 [view]）+ 迷你播放条（队列非空，M03 底部留余量）+ 全屏播放器
/// （immersiveOpen，M04）+ 底部抽屉组（队列 / 音质 / 样式 / 更多 / 账号，M07）
/// + 歌曲行菜单（songMenuSongId，M15）。外层包 [MusicNoticeBridge] 转
/// controller 语义通知。
///
/// 顶部二级页签与底部一级导航属于壳层（app_shell），本容器只负责分支内容区。
class MobileMusicScreen extends ConsumerWidget {
  const MobileMusicScreen({super.key, required this.view, this.body});

  final MusicScreenView view;

  /// 覆盖内容区（详情路由复用：迷你条与全屏播放器要跟着详情一起在，M04/N41）。
  final Widget? body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _MobileBranch(view: view, body: body);
  }
}

/// 私有分支宿主：持有「更多」抽屉的本地开关（musicUiProvider 无此位）。
class _MobileBranch extends ConsumerStatefulWidget {
  const _MobileBranch({required this.view, this.body});

  final MusicScreenView view;
  final Widget? body;

  @override
  ConsumerState<_MobileBranch> createState() => _MobileBranchState();
}

class _MobileBranchState extends ConsumerState<_MobileBranch> {
  bool _moreOpen = false;

  /// 视图统一**有界宿主**（与桌面 MusicScreen 同口径）：四个视图根部都是
  /// `Column[Expanded(内部滚动)]`，自带纵向滚动，宿主只给有界高度与边距。
  /// 水平边距移动端 16（设计稿 `.m-pad`），桌面宿主给 24 —— 由宿主负责。
  Widget _branchView() =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: widget.body ?? _defaultView());

  Widget _defaultView() => switch (widget.view) {
    MusicScreenView.discover => const DiscoverView(),
    MusicScreenView.playlist => const PlaylistLibraryView(),
    MusicScreenView.local => const LocalView(),
    MusicScreenView.history => const HistoryView(),
  };

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(musicUiProvider);
    final miniVisible = ref.watch(playerProvider.select((p) => p.queue.isNotEmpty));
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return MusicNoticeBridge(
      child: Stack(
        // 全覆盖 Stack：非定位子件（抽屉宿主 / 行菜单）强制撑满，否则
        // 只含定位子件时 Stack 会收缩为 0，Positioned.fill 全部塌掉。
        fit: StackFit.expand,
        children: [
          // M03：队列非空时主体底部留出「迷你条 + 安全区」的滚动余量。
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: miniVisible ? kMiniBarHeight + bottomInset : 0),
              child: _branchView(),
            ),
          ),
          if (miniVisible) const Positioned(left: 0, right: 0, bottom: 0, child: MiniMusicBar()),
          if (ui.immersiveOpen)
            Positioned.fill(child: FullMusicPlayer(onMoreTap: () => setState(() => _moreOpen = true))),
          MusicSheetsHost(moreOpen: _moreOpen, onMoreClose: () => setState(() => _moreOpen = false)),
        ],
      ),
    );
  }
}
