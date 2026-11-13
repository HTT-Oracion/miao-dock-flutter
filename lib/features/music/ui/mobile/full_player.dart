import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/responsive.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../controller/music_player.dart';
import '../../controller/music_providers.dart';
import '../../controller/music_session.dart';
import '../../domain/music_models.dart';
import '../widgets/music_shared.dart';
import 'mini_bar.dart' show TapScaleButton;

/// 全屏播放器视图（M04：打开时默认光碟；评论键记住进入前的视图 prevTab —— M14）。
enum _FullTab { disc, lyrics, comments }

/// 歌词行两种固定槽高（有翻译且「译」开时更高）。
const double _lyricLineH = 52;
const double _lyricTrLineH = 74;

/// 全屏播放器（M04/M05/M06/M13/M14）。
///
/// 顶栏（收起 + 正在播放上下文 + 更多）支持下滑 >110px 跟手收起；
/// 主体三视图：光碟（黑胶 + 唱针）/ 歌词（跟随 + 手动定位）/ 评论；
/// 底部三行固定：信息（或「译」）· 进度 · 传输五键。Android 返回键 = 收起。
class FullMusicPlayer extends ConsumerStatefulWidget {
  const FullMusicPlayer({super.key, this.onMoreTap});

  /// 顶栏「更多」回调：更多抽屉由容器渲染（无 musicUiProvider 位，容器本地态）。
  final VoidCallback? onMoreTap;

  @override
  ConsumerState<FullMusicPlayer> createState() => _FullMusicPlayerState();
}

class _FullMusicPlayerState extends ConsumerState<FullMusicPlayer> with TickerProviderStateMixin {
  _FullTab _tab = _FullTab.disc;
  _FullTab _prevTab = _FullTab.disc;

