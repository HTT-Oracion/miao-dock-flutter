import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/responsive.dart';
import '../../../../l10n/app_localizations.dart';
import '../../controller/music_player.dart';
import '../../controller/music_providers.dart';
import '../../controller/music_session.dart';
import '../../domain/music_models.dart';
import '../widgets/music_shared.dart';

/// 灵动岛（N13）：折叠 230×34（封面 24 + 歌名 + 波形律动 4 根）⇄ 展开 348×186
/// （大封面 / 当前歌词行 / 进度 / 传输键），320ms [AppMotion.morphCurve] 形变。
///
/// 悬停 / Tab 展开；点内容区 → 沉浸播放器；展开态右下「歌词卡 / 播放卡」切换；
/// Esc（键盘层）/ 鼠标移出收起（setIsland(false)）。播放态才渲染（由宿主挂载）。
class DynamicIsland extends ConsumerStatefulWidget {
  const DynamicIsland({super.key});

  @override
  ConsumerState<DynamicIsland> createState() => _DynamicIslandState();
}

class _DynamicIslandState extends ConsumerState<DynamicIsland> {
  bool _hover = false;
  // 展开卡片：true = 歌词卡，false = 播放卡（歌手信息）。
  bool _lyricCard = true;

  bool get _expanded => _hover || ref.watch(musicUiProvider.select((s) => s.islandOpen));

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final song = player.current;
    if (song == null) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final expanded = _expanded;

