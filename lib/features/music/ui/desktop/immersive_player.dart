import 'dart:async';
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
import '../../../../shared/widgets/toast.dart';
import '../../domain/music_models.dart';
import '../widgets/fail_magic.dart';
import '../widgets/music_shared.dart';
import '../widgets/song_row.dart';
import 'play_bar.dart';

/// 评论（N20）：播放器「评论」页签数据源（UI 局部 family provider，任务口径）。
final musicCommentsProvider = FutureProvider.family<List<MusicComment>, String>(
  (ref, songId) => ref.watch(musicRepositoryProvider).comments(songId),
);

/// 沉浸播放器（N16–N18/N20）：整层覆盖。
///
/// · 氛围层随 playerStyle 切换 6 种（只换氛围不动布局，N17）——
///   像素级允许合理差异：cover/glass 的封面晕染用 seedCoverColors 简化，
///   vinyl 的颗粒噪点与 glass 的真实毛玻璃（BackdropFilter）未做，见报告偏差；
/// · 左 = 黑胶唱片（playing 时旋转、暂停停转）+ 曲名/歌手/专辑 + 音量滑杆；
/// · 右 = 页签（歌词/评论）+「译」开关；歌词逐句跟随、手动滚动 3 秒恢复（N18）；
/// · 底部 = 红心 / 模式循环 / 传输键 / 进度 / 队列 / 关闭。
class ImmersivePlayer extends ConsumerStatefulWidget {
  const ImmersivePlayer({super.key});

  @override
  ConsumerState<ImmersivePlayer> createState() => _ImmersivePlayerState();
}

class _ImmersivePlayerState extends ConsumerState<ImmersivePlayer> with TickerProviderStateMixin {
  bool _full = false;
  bool _tabLyrics = true;