  // 黑胶旋转：暂停停转、角度连续（M06）。
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26), // 设计稿 .disc 旋转周期
  )..repeat();

  // 顶栏下滑跟手收起（M04）。
  final ValueNotifier<double> _dragY = ValueNotifier(0);
  double _dragDy = 0;

  // 歌词：手动滚动定位（M05）。
  final ScrollController _lyrCtrl = ScrollController();
  bool _manual = false;
  int _seekLine = 0;
  Timer? _restoreTimer;
  int _followLine = -1;

  // 评论点赞（本地演示态，N20/M14）。
  final Set<String> _likedComments = {};

  @override
  void initState() {
    super.initState();
    final playing = ref.read(playerProvider).playing;
    if (!playing) _spin.stop();
  }

  @override
  void dispose() {
    _restoreTimer?.cancel();
    _dragY.dispose();
    _lyrCtrl.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _setTab(_FullTab t) {
    setState(() {
      if (t == _FullTab.comments && _tab != _FullTab.comments) _prevTab = _tab;
      _tab = t;
      _resetLyricManual();
    });
    if (t == _FullTab.lyrics) {
      // 进歌词即回中当前句（初始 jump，不等第一拍 tick）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _followLine = _indexOf(ref.read(playerProvider).positionMs);
        _scrollToLine(_followLine, jumpOnly: true);
      });
    }
  }

  void _toggleComments() {
    if (_tab == _FullTab.comments) {
      _setTab(_prevTab); // M14：记住来之前的视图
    } else {
      _setTab(_FullTab.comments);
    }
  }

  void _close() => ref.read(musicUiProvider.notifier).setImmersive(false);

  // ── 歌词手动滚动 ──────────────────────────────────────────────────────────
  void _resetLyricManual() {
    _restoreTimer?.cancel();
    if (!_manual) return;
    _manual = false;
    _seekLine = 0;
    setState(() {});
  }

  void _markManual() {
    _restoreTimer?.cancel();
    if (!_manual) {
      setState(() => _manual = true);
    }
  }

  void _armRestore() {
    _restoreTimer?.cancel();
    _restoreTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _resetLyricManual();
      _scrollToLine(_indexOf(ref.read(playerProvider).positionMs), jumpOnly: true);
    });
  }

  void _updateSeekLine(List<double> centers, double viewportH) {
    if (!_lyrCtrl.hasClients) return;
    final mid = _lyrCtrl.offset + viewportH / 2;
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < centers.length; i++) {
      final d = (centers[i] - mid).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best != _seekLine) setState(() => _seekLine = best);
  }

  void _scrollToLine(int line, {bool jumpOnly = false}) {
    if (!_lyrCtrl.hasClients) return;
    final vp = _lyrCtrl.position.viewportDimension;
    final offsets = _linePrefix(ref.read(playerProvider).current);
    if (line < 0 || line >= offsets.length) return;
    final centers = _lineCenters(offsets, vp * 0.3);
    final target = (centers[line] - vp / 2).clamp(0.0, _lyrCtrl.position.maxScrollExtent);
    if (jumpOnly) {
      _lyrCtrl.jumpTo(target);
    } else {
      _lyrCtrl.animateTo(target, duration: AppMotion.pageSwitch, curve: AppMotion.easeOutCubic);
    }
  }

  /// 行前缀偏移（两种固定槽高，供中心定位换算）。
  List<double> _linePrefix(MusicSong? song) {
    final lyrics = song == null ? const SongLyrics(lines: []) : ref.read(currentLyricsProvider);
    final translateOn = ref.read(musicUiProvider).translateOn;
    final offsets = <double>[0];
    for (final l in lyrics.lines) {
      final h = (translateOn && l.translation != null) ? _lyricTrLineH : _lyricLineH;
      offsets.add(offsets.last + h);
    }
    return offsets;
  }

  List<double> _lineCenters(List<double> prefix, double topPad) => [
    for (var i = 0; i < prefix.length - 1; i++) topPad + (prefix[i] + prefix[i + 1]) / 2,
  ];

  int _indexOf(int positionMs) {
    final song = ref.read(playerProvider).current;
    if (song == null) return 0;
    final lyrics = ref.read(currentLyricsProvider);
    var idx = 0;
    for (var i = 0; i < lyrics.lines.length; i++) {
      if (positionMs >= lyrics.lines[i].t) idx = i;
    }
    return idx;
  }

  // ── 进度拖拽 ──────────────────────────────────────────────────────────────
  double _dragStartRatio = 0;

  void _seekBy(double ratio) {
    ref.read(playerProvider.notifier).seekRatio(ratio.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final song = player.current;
    if (song == null) {
      // 队列被清空后仍处于沉浸态：收起回到内容（不留悬空播放器）。
      // build 期不能改 provider 状态，postFrame 收口。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
      return const SizedBox.shrink();
    }
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final style = ref.watch(playerStyleProvider);
    final translateOn = ref.watch(musicUiProvider.select((s) => s.translateOn));

    // 播放态同步旋转：暂停停转、角度连续（M06）。
    ref.listen(playerProvider.select((p) => p.playing), (prev, next) {
      // N34：减少动态效果时黑胶不转。
      if (next && !context.reduceMotion) {
        if (!_spin.isAnimating) _spin.repeat();
      } else {
        _spin.stop();
      }
    });
    // 跟随滚动：行号变化时回中（程序化滚动 dragDetails 为 null，不会误判手动）。
    ref.listen(playerProvider.select((p) => p.positionMs), (prev, next) {
      if (_manual || _tab != _FullTab.lyrics) return;
      final li = _indexOf(next);
      if (li != _followLine) {
        _followLine = li;
        _scrollToLine(li);
      }
    });

    final total = song.duration.inMilliseconds;
    final posText = formatSongDuration(Duration(milliseconds: player.positionMs));
    final totalText = formatSongDuration(song.duration);
    final liked = player.likedIds.contains(song.id);
    final modeLabel = playModeLabel(l10n, player.mode);
    final qualityText = qualityLabel(l10n, player.quality);

    return PopScope(
      // M04：Android 返回键 = 收起播放器（不是退出应用）。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      // M04：380ms 上滑进入（挂载时 0→1 一次性播放，弹层退场由容器卸载）。
      child: TweenAnimationBuilder(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: AppMotion.drawer,
        curve: AppMotion.morphCurve,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, 30 * (1 - t)), child: child),
        ),
        child: Container(
          color: palette.bg,
          child: Stack(
            children: [
              // M04 氛围层：封面主色从顶部晕开（`.m-full .bg .wash` + `.noise`），
              // 只做背景、不接手势；深浅主题下都用主题橙底压一层，避免彩色块过艳。
              Positioned.fill(
                child: IgnorePointer(child: _PlayerWash(song: song)),
              ),
              ValueListenableBuilder(
                valueListenable: _dragY,
                builder: (context, dy, child) => Opacity(
                  opacity: (1 - dy / 700).clamp(0.4, 1.0),
                  child: Transform.translate(offset: Offset(0, dy * 0.6), child: child),
                ),
                child: Column(
                  children: [
                    _topBar(context, song),
                    Expanded(child: _body(context, player, song, style, translateOn)),
                    _infoRow(context, song, l10n, liked),
                    _progressRow(context, player, song, posText, totalText, qualityText, total),
                    _ctrlRow(context, player, modeLabel),
                    SizedBox(height: 14 + MediaQuery.paddingOf(context).bottom), // M09 安全区
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 顶栏 ──────────────────────────────────────────────────────────────────
  Widget _topBar(BuildContext context, MusicSong song) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      // M04：顶栏下滑 >110px 收起（拖动跟手下移 + 淡出，未过阈值回弹）。
      onVerticalDragUpdate: (d) {
        _dragDy = (_dragDy + d.delta.dy).clamp(0.0, 300.0);
        _dragY.value = _dragDy;
      },
      onVerticalDragEnd: (_) {
        final over = _dragDy > 110;
        _dragDy = 0;
        if (over) {
          _close();
        } else {
          _dragY.value = 0;
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            TapScaleButton(
              onTap: _close,
              semantics: l10n.musicImmersiveCloseAria,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(LucideIcons.chevronDown, size: 22, color: palette.ink),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    // M04：顶栏第一行 = 当前队列来源（每日推荐 / 我喜欢的音乐 / 歌单名）；
                    // 队列为空时（单曲播放）回退到「正在播放」。
                    ref.watch(playerProvider.select((p) => p.queueTitle)) ?? l10n.musicNowPlayingTag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${song.title} · ${song.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                  ),
                ],
              ),
            ),
            TapScaleButton(
              onTap: () => widget.onMoreTap?.call(),
              semantics: l10n.musicMoreAria,
              child: SizedBox(width: 40, height: 40, child: Icon(LucideIcons.ellipsis, size: 20, color: palette.ink)),
            ),
          ],
        ),
      ),
    );
  }

  // ── 主体三视图 ────────────────────────────────────────────────────────────
  Widget _body(BuildContext context, MusicPlayerState player, MusicSong song, PlayerStyle style, bool translateOn) {
    return switch (_tab) {
      _FullTab.disc => _DiscView(
        song: song,
        spin: _spin,
        playing: player.playing,
        onTap: () => _setTab(_FullTab.lyrics),
      ),
      _FullTab.lyrics => _LyricsView(
        key: ValueKey('lyr-${song.id}-${ref.read(musicUiProvider).translateOn}'),
        song: song,
        controller: _lyrCtrl,
        manual: _manual,
        seekLine: _seekLine,
        translateOn: translateOn,
        onManualScroll: _markManual,
        onScrollEnd: () {
          if (!_manual) return;
          _updateSeekLine(
            _lineCenters(_linePrefix(song), _lyrCtrl.position.viewportDimension * 0.3),
            _lyrCtrl.position.viewportDimension,
          );
          _armRestore();
        },
        onSeekLine: (ms) {
          ref.read(playerProvider.notifier).seekMs(ms);
          _resetLyricManual();
          _followLine = _indexOf(ms);
          _scrollToLine(_followLine, jumpOnly: true);
        },
        onTapBack: () {
          // M05：定位模式下点歌词空白不返回光碟，避免误退。
          if (_manual) return;
          _setTab(_FullTab.disc);
        },
      ),
      _FullTab.comments => _CommentsView(
        songId: song.id,
        liked: _likedComments,
        onLike: (id) {
          setState(() => _likedComments.contains(id) ? _likedComments.remove(id) : _likedComments.add(id));
        },
      ),
    };
  }

  // ── 底部第一行：信息（或「译」）+ 爱心 + 评论（M13）───────────────────────
  Widget _infoRow(BuildContext context, MusicSong song, AppLocalizations l10n, bool liked) {
    final palette = AppPalette.of(context);
    final lyrics = ref.watch(currentLyricsProvider);
    final translateOn = ref.watch(musicUiProvider.select((s) => s.translateOn));
    final showTranslate = _tab == _FullTab.lyrics && lyrics.hasTranslation;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          if (showTranslate)
            TapScaleButton(
              onTap: () => ref.read(musicUiProvider.notifier).setTranslate(!translateOn),
              semantics: l10n.musicTranslateOn,
              child: Container(
                width: 44,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: translateOn ? palette.accSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
                  border: Border.all(color: translateOn ? palette.acc : palette.line2),
                ),
                child: Text(
                  l10n.musicTranslateOn,
                  style: TextStyle(
                    fontSize: AppFont.px12,
                    fontWeight: translateOn ? FontWeight.w700 : FontWeight.w400,
                    color: translateOn ? palette.accInk : palette.mut,
                  ),
                ),
              ),
            )
          else
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
                  const SizedBox(height: 1),
                  Text(
                    '${song.artist} · ${platformLabel(l10n, song.platform)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
                  ),
                ],
              ),
            ),
          if (showTranslate) const Spacer(),
          if (song.platform != MusicPlatform.local)
            TapScaleButton(
              onTap: () => ref.read(playerProvider.notifier).toggleLike(song),
              semantics: l10n.musicLikeAria,
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(LucideIcons.heart, size: 21, color: liked ? palette.bad : palette.ink),
              ),
            ),
          TapScaleButton(
            onTap: _toggleComments,
            semantics: l10n.musicTabComments,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                LucideIcons.messageCircle,
                size: 21,
                // M14：评论键在评论视图高亮。
                color: _tab == _FullTab.comments ? palette.acc : palette.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 底部第二行：进度 + 时间 / 音质胶囊（M13；热区 22px，视觉 3px 细条）────
  Widget _progressRow(
    BuildContext context,
    MusicPlayerState player,
    MusicSong song,
    String posText,
    String totalText,
    String qualityText,
    int total,
  ) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          Semantics(
            label: l10n.musicSeekAria,
            value: l10n.musicSeekText(posText, totalText),
            child: LayoutBuilder(
              builder: (context, bc) {
                final w = bc.maxWidth;
                final progress = player.progressOf(song);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _seekBy(d.localPosition.dx / w),
                  onHorizontalDragStart: (d) {
                    _dragStartRatio = (d.localPosition.dx / w).clamp(0.0, 1.0);
                    _seekBy(_dragStartRatio);
                  },
                  onHorizontalDragUpdate: (d) {
                    _dragStartRatio = (_dragStartRatio + d.delta.dx / w).clamp(0.0, 1.0);
                    _seekBy(_dragStartRatio);
                  },
                  child: Container(
                    height: 22,
                    alignment: Alignment.center,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(color: palette.hi, borderRadius: BorderRadius.circular(2)),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(color: palette.acc, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  posText,
                  style: TextStyle(
                    fontSize: AppFont.px10,
                    color: palette.mut,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: TapScaleButton(
                    onTap: () => ref.read(musicUiProvider.notifier).setQualitySheet(true),
                    semantics: l10n.musicQualityNow(qualityText),
                    child: Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      child: Text(
                        qualityText,
                        style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  totalText,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: AppFont.px10,
                    color: palette.mut,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 底部第三行：模式 / 上一曲 / 播放暂停（56 主键）/ 下一曲 / 播放列表 ────
  Widget _ctrlRow(BuildContext context, MusicPlayerState player, String modeLabel) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final playing = player.playing;
    Widget ibtn(IconData icon, double size, String semantics, VoidCallback onTap) => TapScaleButton(
      onTap: onTap,
      semantics: semantics,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Icon(icon, size: size, color: palette.ink),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // N10/M13：模式点击循环，不开抽屉。
          ibtn(playModeIcon(player.mode), 20, l10n.musicModeAria(modeLabel), () {
            ref.read(playerProvider.notifier).cycleMode();
          }),
          ibtn(LucideIcons.skipBack, 24, l10n.musicPrevAria, () => ref.read(playerProvider.notifier).prevTrack()),
          TapScaleButton(
            onTap: () => ref.read(playerProvider.notifier).toggle(),
            semantics: playing ? l10n.musicPauseAria : l10n.musicPlayAria,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: palette.acc, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(playing ? LucideIcons.pause : LucideIcons.play, size: 22, color: palette.onAcc),
            ),
          ),
          ibtn(LucideIcons.skipForward, 24, l10n.musicNextAria, () => ref.read(playerProvider.notifier).nextTrack()),
          ibtn(LucideIcons.listMusic, 20, l10n.musicSheetQueueAria, () {
            ref.read(musicUiProvider.notifier).setQueue(true);
          }),
        ],
      ),
    );
  }
}

// ── 光碟视图（M06）──────────────────────────────────────────────────────────
/// 全屏播放器的顶部氛围渐变（设计稿 `.m-full .bg`：封面色 wash 淡出 + 主色 noise）。
///
/// 用主题令牌绘制，浅色档同样成立（不写死深色值）；顶部 62% 淡出，
/// 让下方歌名 / 进度区域保持纯 bg，保证文字对比度。
class _PlayerWash extends StatelessWidget {
  const _PlayerWash({required this.song});

  final MusicSong song;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final cover = seedCoverColors(song.title);
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [cover.first.withValues(alpha: 0.42), cover.first.withValues(alpha: 0)],
                stops: const [0, 0.62],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -1),
                radius: 1.1,
                colors: [palette.accSoft.withValues(alpha: 0.6), palette.accSoft.withValues(alpha: 0)],
                stops: const [0, 0.6],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DiscView extends StatelessWidget {
  const _DiscView({required this.song, required this.spin, required this.playing, required this.onTap});

  final MusicSong song;
  final Animation<double> spin;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap, // M06：整块可点切歌词
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: l10n.musicDiscTapAria,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 260,
                  height: 260,
                  child: AnimatedBuilder(
                    animation: spin,
                    builder: (context, _) => Transform.rotate(
                      angle: spin.value * 2 * math.pi,
                      child: CustomPaint(
                        painter: _VinylPainter(line: palette.line, hi: palette.hi, base: palette.vinylBase),
                        child: Center(
                          child: SeedCover(seed: song.title, imageUrl: song.coverUrl, size: 125, radius: 999),
                        ),
                      ),
                    ),
                  ),
                ),
                // 唱针：播放时压在盘上，暂停 rotate -14° 抬起（M06）。
                // 浅色主题下盘仍是深色胶面，但唱针常常探出盘外落在浅底上 ——
                // 白色会融掉，改用 ink 并给浅色投影（设计稿 `[data-theme=light] .arm`）。
                Positioned(
                  right: 6,
                  top: 0,
                  child: AnimatedRotation(
                    turns: playing ? 0 : -14 / 360,
                    duration: AppMotion.pageSwitch,
                    curve: AppMotion.morphCurve,
                    alignment: Alignment.topRight,
                    child: SizedBox(
                      width: 118,
                      height: 118,
                      child: CustomPaint(
                        painter: _TonearmPainter(
                          ink: Theme.of(context).brightness == Brightness.light ? palette.ink : palette.coverInk,
                          shadow: palette.shadow,
                          lightTheme: Theme.of(context).brightness == Brightness.light,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.audioLines, size: 12, color: palette.mut),
                const SizedBox(width: 5),
                Text(
                  l10n.musicDiscTapAria,
                  style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 黑胶唱片纹：同心圆沟槽（设计稿 repeating-radial-gradient 的简化）。
class _VinylPainter extends CustomPainter {
  const _VinylPainter({required this.line, required this.hi, required this.base});

  final Color line;
  final Color hi;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = base); // 盘底（设计稿深色，不随主题）
    final groove = Paint()
      ..color = line.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 22; i++) {
      canvas.drawCircle(c, r * (0.30 + 0.70 * i / 22), groove);
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = hi.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(covariant _VinylPainter old) => old.line != line || old.hi != hi || old.base != base;
}

/// 唱针：白色折线 + 圆点头 + 圆盘尾（mobile.js `.arm` 的对应物）。
class _TonearmPainter extends CustomPainter {
  const _TonearmPainter({required this.ink, required this.shadow, this.lightTheme = false});

  final Color ink;
  final Color shadow;

  /// 浅色主题：唱针常探出深色胶面，投影改浅色描边（设计稿 `.arm` 的 light 变体）。
  final bool lightTheme;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    if (lightTheme) {
      // 白描边衬底：白色唱针已换深色，这层让它在胶面与浅底交界处都能读出来。
      final halo = Paint()
        ..color = shadow.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final haloPath = Path()
        ..moveTo(88 * s, 12 * s)
        ..lineTo(47 * s, 51 * s)
        ..lineTo(30 * s, 55 * s);
      canvas.drawPath(haloPath, halo);
    }
    final arm = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(88 * s, 12 * s)
      ..lineTo(47 * s, 51 * s)
      ..lineTo(30 * s, 55 * s);
    canvas.drawPath(path, arm);
    canvas.drawCircle(Offset(88 * s, 12 * s), 7 * s, Paint()..color = ink);
    canvas.save();
    canvas.translate(28 * s, 55 * s);
    canvas.rotate(-12 * math.pi / 180);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-9 * s, -4 * s, 17 * s, 9 * s), Radius.circular(2 * s)),
      Paint()..color = ink,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TonearmPainter old) => old.ink != ink || old.lightTheme != lightTheme;
}

// ── 歌词视图（M05）──────────────────────────────────────────────────────────
class _LyricsView extends ConsumerWidget {
  const _LyricsView({
    super.key,
    required this.song,
    required this.controller,
    required this.manual,
    required this.seekLine,
    required this.translateOn,
    required this.onManualScroll,
    required this.onScrollEnd,
    required this.onSeekLine,
    required this.onTapBack,
  });

  final MusicSong song;
  final ScrollController controller;
  final bool manual;
  final int seekLine;
  final bool translateOn;
  final VoidCallback onManualScroll;
  final VoidCallback onScrollEnd;
  final ValueChanged<int> onSeekLine;
  final VoidCallback onTapBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final lyrics = ref.watch(currentLyricsProvider);
    final positionMs = ref.watch(playerProvider.select((p) => p.positionMs));
    final lines = lyrics.lines;
    final cur = _indexOf(lines, positionMs);

    return Column(
      children: [
        Expanded(
          child: ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
              stops: const [0, 0.12, 0.84, 1],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            // 歌词区不显示滚动条（设计稿 `.m-lyrics{scrollbar-width:none}`）；
            // 桌面窗口跑移动布局时 Material 默认会画一条（截图实测）。
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  // 程序化回中 dragDetails == null，不会误判为手动滚动（M05 锁）。
                  if ((n is ScrollStartNotification && n.dragDetails != null) ||
                      (n is ScrollUpdateNotification && n.dragDetails != null)) {
                    onManualScroll();
                  }
                  if (n is ScrollEndNotification && manual) onScrollEnd();
                  return false;
                },
                child: GestureDetector(
                  onTap: onTapBack,
                  behavior: HitTestBehavior.opaque,
                  child: LayoutBuilder(
                    builder: (context, bc) {
                      final vp = bc.maxHeight;
                      final topPad = vp * 0.30;
                      return ListView.builder(
                        controller: controller,
                        padding: EdgeInsets.only(top: topPad, bottom: vp * 0.30),
                        itemCount: lines.length,
                        itemBuilder: (context, i) {
                          final line = lines[i];
                          final hasTr = translateOn && line.translation != null;
                          final slotH = hasTr ? _lyricTrLineH : _lyricLineH;
                          final isCur = i == cur;
                          final isSeek = manual && i == seekLine;
                          Widget content = SizedBox(
                            height: slotH,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: isSeek ? 26 : 8, vertical: 6),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        line.text,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          // 当前行加粗放大（M05）；定位行只加粗提主色不铺背景。
                                          fontSize: isSeek ? AppFont.px15 : (isCur ? AppFont.px17 : AppFont.px14),
                                          fontWeight: isCur || isSeek ? FontWeight.w700 : FontWeight.w400,
                                          color: isCur ? palette.ink : palette.ink2,
                                        ),
                                      ),
                                      if (hasTr) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          line.translation!,
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: AppFont.px11_5,
                                            color: isCur ? palette.accInk : palette.ink2.withValues(alpha: 0.75),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (isSeek) ...[
                                  // 定位卡：左时间戳 + 右 ▶ 纯 icon 无底色（M05）。
                                  Positioned(
                                    left: 2,
                                    child: Text(
                                      formatSongDuration(Duration(milliseconds: line.t)),
                                      style: TextStyle(
                                        fontSize: AppFont.px9_5,
                                        color: palette.accInk,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 2,
                                    child: GestureDetector(
                                      onTap: () => onSeekLine(line.t),
                                      behavior: HitTestBehavior.opaque,
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Icon(LucideIcons.play, size: 13, color: palette.accInk),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                          if (isCur) {
                            content = Transform.scale(scale: 1.06, child: content);
                          }
                          return Opacity(opacity: i < cur ? 0.55 : (isCur ? 1.0 : 0.82), child: content);
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        // 底部提示两态：跟随 = 轻点返回光碟；手动 = 可点 ▶ 定位（M05）。
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            manual ? l10n.musicLyricSeekHint : l10n.musicLyricBackHint,
            style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
          ),
        ),
      ],
    );
  }

  int _indexOf(List<LyricLine> lines, int positionMs) {
    var idx = 0;
    for (var i = 0; i < lines.length; i++) {
      if (positionMs >= lines[i].t) idx = i;
    }
    return idx;
  }
}

// ── 评论视图（M14/N20）──────────────────────────────────────────────────────
/// 歌词/评论走仓库直读（controller 层没有对应 provider，mobile 本地 family；
/// 记入报告：集成时若桌面端补了 controller provider，两端口径合一）。
final _songCommentsProvider = FutureProvider.autoDispose.family<List<MusicComment>, String>((ref, songId) {
  return ref.watch(musicRepositoryProvider).comments(songId);
});

class _CommentsView extends ConsumerWidget {
  const _CommentsView({required this.songId, required this.liked, required this.onLike});

  final String songId;
  final Set<String> liked;
  final ValueChanged<String> onLike;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(_songCommentsProvider(songId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SkeletonRows(rows: 4, rowHeight: 64),
      ),
      error: (e, _) => Center(
        child: Text(
          l10n.musicCommentsEmpty,
          style: TextStyle(fontSize: AppFont.px12, color: palette.mut),
        ),
      ),
      data: (comments) => ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: comments.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Text(
                    l10n.musicCommentCount(comments.length),
                    style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                  ),
                  const Spacer(),
                  Icon(LucideIcons.messageSquare, size: 11, color: palette.accInk),
                  const SizedBox(width: 4),
                  Text(
                    l10n.musicCommentHot,
                    style: TextStyle(fontSize: AppFont.px10_5, color: palette.accInk),
                  ),
                ],
              ),
            );
          }
          final c = comments[i - 1];
          final isLiked = liked.contains(c.id);
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: palette.card, shape: BoxShape.circle),
                  child: Text(
                    c.nick.isEmpty ? '?' : c.nick.substring(0, 1),
                    style: TextStyle(fontSize: AppFont.px12, color: palette.ink2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              c.nick,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFont.px11,
                                fontWeight: FontWeight.w600,
                                color: palette.ink2,
                              ),
                            ),
                          ),
                          if (c.hot) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              height: 15,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: palette.accSoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                l10n.musicCommentHotAria,
                                style: TextStyle(fontSize: AppFont.px8_5, color: palette.accInk),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        c.content,
                        style: TextStyle(fontSize: AppFont.px12_5, height: 1.6, color: palette.ink),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text(
                            c.time,
                            style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => onLike(c.id),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.heart, size: 12, color: isLiked ? palette.bad : palette.mut),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${c.likes + (isLiked ? 1 : 0)}',
                                    style: TextStyle(
                                      fontSize: AppFont.px10,
                                      color: isLiked ? palette.bad : palette.mut,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
