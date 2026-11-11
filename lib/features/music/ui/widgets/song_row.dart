import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/toast.dart';
import 'music_shared.dart';
import '../../controller/music_player.dart';
import '../../domain/music_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 音乐模块浮层基件（行菜单 / 音质弹层 / 样式弹层 / 账号菜单共用）。
// 放在本文件是因为 song_row 位于音乐 UI 依赖图最底部，可被其余浮层安全引用。
// ─────────────────────────────────────────────────────────────────────────────

/// 在指定屏幕坐标弹出音乐模块浮层（右键菜单 / 长按菜单 / 音质 / 样式弹层）。
///
/// 与 `showAppMenuAt`（shared，manga 右键在用）同型：透明 barrier + 1 个定位锚点。
/// 差异：浮层内部自挂 [Focus]（autofocus）拦截 **Esc 关闭**（N33/N36 逐层关闭）；
/// 坐标按屏幕尺寸夹紧，靠右下角弹出不会溢出窗口（N36 边界）。
Future<T?> showAnchoredMusicPanel<T>(
  BuildContext context, {
  required Offset position,
  required double width,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    barrierLabel: 'music-anchored-panel',
    transitionDuration: Duration.zero,
    pageBuilder: (ctx, _, _) {
      final size = MediaQuery.sizeOf(ctx);
      const margin = 8.0;
      final left = position.dx.clamp(margin, math.max(margin, size.width - width - margin)).toDouble();
      // 高度未知，按弹层常见最大高 260 预估夹紧（design openPop 的同款口径）。
      final top = position.dy.clamp(margin, math.max(margin, size.height - 260)).toDouble();
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                  Navigator.of(ctx).pop();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Material(color: Colors.transparent, child: builder(ctx)),
            ),
          ),
        ],
      );
    },
  );
}

/// 浮层容器（app.css `.pop`）：panel 底 + line2 描边 + r12 + 投影，内距 5。
class MusicPanelBox extends StatelessWidget {
  const MusicPanelBox({super.key, required this.child, this.width = 210, this.padding = const EdgeInsets.all(5)});

  final Widget child;
  final double width;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
        boxShadow: [
          BoxShadow(color: palette.shadow.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }
}

/// 浮层分组头（app.css `.pop .ph`）：小号灰字。
class MusicMenuHeader extends StatelessWidget {
  const MusicMenuHeader({super.key, required this.text, this.trailing, this.subtitle, this.coverSeed, this.coverUrl});

  final String text;
  final String? trailing;

  /// 副行（移动端歌曲菜单的「歌手」行，设计稿 M15 `.rm-head span`）。
  final String? subtitle;

  /// 封面种子 / 真实封面：非空时头部改为「封面 + 歌名 / 歌手」（M15）。
  final String? coverSeed;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final seed = coverSeed;
    if (seed != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 9),
        child: Container(
          padding: const EdgeInsets.only(bottom: 9),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.line)),
          ),
          child: Row(
            children: [
              SeedCover(seed: seed, imageUrl: coverUrl, size: 30, radius: 6),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFont.px10, color: palette.mut, letterSpacing: 0.8),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(fontSize: AppFont.px9_5, color: palette.accInk, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

/// 浮层菜单项（app.css `.pop button`）：图标（或自定义前导块）+ 文案 + 可选尾注 / 勾选。
class MusicMenuTile extends StatefulWidget {
  const MusicMenuTile({
    super.key,
    this.icon,
    required this.label,
    required this.onTap,
    this.sub,
    this.checked = false,
    this.danger = false,
    this.leading,
  });

  /// 图标；与 [leading] 至少给一个（leading 优先）。
  final IconData? icon;

  /// 自定义前导块（样式弹层的缩略色块）；非空时优先于 [icon]。
  final Widget? leading;
  final String label;
  final String? sub;
  final bool checked;
  final bool danger;
  final VoidCallback onTap;

  @override
  State<MusicMenuTile> createState() => _MusicMenuTileState();
}

class _MusicMenuTileState extends State<MusicMenuTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = widget.danger && _hover
        ? palette.bad
        : widget.checked
        ? palette.accInk
        : palette.ink2;
    return InkWell(
      onTap: widget.onTap,
      mouseCursor: SystemMouseCursors.click,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onHover: (v) => setState(() => _hover = v),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _hover ? palette.hi : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            if (widget.leading != null)
              widget.leading!
            else if (widget.icon != null)
              Icon(widget.icon, size: 14, color: fg),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFont.px12_5,
                  color: widget.checked ? palette.accInk : fg,
                  fontWeight: widget.checked ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (widget.sub != null)
              Text(
                widget.sub!,
                style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
              )
            else if (widget.checked)
              Icon(LucideIcons.check, size: 13, color: palette.acc),
          ],
        ),
      ),
    );
  }
}