  /// 「动态」氛围开关（仅现代样式；设计稿 `.dyn`）。
  bool _dynamicOn = true;

  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 26));
  late final AnimationController _fx = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();

  final ScrollController _lyrCtrl = ScrollController();
  bool _manual = false;
  bool _programmatic = false;
  Timer? _manualTimer;
  int _lastFollowIdx = -1;
  String? _lastSongId;

  @override
  void dispose() {
    _spin.dispose();
    _fx.dispose();
    _lyrCtrl.dispose();
    _manualTimer?.cancel();
    super.dispose();
  }

  void _syncSpin(bool playing) {
    // N34：减少动态效果时唱片不转（暂停态本来也不转）。
    if (playing && !context.reduceMotion) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  void _markManual() {
    _manualTimer?.cancel();
    if (!_manual) setState(() => _manual = true);
    _manualTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _manual = false);
        _follow();
      }
    });
  }

  /// 点击歌词行 / 切页签时重置手动状态（N18 边界，供子面板回调）。
  void resetManual() {
    _manualTimer?.cancel();
    if (_manual) setState(() => _manual = false);
  }

  void _follow() {
    if (!_lyrCtrl.hasClients) return;
    final player = ref.read(playerProvider);
    final song = player.current;
    if (song == null) return;
    final ui = ref.read(musicUiProvider);
    final lyrics = ref.read(musicRepositoryProvider).lyricsFor(song);
    final idx = _lyricIndexOf(lyrics, player.positionMs);
    final lineH = _lineHeight(lyrics, ui.translateOn);
    final target = (idx * lineH + lineH / 2 - _lyrCtrl.position.viewportDimension / 2).clamp(
      0.0,
      _lyrCtrl.position.maxScrollExtent,
    );
    _programmatic = true;
    _lyrCtrl
        .animateTo(target, duration: AppMotion.pageSwitch, curve: AppMotion.easeOutCubic)
        .whenComplete(() => _programmatic = false);
  }

  static int _lyricIndexOf(SongLyrics lyrics, int ms) {
    var i = 0;
    for (final (k, line) in lyrics.lines.indexed) {
      if (ms >= line.t) i = k;
    }
    return i;
  }

  double _lineHeight(SongLyrics lyrics, bool translateOn) {
    final withTr = lyrics.hasTranslation && translateOn;
    return withTr ? 54 : 36;
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(musicUiProvider);
    if (!ui.immersiveOpen) return const SizedBox.shrink();
    final player = ref.watch(playerProvider);
    final song = player.current;
    if (song == null) return const SizedBox.shrink();
    final skin = ref.watch(playerStyleProvider);
    final palette = AppPalette.of(context);

    _syncSpin(player.playing);

    final lyrics = ref.watch(musicRepositoryProvider).lyricsFor(song);
    final lyricIdx = _lyricIndexOf(lyrics, player.positionMs);
    final lineH = _lineHeight(lyrics, ui.translateOn);
    // 歌词自动跟随：当前行变化（或换曲）时回中；手动滚动期间不抢（N18）。
    if (_tabLyrics && !_manual && (song.id != _lastSongId || lyricIdx != _lastFollowIdx)) {
      _lastSongId = song.id;
      _lastFollowIdx = lyricIdx;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _manual || !_lyrCtrl.hasClients) return;
        final target = (lyricIdx * lineH + lineH / 2 - _lyrCtrl.position.viewportDimension / 2).clamp(
          0.0,
          _lyrCtrl.position.maxScrollExtent,
        );
        if ((_lyrCtrl.offset - target).abs() < 1) return;
        _programmatic = true;
        _lyrCtrl
            .animateTo(target, duration: AppMotion.pageSwitch, curve: AppMotion.easeOutCubic)
            .whenComplete(() => _programmatic = false);
      });
    }

    final artSize = _full ? 340.0 : 300.0;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: palette.bg),
        child: Stack(
          children: [
            Positioned.fill(
              child: _Atmosphere(skin: skin, song: song, playing: player.playing, fx: _fx),
            ),
            Column(
              children: [
                _TopBar(
                  song: song,
                  quality: player.quality,
                  full: _full,
                  lyricsOn: ui.desktopLyricsOn,
                  onClose: () => ref.read(musicUiProvider.notifier).setImmersive(false),
                  onSkin: () {
                    final box = context.findRenderObject()! as RenderBox;
                    _showSkinPopover(context, ref, box.localToGlobal(Offset(box.size.width - 300, 52)));
                  },
                  onLyrics: () => ref.read(musicUiProvider.notifier).setDesktopLyrics(!ui.desktopLyricsOn),
                  onToggleFull: () => setState(() => _full = !_full),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: _full ? 12 : 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: math.min(420.0, MediaQuery.sizeOf(context).width * 0.38),
                          child: _ArtColumn(
                            song: song,
                            quality: player.quality,
                            playing: player.playing,
                            spin: _spin,
                            size: artSize,
                            onDiscTap: () => setState(() => _tabLyrics = true),
                          ),
                        ),
                        Expanded(
                          child: _RightPanel(
                            song: song,
                            ui: ui,
                            player: player,
                            host: this,
                            setTabLyrics: (v) => setState(() => _tabLyrics = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _BottomBar(
                  song: song,
                  player: player,
                  skin: skin,
                  dynamicOn: _dynamicOn,
                  onDynamic: (v) => setState(() => _dynamicOn = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 键盘层（N33）：沉浸播放器挂在壳层后要自己接管快捷键（Esc/F 收起、
  /// 空格播放、←→ 5s、↑↓ 音量）。
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final playerN = ref.read(playerProvider.notifier);
    final player = ref.read(playerProvider);
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyF) {
      ref.read(musicUiProvider.notifier).setImmersive(false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      playerN.toggle();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      playerN.seekMs(player.positionMs + (key == LogicalKeyboardKey.arrowLeft ? -5000 : 5000));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      playerN.setVolume(player.volume + (key == LogicalKeyboardKey.arrowUp ? 5 : -5));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── 样式弹层（N17）：6 项直选 + 缩略色块 + 说明 + 勾选；「动态」开关仅现代样式出现 ──
  void _showSkinPopover(BuildContext context, WidgetRef ref, Offset position) {
    showAnchoredMusicPanel<void>(context, position: position, width: 250, builder: (ctx) => const _SkinPopoverBody());
  }

  static String _skinLabel(AppLocalizations l10n, PlayerStyle s) => switch (s) {
    PlayerStyle.modern => l10n.musicSkinModern,
    PlayerStyle.cover => l10n.musicSkinCover,
    PlayerStyle.vinyl => l10n.musicSkinVinyl,
    PlayerStyle.spectrum => l10n.musicSkinSpectrum,
    PlayerStyle.immersive => l10n.musicSkinImmersive,
    PlayerStyle.glass => l10n.musicSkinGlass,
  };

  static String _skinDesc(AppLocalizations l10n, PlayerStyle s) => switch (s) {
    PlayerStyle.modern => l10n.musicSkinModernDesc,
    PlayerStyle.cover => l10n.musicSkinCoverDesc,
    PlayerStyle.vinyl => l10n.musicSkinVinylDesc,
    PlayerStyle.spectrum => l10n.musicSkinSpectrumDesc,
    PlayerStyle.immersive => l10n.musicSkinImmersiveDesc,
    PlayerStyle.glass => l10n.musicSkinGlassDesc,
  };
}

/// 样式弹层主体：监听 playerStyleProvider 实时高亮；「动态」开关仅现代样式出现。
class _SkinPopoverBody extends ConsumerStatefulWidget {
  const _SkinPopoverBody();

  @override
  ConsumerState<_SkinPopoverBody> createState() => _SkinPopoverBodyState();
}

class _SkinPopoverBodyState extends ConsumerState<_SkinPopoverBody> {
  bool _dynamic = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(playerStyleProvider);
    return MusicPanelBox(
      width: 250,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MusicMenuHeader(text: l10n.musicSkinTitle),
          for (final s in PlayerStyle.values)
            MusicMenuTile(
              leading: _SkinSwatch(skin: s, song: ref.watch(playerProvider).current),
              label: _ImmersivePlayerState._skinLabel(l10n, s),
              sub: current == s ? null : _ImmersivePlayerState._skinDesc(l10n, s),
              checked: s == current,
              onTap: () {
                ref.read(playerStyleProvider.notifier).set(s);
                Navigator.of(context).pop();
              },
            ),
          if (current == PlayerStyle.modern) ...[
            const MusicMenuDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  Text(
                    l10n.musicSkinDynamic,
                    style: TextStyle(fontSize: AppFont.px11_5, color: AppPalette.of(context).ink2),
                  ),
                  const Spacer(),
                  AppSwitchTiny(value: _dynamic, onChanged: (v) => setState(() => _dynamic = v)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 样式缩略色块（app.css skinSwatch：用令牌色近似，见报告偏差）。
class _SkinSwatch extends StatelessWidget {
  const _SkinSwatch({required this.skin, required this.song});

  final PlayerStyle skin;
  final MusicSong? song;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final List<Color> colors = switch (skin) {
      PlayerStyle.modern => [palette.accSoft, palette.bg],
      PlayerStyle.cover => [palette.coverEnd, palette.card],
      PlayerStyle.vinyl => [palette.line2, palette.hi],
      PlayerStyle.spectrum => [palette.acc, Colors.transparent],
      PlayerStyle.immersive => [Colors.transparent, palette.accSoft],
      PlayerStyle.glass => [palette.card, palette.panel],
    };
    return Container(
      width: 22,
      height: 16,
      decoration: BoxDecoration(
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(4),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
    );
  }
}

// ── 氛围层（N17 六种；令牌 + seedCoverColors 简化实现）────────────────────────

class _Atmosphere extends StatelessWidget {
  const _Atmosphere({required this.skin, required this.song, required this.playing, required this.fx});

  final PlayerStyle skin;
  final MusicSong song;
  final bool playing;
  final Animation<double> fx;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final cover = seedCoverColors(song.title);
    switch (skin) {
      case PlayerStyle.modern:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.accSoft, palette.bg, palette.bg],
              stops: const [0, 0.52, 1],
            ),
          ),
        );
      case PlayerStyle.cover:
        // 封面主色向左晕开（mask 渐隐用 Alignment 渐变近似）。
        return Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.58,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [cover.first.withValues(alpha: 0.62), Colors.transparent],
                ),
              ),
            ),
          ),
        );
      case PlayerStyle.vinyl:
        // 大唱片 + 径向暖光；颗粒噪点省略（偏差见报告）。
        return Stack(
          children: [
            Positioned(
              right: -230,
              top: 0,
              bottom: 0,
              child: Center(
                child: CustomPaint(
                  size: const Size(660, 660),
                  painter: _DiscPainter(base: palette.line2, hi: palette.hi),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 420,
                height: 320,
                decoration: BoxDecoration(gradient: RadialGradient(colors: [palette.accSoft, Colors.transparent])),
              ),
            ),
          ],
        );
      case PlayerStyle.spectrum:
        // 26 根频谱柱，播放时随 fx 相位律动（不接真实音频，演示律动）。
        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.42,
            child: AnimatedBuilder(
              animation: fx,
              builder: (context, _) => Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final i in List.generate(26, (i) => i))
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height:
                            (0.3 + 0.7 * (0.5 + 0.5 * math.sin(fx.value * 2 * math.pi + i * 0.7))) *
                            MediaQuery.sizeOf(context).height *
                            0.4,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [palette.acc.withValues(alpha: 0.22), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      case PlayerStyle.immersive:
        // 同心涟漪：三环错相扩散。
        return AnimatedBuilder(
          animation: fx,
          builder: (context, _) => Stack(
            children: [
              for (final (_, delay) in [0.0, 0.33, 0.66].indexed)
                Center(
                  child: Transform.scale(
                    scale: 0.2 + 1.3 * _phase(fx.value, delay),
                    child: Container(
                      width: MediaQuery.sizeOf(context).height,
                      height: MediaQuery.sizeOf(context).height,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.acc.withValues(alpha: 0.42 * (1 - _phase(fx.value, delay)))),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      case PlayerStyle.glass:
        // 雾面：封面晕染 + 半透明雾层（真实 BackdropFilter 略，见报告偏差）。
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [cover.first.withValues(alpha: 0.5), cover.last.withValues(alpha: 0.35)],
                  ),
                ),
              ),
            ),
            Positioned.fill(child: ColoredBox(color: palette.bg.withValues(alpha: 0.55))),
          ],
        );
    }
  }

  static double _phase(double t, double delay) => ((t + delay) % 1.0);
}

class _DiscPainter extends CustomPainter {
  const _DiscPainter({required this.base, required this.hi});

  final Color base;
  final Color hi;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    // 盘体（设计稿 viny 深色实心圆，不随主题）。
    canvas.drawCircle(c, r, Paint()..color = base);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var i = 0; i < 60; i++) {
      ring.color = i.isEven ? hi.withValues(alpha: 0.28) : hi.withValues(alpha: 0.16);
      canvas.drawCircle(c, r - i * (r / 62), ring);
    }
    canvas.drawCircle(c, 60, Paint()..color = hi.withValues(alpha: 0.08));
  }

  @override
  bool shouldRepaint(covariant _DiscPainter old) => false;
}

// ── 顶栏 ─────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.song,
    required this.quality,
    required this.full,
    required this.lyricsOn,
    required this.onClose,
    required this.onSkin,
    required this.onLyrics,
    required this.onToggleFull,
  });

  final MusicSong song;
  final QualityTier quality;
  final bool full;
  final bool lyricsOn;
  final VoidCallback onClose;
  final VoidCallback onSkin;
  final VoidCallback onLyrics;
  final VoidCallback onToggleFull;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    Widget ibtn(IconData icon, String tip, VoidCallback onTap, {bool on = false}) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: palette.card.withValues(alpha: 0.6),
          border: Border.all(color: on ? palette.acc : palette.line),
          borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
        ),
        child: Icon(icon, size: 16, color: on ? palette.acc : palette.ink2),
      ),
    );
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 16),
          ibtn(LucideIcons.chevronDown, l10n.musicImmersiveCloseAria, onClose),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.musicNowPlayingTag,
                  style: TextStyle(
                    fontSize: AppFont.px11,
                    letterSpacing: 1.4,
                    color: palette.mut,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  l10n.musicPlatformQuality(platformLabel(l10n, song.platform), qualityLabel(l10n, quality)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFont.px10_5, color: palette.ink2),
                ),
              ],
            ),
          ),
          ibtn(LucideIcons.palette, l10n.musicSkinTitle, onSkin),
          const SizedBox(width: 6),
          ibtn(LucideIcons.monitorSpeaker, l10n.titleDesktopLyrics, onLyrics, on: lyricsOn),
          const SizedBox(width: 6),
          ibtn(full ? LucideIcons.minimize2 : LucideIcons.maximize2, l10n.musicFullscreenAria, onToggleFull),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