    final lyrics = ref.watch(musicRepositoryProvider).lyricsFor(song);
    var idx = 0;
    for (final (k, line) in lyrics.lines.indexed) {
      if (player.positionMs >= line.t) idx = k;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) {
        setState(() => _hover = false);
        ref.read(musicUiProvider.notifier).setIsland(false);
      },
      child: Focus(
        // Tab 聚焦即展开（N13 trigger）。
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.tab &&
              !_hover &&
              !ref.read(musicUiProvider).islandOpen) {
            ref.read(musicUiProvider.notifier).setIsland(true);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedContainer(
          duration: AppMotion.morph,
          curve: AppMotion.morphCurve,
          width: expanded ? 348 : 230,
          height: expanded ? 186 : 34,
          decoration: BoxDecoration(
            color: palette.panel,
            border: Border.all(color: palette.line2),
            borderRadius: BorderRadius.circular(expanded ? AppMetrics.radiusIslandOpen : AppMetrics.radiusPill),
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(alpha: 0.35),
                blurRadius: expanded ? 18 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          // 子件始终按目标尺寸布局：AnimatedContainer 形变过程中容器只有中间尺寸，
          // 若让子件跟着收缩，展开内容会在一帧内被压扁并触发 RenderFlex overflow。
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: expanded ? 348 : 230,
            maxWidth: expanded ? 348 : 230,
            minHeight: expanded ? 186 : 34,
            maxHeight: expanded ? 186 : 34,
            child: SizedBox(
              width: expanded ? 348 : 230,
              height: expanded ? 186 : 34,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // 点内容区 → 沉浸播放器（展开态里的传输键各自接管，不再冒泡）。
                onTap: expanded ? null : () => ref.read(musicUiProvider.notifier).setImmersive(true),
                child: Semantics(
                  label: expanded ? l10n.musicIslandCloseAria : l10n.musicIslandOpenAria,
                  button: true,
                  child: expanded
                      ? _buildExpanded(context, ref, song, lyrics, idx, l10n)
                      : _buildCollapsed(context, ref, song, l10n),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsed(BuildContext context, WidgetRef ref, MusicSong song, AppLocalizations l10n) {
    final palette = AppPalette.of(context);
    final player = ref.watch(playerProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      child: Row(
        children: [
          SeedCover(seed: song.title, imageUrl: song.coverUrl, size: 26, radius: 7),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFont.px11, fontWeight: FontWeight.w600, color: palette.ink),
            ),
          ),
          const SizedBox(width: 8),
          // 波形律动 4 根（播放时律动、暂停压平）。
          _Wave(playing: player.playing, color: palette.ink.withValues(alpha: 0.85)),
        ],
      ),
    );
  }

  Widget _buildExpanded(
    BuildContext context,
    WidgetRef ref,
    MusicSong song,
    SongLyrics lyrics,
    int idx,
    AppLocalizations l10n,
  ) {
    final palette = AppPalette.of(context);
    final player = ref.watch(playerProvider);
    final lyricLine = lyrics.lines[idx];
    final total = song.duration.inMilliseconds;
    String fmt(int ms) => formatSongDuration(Duration(milliseconds: ms));
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SeedCover(seed: song.title, imageUrl: song.coverUrl, size: 52, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 歌词卡：当前句；播放卡：音质 + 时长摘要。
          if (_lyricCard)
            Text(
              lyricLine.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w600, color: palette.accInk),
            )
          else
            Text(
              l10n.musicSongInfoLine(song.album, song.qualityLabel ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w600, color: palette.accInk),
            ),
          const SizedBox(height: 8),
          // 进度：静态比例条（拖拽交给沉浸播放器）。
          Row(
            children: [
              Text(
                fmt(player.positionMs),
                style: TextStyle(
                  fontSize: AppFont.px9_5,
                  color: palette.mut,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                  child: LinearProgressIndicator(
                    value: player.progressOf(song),
                    minHeight: 4,
                    backgroundColor: palette.hi,
                    valueColor: AlwaysStoppedAnimation(palette.acc),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                fmt(total),
                style: TextStyle(
                  fontSize: AppFont.px9_5,
                  color: palette.mut,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              _IslandBtn(
                icon: LucideIcons.skipBack,
                tip: l10n.musicPrevAria,
                onTap: () => ref.read(playerProvider.notifier).prevTrack(),
              ),
              const SizedBox(width: 12),
              _IslandBtn(
                icon: player.playing ? LucideIcons.pause : LucideIcons.play,
                tip: player.playing ? l10n.musicPauseAria : l10n.musicPlayAria,
                onTap: () => ref.read(playerProvider.notifier).toggle(),
              ),
              const SizedBox(width: 12),
              _IslandBtn(
                icon: LucideIcons.skipForward,
                tip: l10n.musicNextAria,
                onTap: () => ref.read(playerProvider.notifier).nextTrack(),
              ),
              const Spacer(),
              // 右下：「歌词卡 / 播放卡」切换（N13）。
              GestureDetector(
                onTap: () => setState(() => _lyricCard = !_lyricCard),
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                    border: Border.all(color: palette.line),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _lyricCard ? l10n.musicIslandLyricTab : l10n.musicIslandSingerTab,
                    style: TextStyle(fontSize: AppFont.px10, color: palette.ink2),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _IslandBtn(
                icon: LucideIcons.maximize2,
                tip: l10n.musicImmersiveOpenAria,
                onTap: () => ref.read(musicUiProvider.notifier).setImmersive(true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IslandBtn extends StatelessWidget {
  const _IslandBtn({required this.icon, required this.tip, required this.onTap});

  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(width: 28, height: 28, child: Icon(icon, size: 15, color: palette.ink2)),
      ),
    );
  }
}

/// 波形律动（app.css `.wave`）：4 根，播放时循环起伏、暂停压平。
class _Wave extends StatefulWidget {
  const _Wave({required this.playing, required this.color});

  final bool playing;
  final Color color;

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    if (reduce && _c.isAnimating) {
      _c.stop();
    } else if (!reduce && !_c.isAnimating) {
      _c.repeat();
    }
    return SizedBox(
      width: 17,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (_, delay) in [0.0, 0.1, 0.22, 0.06].indexed)
              Container(
                width: 2.5,
                height: widget.playing && !context.reduceMotion
                    ? 3.2 + 10.8 * (0.5 + 0.5 * math.sin((_c.value + delay) * 2 * math.pi))
                    : 3.2,
                decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
              ),
          ],
        ),
      ),
    );
  }
}