/// 浮层分隔线（app.css `.pop .sep`）。
class MusicMenuDivider extends StatelessWidget {
  const MusicMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6), color: palette.line);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 歌曲行
// ─────────────────────────────────────────────────────────────────────────────

/// 曲目表：推荐歌曲、歌单详情与本地曲库共用同一套表头、列宽和歌曲行。
class MusicSongTable extends ConsumerWidget {
  const MusicSongTable({
    super.key,
    required this.songs,
    this.showHeader = true,
    this.showAlbum = true,
    this.scrollable = true,
    this.controller,
    this.fromLiked = false,
    this.queueTitle,
  });

  final List<MusicSong> songs;
  final bool showHeader;
  final bool showAlbum;
  final bool scrollable;
  final ScrollController? controller;
  final bool fromLiked;
  final String? queueTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final mobile = context.isMobile;
    final header = showHeader && !mobile ? MusicSongTableHeader(showAlbum: showAlbum) : null;
    Widget row(int index) {
      final song = songs[index];
      return SongRow(
        song: song,
        index: index,
        showAlbum: showAlbum,
        current: player.current?.id == song.id,
        liked: player.likedIds.contains(song.id),
        onPlay: () {
          ref.read(playerProvider.notifier).playAll(songs, start: index, fromLiked: fromLiked, title: queueTitle);
          showAppToast(context, AppLocalizations.of(context).musicPlayingNow(song.title));
        },
      );
    }

    if (!scrollable) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [?header, for (var i = 0; i < songs.length; i++) row(i)],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?header,
        Expanded(
          child: ListView.builder(
            controller: controller,
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: songs.length,
            itemBuilder: (_, index) => row(index),
          ),
        ),
      ],
    );
  }
}

class MusicSongTableHeader extends StatelessWidget {
  const MusicSongTableHeader({super.key, this.showAlbum = true});

  final bool showAlbum;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final style = TextStyle(fontSize: AppFont.px10_5, letterSpacing: 1.2, color: palette.mut);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.musicColTitle, style: style)),
          if (showAlbum) SizedBox(width: 150, child: Text(l10n.musicAlbumTag, style: style)),
          if (showAlbum) const SizedBox(width: 12),
          SizedBox(
            width: 44,
            child: Text(l10n.musicColDuration, textAlign: TextAlign.right, style: style),
          ),
          const SizedBox(width: 4),
          const SizedBox(width: 24),
        ],
      ),
    );
  }
}

/// 歌曲行（设计稿 app.css `.row`，桌面 / 移动共用）：
/// 高 34、hover 极淡底色；序号列 22px 占位 —— hover 变播放图标、当前行变 ♪，
/// 文字不左右跳动（N23）；当前行橙色文字 + ♪；专辑定宽左对齐、时长右对齐等宽数字。
///
/// 交互（N23/N36/M11/M15）：点行播放；桌面右键弹「播放 / 下一首播放」两项精简菜单
/// （跟随鼠标坐标）；⋯ 按钮与长按弹完整菜单。默认动作已内置，
/// [onPlay] / [onOpenMenu] / [onToggleLike] / [onNext] 为调用方可选覆写钩子。
class SongRow extends ConsumerStatefulWidget {
  const SongRow({
    super.key,
    required this.song,
    required this.index,
    this.current = false,
    this.liked = false,
    this.showAlbum = false,
    this.onPlay,
    this.onOpenMenu,
    this.onToggleLike,
    this.onNext,
  });

  final MusicSong song;
  final int index;
  final bool current;
  final bool liked;

  /// 歌单详情等场景显示专辑列（宽 150，设计稿 `.row .alb`）。
  final bool showAlbum;

  /// 点行播放覆写；null = 播放 + 轻提示（musicPlayingNow）。
  final VoidCallback? onPlay;