// ── 左列：黑胶 + 信息 + 音量 ────────────────────────────────────────────────

class _ArtColumn extends StatelessWidget {
  const _ArtColumn({
    required this.song,
    required this.quality,
    required this.playing,
    required this.spin,
    required this.size,
    required this.onDiscTap,
  });

  final MusicSong song;
  final QualityTier quality;
  final bool playing;
  final Animation<double> spin;
  final double size;
  final VoidCallback onDiscTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 黑胶唱片：播放时旋转、暂停停转（N16 覆盖项）；中心封面 SeedCover。
        GestureDetector(
          onTap: onDiscTap,
          child: Semantics(
            label: l10n.musicDiscTapAria,
            button: true,
            child: SizedBox(
              width: size * 1.16,
              height: size * 1.16,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 只转唱片沟槽；方形封面保持正立（设计稿 .art-stack 的封套不转）。
                  AnimatedBuilder(
                    animation: spin,
                    builder: (context, _) => Transform.rotate(
                      angle: spin.value * 2 * math.pi,
                      child: CustomPaint(
                        size: Size.square(size * 1.16),
                        painter: _DiscPainter(base: palette.vinylBase, hi: palette.hi),
                      ),
                    ),
                  ),
                  SeedCover(seed: song.title, imageUrl: song.coverUrl, size: size, radius: AppMetrics.radiusCardLg),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 36),
        Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: AppFont.px19,
            fontWeight: FontWeight.w800,
            color: palette.ink,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.musicSongInfoLine(song.artist, song.album),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: AppFont.px12, color: palette.mut),
        ),
        const SizedBox(height: 10),
        // 标签行（设计稿 `.m-tags`）：音质 / 时长 / 音源。
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MetaChip(label: qualityLabel(l10n, quality)),
            const SizedBox(width: 6),
            _MetaChip(label: formatSongDuration(song.duration)),
            const SizedBox(width: 6),
            _MetaChip(label: platformLabel(l10n, song.platform), icon: LucideIcons.headphones, accent: true),
          ],
        ),
      ],
    );
  }
}

