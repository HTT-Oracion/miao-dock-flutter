import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../controller/music_player.dart';
import '../controller/music_providers.dart';
import '../controller/music_session.dart';
import 'desktop/account_menu.dart';
import 'desktop/desktop_lyrics.dart';
import 'desktop/play_bar.dart';
import 'desktop/queue_drawer.dart';
import 'views/discover_view.dart';
import 'views/history_view.dart';
import 'views/local_view.dart';
import 'views/playlist_view.dart';
import 'widgets/music_shared.dart';

/// 音乐模块内的视图（与 `musicViews` 的 id 一一对应；路由依赖此枚举，勿改签名）。
enum MusicScreenView { discover, playlist, local, history }

/// 音乐屏（桌面模块容器）：内容区 + 底部播放条 + 顶层浮层。
///
/// · 所有浮层用 **Stack 内 Alignment** 挂载（不用 OverlayEntry，方便测试）；
/// · 键盘层（N33）：空格播放 / ←→ 快退快进 5s / ↑↓ 音量 ±5 / M 静音 / Q 队列 /
///   F 沉浸 / ⌘K·Ctrl+K 搜索 / Esc 逐层关闭（登录 → 搜索 → 账号菜单 → 队列 → 沉浸 → 岛）；
///   输入框聚焦时全局快捷键让位（用 primaryFocus 的祖先链查 [TextField]，简化实现）。
/// · 本文件不做移动端切换 —— 由外层（B 端集成）决定何时渲染 MusicScreen。
class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key, required this.view, this.body});

  final MusicScreenView view;

  /// 覆盖内容区（详情路由复用它，才能保住底部播放条与模块浮层，N16/N41）。
  final Widget? body;

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen> {
  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final ui = ref.watch(musicUiProvider);
    final hasPlayer = player.queue.isNotEmpty;
    const playBarH = MusicPlayBar.height;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Stack(
        children: [
          // 内容区：队列为空时占满，有播放条时让出底部（不给浮层叠出双向滚动）。
          Positioned.fill(
            bottom: hasPlayer ? playBarH : 0,
            child: Padding(
              padding: EdgeInsets.fromLTRB(AppMetrics.contentPadding, 6, AppMetrics.contentPadding, hasPlayer ? 6 : 18),
              child: MusicNoticeBridge(child: _body()),
            ),
          ),
          // 播放条（队列为空时整条隐藏）。
          if (hasPlayer) Positioned(left: 0, right: 0, bottom: 0, height: playBarH, child: const MusicPlayBar()),
          // 队列抽屉（不遮播放条：bottom 留播放条高度，N14）。
          if (hasPlayer && ui.queueOpen) Positioned(top: 0, right: 0, bottom: playBarH, child: const QueueDrawer()),
          // 沉浸播放器覆盖整个应用，挂在壳层（见 app_shell.dart），不在此层叠。
          // 搜索 / 登录浮层挂**壳层**（要盖住侧栏与工具条，设计稿浮层覆盖全窗口）：
          // 见 app_shell.dart 的 _DesktopShell；这里只挂模块内浮层。
          if (ui.accountMenuOpen) const Positioned.fill(child: AccountMenuPopover()),
          // 桌面歌词浮层：最顶层 + IgnorePointer（不挡桌面操作，N19）。
          const Positioned.fill(child: DesktopLyricsOverlay()),
        ],
      ),
    );
  }

  Widget _body() {
    final override = widget.body;
    if (override != null) return override;
    return switch (widget.view) {
      MusicScreenView.discover => const DiscoverView(),
      MusicScreenView.playlist => const PlaylistLibraryView(),
      MusicScreenView.local => const LocalView(),
      MusicScreenView.history => const HistoryView(),
    };
  }

  // ── 键盘层（N33）──────────────────────────────────────────────────────────

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    // 只在按下时触发切换类快捷键（连按 repeat 只对 seek/音量有意义）。
    final down = event is KeyDownEvent;
    if (!down && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    // 输入框聚焦时全局快捷键让位（N33 边界）：从 primaryFocus 的元素向上找 TextField。
    if (_isEditing()) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final player = ref.read(playerProvider);
    final ui = ref.read(musicUiProvider);
    final uiN = ref.read(musicUiProvider.notifier);
    final playerN = ref.read(playerProvider.notifier);
    final hasPlayer = player.current != null;

    // ⌘K / Ctrl+K：搜索（N06）。
    final mod = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (mod && key == LogicalKeyboardKey.keyK) {
      uiN.setSearch(true);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      // 逐层关闭（N16/N33 顺序：登录 → 搜索 → 账号菜单 → 队列 → 沉浸 → 岛）。
      if (ui.loginOpen) {
        uiN.closeLogin();
        return KeyEventResult.handled;
      }
      if (ui.searchOpen) {
        ref.read(musicSearchProvider.notifier).clear();
        uiN.setSearch(false);
        return KeyEventResult.handled;
      }
      if (ui.accountMenuOpen) {
        uiN.setAccountMenu(false);
        return KeyEventResult.handled;
      }
      if (ui.queueOpen) {
        uiN.setQueue(false);
        return KeyEventResult.handled;
      }
      if (ui.immersiveOpen) {
        uiN.setImmersive(false);
        return KeyEventResult.handled;
      }
      if (ui.islandOpen) {
        uiN.setIsland(false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (!hasPlayer) return KeyEventResult.ignored;

    if (down && key == LogicalKeyboardKey.space) {
      playerN.toggle();
      return KeyEventResult.handled;
    }
    // ←/→ 快退 / 快进 5 秒（N09）；连按 repeat 生效。
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      final delta = key == LogicalKeyboardKey.arrowLeft ? -5000 : 5000;
      playerN.seekMs(player.positionMs + delta);
      return KeyEventResult.handled;
    }
    // ↑/↓ 音量 ±5（N12）。
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      final delta = key == LogicalKeyboardKey.arrowUp ? 5 : -5;
      playerN.setVolume(player.volume + delta);
      return KeyEventResult.handled;
    }
    if (down && (key == LogicalKeyboardKey.keyM || key == LogicalKeyboardKey.keyQ || key == LogicalKeyboardKey.keyF)) {
      if (key == LogicalKeyboardKey.keyM) {
        playerN.toggleMute();
      } else if (key == LogicalKeyboardKey.keyQ) {
        uiN.setQueue(!ui.queueOpen);
      } else {
        uiN.setImmersive(!ui.immersiveOpen);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 输入框聚焦判定：primaryFocus 的 context 向上查祖先是否有 [TextField]
  /// （TextField 包住 Focus/EditableText，FocusNode.context 指向 Focus 元素）。
  bool _isEditing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is TextField || ctx.findAncestorWidgetOfExactType<TextField>() != null;
  }
}