  /// ⋯ 完整菜单覆写；null = 内置完整菜单（播放 / 下一首 / 红心 / 加入歌单 / 查看专辑 / 复制链接）。
  final VoidCallback? onOpenMenu;

  /// 红心覆写；null = toggleLike + 轻提示。
  final VoidCallback? onToggleLike;

  /// 「下一首播放」覆写；null = enqueueNext + 轻提示（musicAddedNext）。
  final VoidCallback? onNext;

  @override
  ConsumerState<SongRow> createState() => _SongRowState();
}

class _SongRowState extends ConsumerState<SongRow> {
  bool _hover = false;

  PlayerNotifier get _player => ref.read(playerProvider.notifier);

  void _defaultPlay() {
    _player.playSong(widget.song);
    final l10n = AppLocalizations.of(context);
    showAppToast(context, l10n.musicPlayingNow(widget.song.title));
  }

  void _defaultNext() {
    _player.enqueueNext(widget.song);
    showAppToast(context, AppLocalizations.of(context).musicAddedNext, tone: ToastTone.good);
  }

  void _defaultToggleLike() {
    _player.toggleLike(widget.song);
    final l10n = AppLocalizations.of(context);
    final liked = ref.read(playerProvider).likedIds.contains(widget.song.id);
    showAppToast(context, liked ? l10n.musicLiked : l10n.musicUnliked, tone: ToastTone.good);
  }