/// 沉浸播放器信息行小标签（设计稿 `.chip`）。
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.icon, this.accent = false});

  final String label;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: accent ? palette.accSoft : palette.card,
        border: Border.all(color: accent ? palette.acc.withValues(alpha: 0.35) : palette.line),
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: accent ? palette.accInk : palette.ink2),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: AppFont.px9_5,
              color: accent ? palette.accInk : palette.ink2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImmersiveVolume extends ConsumerWidget {
  const _ImmersiveVolume({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final palette = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => ref.read(playerProvider.notifier).toggleMute(),
          child: Tooltip(
            message: player.muted
                ? AppLocalizations.of(context).musicVolumeMute
                : AppLocalizations.of(context).musicVolumeUnmute,
            child: Icon(
              player.muted ? LucideIcons.volumeX : (player.volume > 55 ? LucideIcons.volume2 : LucideIcons.volume1),
              size: 17,
              color: palette.ink2,
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 70,
            height: 18,
            child: MusicSeek(
              thin: true,
              value: player.muted ? 0 : player.volume / 100,
              totalMs: 100,
              showTip: false,
              onRatio: (double r) => ref.read(playerProvider.notifier).setVolume((r * 100).round()),
            ),
          ),
        ],
      ],
    );
  }
}

// ── 右列：页签（歌词 / 评论）+ 译开关 ────────────────────────────────────────

class _RightPanel extends ConsumerWidget {
  const _RightPanel({
    required this.song,
    required this.ui,
    required this.player,
    required this.host,
    required this.setTabLyrics,
  });

  final MusicSong song;
  final MusicUiState ui;
  final MusicPlayerState player;
  final _ImmersivePlayerState host;

  /// 页签切换（经由宿主 setState，避免外部直接调用受保护成员）。
  final ValueChanged<bool> setTabLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final showLyrics = host._tabLyrics;
    final manual = host._manual;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 「译」开关（N18）：双语歌词显隐。
                GestureDetector(
                  onTap: () => ref.read(musicUiProvider.notifier).setTranslate(!ui.translateOn),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: ui.translateOn ? palette.accSoft : Colors.transparent,
                      border: Border.all(color: ui.translateOn ? palette.acc.withValues(alpha: 0.55) : palette.line2),
                      borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      l10n.musicTranslateOn,
                      style: TextStyle(
                        fontSize: AppFont.px12,
                        fontWeight: FontWeight.w600,
                        color: ui.translateOn ? palette.accInk : palette.ink2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _TabPill(label: l10n.musicTabLyrics, on: showLyrics, onTap: () => setTabLyrics(true)),
                _TabPill(label: l10n.musicTabComments, on: !showLyrics, onTap: () => setTabLyrics(false)),
              ],
            ),
            // 跟随状态标签（N18）：歌词页签时右上角显示。
            if (showLyrics)
              Positioned(
                right: 2,
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: manual ? palette.warn.withValues(alpha: 0.14) : palette.card,
                    border: Border.all(color: manual ? palette.warn.withValues(alpha: 0.5) : palette.line),
                    borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    manual ? l10n.musicLyricManual : l10n.musicLyricAuto,
                    style: TextStyle(
                      fontSize: AppFont.px10,
                      fontWeight: FontWeight.w600,
                      color: manual ? palette.warn : palette.mut,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: showLyrics ? _LyricsView(host: host) : _CommentsView(songId: song.id),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: on ? palette.card : Colors.transparent,
          borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppFont.px12,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? palette.ink : palette.ink2,
          ),
        ),
      ),
    );
  }
}