  /// 右键两项精简菜单（N36）：播放 / 下一首播放，跟随鼠标坐标。
  void _showContextMenu(Offset position) {
    final l10n = AppLocalizations.of(context);
    showAnchoredMusicPanel<void>(
      context,
      position: position,
      width: 190,
      builder: (ctx) => MusicPanelBox(
        width: 190,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MusicMenuHeader(
              text: widget.song.title,
              subtitle: widget.song.artist,
              coverSeed: widget.song.title,
              coverUrl: widget.song.coverUrl,
            ),
            MusicMenuTile(
              icon: LucideIcons.play,
              label: l10n.musicMenuPlay,
              onTap: () {
                Navigator.of(ctx).pop();
                (widget.onPlay ?? _defaultPlay)();
              },
            ),
            MusicMenuTile(
              icon: LucideIcons.cornerDownRight,
              label: l10n.musicMenuNext,
              onTap: () {
                Navigator.of(ctx).pop();
                (widget.onNext ?? _defaultNext)();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// ⋯ / 长按完整菜单（N23/M15）。
  void _showFullMenu(Offset position) {
    if (widget.onOpenMenu != null) {
      widget.onOpenMenu!();
      return;
    }
    final l10n = AppLocalizations.of(context);
    final liked = ref.read(playerProvider).likedIds.contains(widget.song.id);
    showAnchoredMusicPanel<void>(
      context,
      position: position,
      width: 210,
      builder: (ctx) => MusicPanelBox(
        width: 210,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MusicMenuHeader(
              text: widget.song.title,
              subtitle: widget.song.artist,
              coverSeed: widget.song.title,
              coverUrl: widget.song.coverUrl,
            ),
            MusicMenuTile(
              icon: LucideIcons.play,
              label: l10n.musicMenuPlay,
              onTap: () {
                Navigator.of(ctx).pop();
                (widget.onPlay ?? _defaultPlay)();
              },
            ),
            MusicMenuTile(
              icon: LucideIcons.cornerDownRight,
              label: l10n.musicMenuNext,
              onTap: () {
                Navigator.of(ctx).pop();
                (widget.onNext ?? _defaultNext)();
              },
            ),
            if (widget.song.platform != MusicPlatform.local) ...[
              const MusicMenuDivider(),
              MusicMenuTile(
                icon: LucideIcons.heart,
                label: liked ? l10n.musicMenuUnlike : l10n.musicMenuLike,
                onTap: () {
                  Navigator.of(ctx).pop();
                  (widget.onToggleLike ?? _defaultToggleLike)();
                },
              ),
            ],
            MusicMenuTile(
              icon: LucideIcons.listPlus,
              label: l10n.musicMenuAddTo,
              onTap: () {
                Navigator.of(ctx).pop();
                showAppToast(context, AppLocalizations.of(context).musicAddedToDone, tone: ToastTone.good);
              },
            ),
            MusicMenuTile(
              icon: LucideIcons.disc,
              label: l10n.musicMenuViewAlbum,
              onTap: () {
                Navigator.of(ctx).pop();
                // 详情页以专辑名展示（任务口径：可接受）；id 不存在时详情页回落首张歌单。
                GoRouter.of(context).go('/music/playlist/${Uri.encodeComponent(widget.song.album)}');
              },
            ),
            MusicMenuTile(
              icon: LucideIcons.link2,
              label: l10n.musicMenuCopyLink,
              onTap: () {
                Navigator.of(ctx).pop();
                Clipboard.setData(ClipboardData(text: 'miao-dock://song/${widget.song.id}'));
                showAppToast(context, AppLocalizations.of(context).musicCopied, tone: ToastTone.good);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final song = widget.song;
    final on = widget.current;
    // 移动端行高 48、徽标热区 36（M08：触控热区 ≥48 / ≥40）；桌面保持 34 的紧凑行。
    final mobile = context.isMobile;
    final rowHeight = mobile ? 48.0 : 34.0;

    final titleColor = on ? palette.accInk : palette.ink;
    final numColor = on ? palette.acc : palette.mut;

    Widget? trailingMore = AnimatedOpacity(
      duration: AppMotion.hover,
      opacity: mobile || _hover ? 1 : 0,
      child: SizedBox(
        width: mobile ? 36 : 24,
        height: mobile ? 36 : 24,
        child: IconButton(
          key: const ValueKey('song-row-more'),
          onPressed: () {
            final box = context.findRenderObject()! as RenderBox;
            _showFullMenu(box.localToGlobal(Offset(box.size.width - 16, 28)));
          },
          icon: Icon(LucideIcons.ellipsis, size: 15, color: palette.ink2),
          tooltip: l10n.musicRowMenuAria,
          padding: EdgeInsets.zero,
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
      ),
    );

    final row = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => (widget.onPlay ?? _defaultPlay)(),
        onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
        onLongPressStart: (details) {
          if (mobile) HapticFeedback.lightImpact(); // M11：长按成功轻震
          _showFullMenu(details.globalPosition);
        },
        child: Container(
          height: rowHeight,
          padding: EdgeInsets.symmetric(horizontal: mobile ? 4 : 10),
          decoration: BoxDecoration(
            // hover 只铺一层极淡底色（N23）；当前行不加底色，用文字色 + ♪ 表达。
            color: _hover ? palette.card.withValues(alpha: 0.6) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
          ),
          child: Row(
            children: [
              // 移动端行首显示封面（M08 行 ≥48）；桌面保持序号列（设计稿 `.row`）。
              if (mobile) ...[
                SeedCover(seed: song.title, imageUrl: song.coverUrl, size: 44, radius: 8),
                const SizedBox(width: 10),
              ],
              // 序号列 22px 占位：hover 变播放图标、当前行变 ♪，文字不跳动。
              if (!mobile)
                SizedBox(
                  width: 22,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: AppMotion.fast,
                      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                      child: _hover
                          ? Icon(LucideIcons.play, key: const ValueKey('row-play'), size: 12, color: palette.acc)
                          : Text(
                              on ? '♪' : '${widget.index + 1}',
                              key: ValueKey('row-no-${widget.index}'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: AppFont.px11,
                                color: numColor,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: mobile ? AppFont.px13 : AppFont.px11_5,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                        color: titleColor,
                      ),
                    ),
                    Text(
                      mobile && widget.showAlbum ? '${song.artist} · ${song.album}' : song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: mobile ? AppFont.px11 : AppFont.px9_5,
                        color: on ? palette.accInk.withValues(alpha: 0.85) : palette.mut,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showAlbum && !mobile)
                SizedBox(
                  width: 150,
                  child: Text(
                    song.album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px11, color: palette.ink2),
                  ),
                ),
              if (widget.showAlbum && !mobile) const SizedBox(width: 12),
              SizedBox(
                width: 44,
                child: Text(
                  formatSongDuration(song.duration),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: AppFont.px11,
                    color: palette.mut,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              trailingMore,
            ],
          ),
        ),
      ),
    );

    return Semantics(label: on ? l10n.musicCurRowAria : l10n.musicRowPlayAria(song.title), button: true, child: row);
  }
}