/// 歌词视图（N18）：逐句跟随、当前行橙加粗放大、唱过行降透明、点击行跳转、
/// 手动滚动暂停跟随 3 秒恢复；上下边缘遮罩渐隐。
class _LyricsView extends ConsumerWidget {
  const _LyricsView({required this.host});

  /// 只读访问宿主的滚动控制器 / 手动态；写操作经 [host.resetManual] 等方法。
  final _ImmersivePlayerState host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final player = ref.watch(playerProvider);
    final ui = ref.watch(musicUiProvider);
    final song = player.current!;
    final lyrics = ref.watch(musicRepositoryProvider).lyricsFor(song);
    final withTr = lyrics.hasTranslation && ui.translateOn;
    final lineH = host._lineHeight(lyrics, ui.translateOn);
    final idx = _ImmersivePlayerState._lyricIndexOf(lyrics, player.positionMs);

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // 手动滚动侦测：程序化回中期间忽略（防把自动跟随误判成手动）。
        if (n is ScrollUpdateNotification && !host._programmatic && n.dragDetails != null) {
          host._markManual();
        }
        return false;
      },
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.12, 0.86, 1],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          controller: host._lyrCtrl,
          itemExtent: lineH,
          padding: EdgeInsets.symmetric(vertical: MediaQuery.sizeOf(context).height * 0.16, horizontal: 6),
          itemCount: lyrics.lines.length,
          itemBuilder: (_, i) {
            final line = lyrics.lines[i];
            final on = i == idx;
            final past = i < idx;
            final mainColor = on ? palette.acc : (past ? palette.ink2.withValues(alpha: 0.42) : palette.ink2);
            // N18：悬停行变蓝提示可点；鼠标离开恢复（用状态色 blue，不改正文色纪律 ——
            // 歌词行是可交互元素，不是「用彩色表达状态」）。
            return _HoverLyricLine(
              lineHeight: lineH,
              onTap: () {
                // 点击行 seek 并重置手动状态（N18 边界）。
                host.resetManual();
                ref.read(playerProvider.notifier).seekMs(line.t);
              },
              builder: (hover) => Container(
                height: lineH,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      line.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: on ? AppFont.px17 : AppFont.px14,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                        color: hover && !on ? palette.blue : mainColor,
                      ),
                    ),
                    if (withTr && line.translation != null)
                      Text(
                        line.translation!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppFont.px11_5,
                          color: on ? palette.accInk.withValues(alpha: 0.9) : palette.ink2.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 歌词行 hover 包装（N18）：鼠标进入时把文字提蓝，离开恢复。
///
/// 不用 InkWell：歌词行没有底色 / 水波纹，只要颜色提示，避免在透明区域画 Material 层。
class _HoverLyricLine extends StatefulWidget {
  const _HoverLyricLine({required this.lineHeight, required this.onTap, required this.builder});

  final double lineHeight;
  final VoidCallback onTap;
  final Widget Function(bool hover) builder;

  @override
  State<_HoverLyricLine> createState() => _HoverLyricLineState();
}

class _HoverLyricLineState extends State<_HoverLyricLine> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: widget.builder(_hover)),
    );
  }
}

/// 评论视图（N20）：头像圈 + 昵称 + 内容 + 时间 + 点赞 toggle +1；热门角标。
class _CommentsView extends ConsumerWidget {
  const _CommentsView({required this.songId});

  final String songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final comments = ref.watch(musicCommentsProvider(songId));
    return comments.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(
        child: FailMagicCircle(
          reason: l10n.musicFailReasonNetwork,
          lastSyncLabel: l10n.musicFailLastSync(_hhmm()),
          queueHint: l10n.musicFailQueueHint(ref.watch(playerProvider).queue.length),
          retryLabel: l10n.musicRetry,
          onRetry: () => ref.invalidate(musicCommentsProvider(songId)),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text(
              l10n.musicCommentsEmpty,
              style: TextStyle(fontSize: AppFont.px12, color: palette.mut),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final c = list[i];
            final isLiked = ref.watch(_CommentLikeNotifier.provider).contains(c.id);
            return Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: palette.accSoft,
                    child: Text(
                      c.nick.isEmpty ? '?' : c.nick.substring(0, 1),
                      style: TextStyle(fontSize: AppFont.px11_5, fontWeight: FontWeight.w700, color: palette.accInk),
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
                              Tooltip(
                                message: l10n.musicCommentHotAria,
                                child: Container(
                                  height: 16,
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  decoration: BoxDecoration(
                                    color: palette.accSoft,
                                    borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                                  ),
                                  child: Center(
                                    child: Text(
                                      l10n.musicCommentHotAria.substring(0, 2),
                                      style: TextStyle(
                                        fontSize: AppFont.px9,
                                        fontWeight: FontWeight.w700,
                                        color: palette.accInk,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.content,
                          style: TextStyle(fontSize: AppFont.px12, height: 1.6, color: palette.ink),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              c.time,
                              style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                ref.read(_CommentLikeNotifier.provider.notifier).toggle(c.id);
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.heart, size: 11, color: isLiked ? palette.bad : palette.mut),
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
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static String _hhmm() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

/// 评论点赞内存态（红心 toggle 变红 +1）。
class _CommentLikeNotifier extends Notifier<Set<String>> {
  static final provider = NotifierProvider<_CommentLikeNotifier, Set<String>>(_CommentLikeNotifier.new);

  @override
  Set<String> build() => const {};

  void toggle(String id) {
    final next = {...state};
    next.contains(id) ? next.remove(id) : next.add(id);
    state = next;
  }
}

// ── 底部控制条 ───────────────────────────────────────────────────────────────

class _BottomBar extends ConsumerWidget {
  const _BottomBar({
    required this.song,
    required this.player,
    required this.skin,
    required this.dynamicOn,
    required this.onDynamic,
  });

  final MusicSong song;
  final MusicPlayerState player;
  final PlayerStyle skin;
  final bool dynamicOn;
  final ValueChanged<bool> onDynamic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final liked = player.likedIds.contains(song.id);
    final wide = MediaQuery.sizeOf(context).width >= 1120;
    final ui = ref.watch(musicUiProvider);

    Widget ibtn(IconData icon, String tip, VoidCallback onTap, {double size = 16, bool on = false}) => Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: size, color: on ? palette.acc : palette.ink2),
        ),
      ),
    );

    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.72),
        border: Border(top: BorderSide(color: palette.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          SizedBox(
            width: 190,
            child: Row(
              children: [
                ibtn(
                  LucideIcons.heart,
                  l10n.musicLikeAria,
                  () => ref.read(playerProvider.notifier).toggleLike(song),
                  size: 17,
                  on: liked,
                ),
                const SizedBox(width: 2),
                ibtn(LucideIcons.palette, l10n.musicSkinTitle, () => _openSkin(context)),
                // 「动态」仅在现代样式出现（N17 边界）。
                if (skin == PlayerStyle.modern) ...[
                  const SizedBox(width: 6),
                  Text(
                    l10n.musicDynamicLabel,
                    style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                  ),
                  const SizedBox(width: 6),
                  AppSwitchTiny(value: dynamicOn, onChanged: onDynamic),
                ],
              ],
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ibtn(
                      playModeIcon(player.mode),
                      l10n.musicModeAria(playModeLabel(l10n, player.mode)),
                      () => ref.read(playerProvider.notifier).cycleMode(),
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    ibtn(
                      LucideIcons.skipBack,
                      l10n.musicPrevAria,
                      () => ref.read(playerProvider.notifier).prevTrack(),
                      size: 19,
                    ),
                    GestureDetector(
                      onTap: () => ref.read(playerProvider.notifier).toggle(),
                      child: Tooltip(
                        message: player.playing ? l10n.musicPauseAria : l10n.musicPlayAria,
                        child: Container(
                          width: 52,
                          height: 52,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: palette.acc),
                          child: Icon(
                            player.playing ? LucideIcons.pause : LucideIcons.play,
                            size: 20,
                            color: palette.onAcc,
                          ),
                        ),
                      ),
                    ),
                    ibtn(
                      LucideIcons.skipForward,
                      l10n.musicNextAria,
                      () => ref.read(playerProvider.notifier).nextTrack(),
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    // 音量（设计稿 `.vol`：图标 + 滑出滑杆；移动端用系统音量，不出现）。
                    _ImmersiveVolume(compact: !wide),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 18,
                  child: Row(
                    children: [
                      MusicTimeText(_fmt(player.positionMs)),
                      const SizedBox(width: 9),
                      Expanded(
                        child: MusicSeek(
                          value: player.progressOf(song),
                          totalMs: song.duration.inMilliseconds,
                          onRatio: (double r) => ref.read(playerProvider.notifier).seekRatio(r),
                        ),
                      ),
                      const SizedBox(width: 9),
                      MusicTimeText(_fmt(song.duration.inMilliseconds)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: wide ? 210 : 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 音质胶囊（N11）；窄窗隐藏（N32 逐级隐藏）。
                if (wide) ...[
                  Tooltip(
                    message: l10n.musicQualityAria,
                    child: GestureDetector(
                      onTap: () => _openQuality(context),
                      child: Container(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.accSoft,
                          border: Border.all(color: palette.acc.withValues(alpha: 0.35)),
                          borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
                        ),
                        child: Text(
                          qualityLabel(l10n, player.quality),
                          style: TextStyle(fontSize: AppFont.px9_5, fontWeight: FontWeight.w700, color: palette.accInk),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  ibtn(
                    LucideIcons.monitorSpeaker,
                    l10n.titleDesktopLyrics,
                    () => ref.read(musicUiProvider.notifier).setDesktopLyrics(!ui.desktopLyricsOn),
                    on: ui.desktopLyricsOn,
                  ),
                  ibtn(
                    LucideIcons.settings,
                    l10n.musicDlSettingsAria,
                    () => ref.read(musicUiProvider.notifier).setLyricsSettings(true),
                    size: 15,
                  ),
                ],
                ibtn(
                  LucideIcons.listMusic,
                  l10n.musicSheetQueueAria,
                  () => ref.read(musicUiProvider.notifier).setQueue(!ui.queueOpen),
                  on: ui.queueOpen,
                ),
                ibtn(LucideIcons.x, l10n.musicClosePlayer, () => ref.read(playerProvider.notifier).closePlayer()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 样式弹层（与顶栏同一个宿主弹层，锚点按底栏按钮估算）。
  void _openSkin(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    showAnchoredMusicPanel<void>(
      context,
      position: Offset(22, size.height - 330),
      width: 250,
      builder: (_) => const _SkinPopoverBody(),
    );
  }

  /// 音质弹层（N11）：5 档 + 当前档；点选即生效并关闭。
  void _openQuality(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final l10n = AppLocalizations.of(context);
    showAnchoredMusicPanel<void>(
      context,
      position: Offset(size.width - 300, size.height - 330),
      width: 230,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final current = ref.watch(playerProvider.select((p) => p.quality));
          return MusicPanelBox(
            width: 230,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MusicMenuHeader(
                  text: l10n.musicQualitySheetTitle,
                  trailing: l10n.musicQualityNow(qualityLabel(l10n, current)),
                ),
                for (final q in QualityTier.values)
                  MusicMenuTile(
                    icon: q == current ? LucideIcons.check : LucideIcons.music,
                    label: qualityLabel(l10n, q),
                    checked: q == current,
                    onTap: () {
                      ref.read(playerProvider.notifier).setQuality(q);
                      Navigator.of(ctx).pop();
                      showAppToast(context, l10n.musicQualityNow(qualityLabel(l10n, q)));
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _fmt(int ms) => formatSongDuration(Duration(milliseconds: ms));
}

/// 迷你开关（样式弹层「动态」行）。
class AppSwitchTiny extends StatelessWidget {
  const AppSwitchTiny({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: AppMotion.hover,
        width: 34,
        height: 19,
        decoration: BoxDecoration(
          color: value ? palette.acc : palette.hi,
          border: Border.all(color: value ? Colors.transparent : palette.line2),
          borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
        ),
        child: AnimatedAlign(
          duration: AppMotion.hover,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 13,
            height: 13,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, color: value ? palette.onAcc : palette.mut),
          ),
        ),
      ),
    );
  }
}
