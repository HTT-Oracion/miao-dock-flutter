import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_player.dart';
import '../../controller/music_session.dart';
import '../../domain/music_models.dart';
import '../widgets/music_shared.dart';
import '../widgets/song_row.dart';

/// 播放条（设计稿 `.d-pb`，高 56）：panel 底 + 上边框。
///
/// 左 = 封面(36) + 歌名/歌手两行（点击进沉浸播放器）+ 红心；
/// 中 = 上一曲 / 播放暂停(36 橙圆底) / 下一曲 + 可拖拽进度（悬停时间气泡、拖拽轨道变粗，N09）+ 等宽数字时间；
/// 右 = 模式（点击循环，N10）/ 音质胶囊（弹层 5 档，N11）/ 音量（悬停滑出滑杆、点图标静音，N12）/
///      桌面歌词开关（开启描边橙，N19）+ 设置齿轮 / 队列（开启高亮，N14）/ 关闭。
///
/// 窄窗（< 1120，N32 lg 档）隐藏桌面歌词与音质入口；队列为空时整条不渲染。
class MusicPlayBar extends ConsumerWidget {
  const MusicPlayBar({super.key});

  static const double height = 56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final song = player.current;
    if (song == null) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final ui = ref.watch(musicUiProvider);
    final liked = player.likedIds.contains(song.id);

    return LayoutBuilder(
      builder: (context, box) {
        // N32 三档：lg ≥1120 全量；md 900–1119 收起灵动岛与音质胶囊；
        // sm <900 再收掉音量滑杆（移动布局没有位置，桌面窄窗同样让位）。
        final wide = box.maxWidth >= AppMetrics.musicIslandBreakpoint;
        final showVolume = box.maxWidth >= AppMetrics.musicNarrowBreakpoint;
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: palette.panel,
            border: Border(top: BorderSide(color: palette.line)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 250,
                child: Row(
                  children: [
                    // 封面 / 歌名点击 → 沉浸播放器（N16）。
                    GestureDetector(
                      onTap: () => ref.read(musicUiProvider.notifier).setImmersive(true),
                      child: SeedCover(key: const ValueKey('playbar-cover'), seed: song.title, size: 36, radius: 7),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => ref.read(musicUiProvider.notifier).setImmersive(true),
                            child: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFont.px12_5,
                                fontWeight: FontWeight.w600,
                                color: palette.ink,
                              ),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.only(right: 5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: platformBrands[song.platform]?.color ?? palette.mut,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (song.platform != MusicPlatform.local)
                      _BarIcon(
                        icon: LucideIcons.heart,
                        tooltip: liked ? l10n.musicMenuUnlike : l10n.musicMenuLike,
                        color: liked ? palette.bad : null,
                        onTap: () => ref.read(playerProvider.notifier).toggleLike(song),
                      ),
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
                        _BarIcon(
                          key: const ValueKey('music-mode-btn'),
                          icon: playModeIcon(player.mode),
                          tooltip: l10n.musicModeAria(playModeLabel(l10n, player.mode)),
                          onTap: () => ref.read(playerProvider.notifier).cycleMode(),
                        ),
                        _BarIcon(
                          icon: LucideIcons.skipBack,
                          tooltip: l10n.musicPrevAria,
                          onTap: () => ref.read(playerProvider.notifier).prevTrack(),
                        ),
                        // 主播放键：36 橙圆底（设计稿 .playbtn）。
                        GestureDetector(
                          onTap: () => ref.read(playerProvider.notifier).toggle(),
                          child: Tooltip(
                            message: player.playing ? l10n.musicPauseAria : l10n.musicPlayAria,
                            child: Container(
                              width: 36,
                              height: 36,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(shape: BoxShape.circle, color: palette.acc),
                              child: Icon(
                                player.playing ? LucideIcons.pause : LucideIcons.play,
                                size: 15,
                                color: palette.onAcc,
                              ),
                            ),
                          ),
                        ),
                        _BarIcon(
                          icon: LucideIcons.skipForward,
                          tooltip: l10n.musicNextAria,
                          onTap: () => ref.read(playerProvider.notifier).nextTrack(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
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
                              onRatio: (r) => ref.read(playerProvider.notifier).seekRatio(r),
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
                width: wide ? 334 : 258,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (wide) ...[
                      _QualityChip(
                        label: qualityLabel(l10n, player.quality),
                        onTap: () {
                          final box2 = context.findRenderObject()! as RenderBox;
                          final pos = box2.localToGlobal(const Offset(-8, 24));
                          _showQualityPopover(context, ref, pos);
                        },
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (showVolume) _VolumeRegion(),
                    if (wide) ...[
                      _BarIcon(
                        icon: LucideIcons.monitorSpeaker,
                        tooltip: l10n.musicDlToggleAria,
                        on: ui.desktopLyricsOn,
                        onTap: () => ref.read(musicUiProvider.notifier).setDesktopLyrics(!ui.desktopLyricsOn),
                      ),
                      _BarIcon(
                        icon: LucideIcons.settings,
                        tooltip: l10n.musicDlSettingsAria,
                        onTap: () => ref.read(musicUiProvider.notifier).setLyricsSettings(true),
                      ),
                    ],
                    _BarIcon(
                      key: const ValueKey('music-queue-btn'),
                      icon: LucideIcons.listMusic,
                      tooltip: l10n.musicSheetQueueAria,
                      on: ui.queueOpen,
                      onTap: () => ref.read(musicUiProvider.notifier).setQueue(!ui.queueOpen),
                    ),
                    _BarIcon(
                      icon: LucideIcons.x,
                      tooltip: l10n.musicClosePlayer,
                      onTap: () => ref.read(playerProvider.notifier).closePlayer(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _fmt(int ms) => formatSongDuration(Duration(milliseconds: ms));
}

// ── 右侧按钮与弹层 ───────────────────────────────────────────────────────────

/// 播放条图标按钮（app.css `.ibtn`）：32×32，hover 提亮，可选开启态（橙底橙字）。
class _BarIcon extends StatelessWidget {
  const _BarIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.on = false,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool on;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: on ? palette.accSoft : Colors.transparent,
            border: on ? Border.all(color: palette.acc.withValues(alpha: 0.55)) : null,
            borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
          ),
          child: Icon(icon, size: 16, color: color ?? (on ? palette.acc : palette.ink2)),
        ),
      ),
    );
  }
}

/// 音质胶囊（app.css `.qchip`）：accSoft 底 + accInk 字。
class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: AppLocalizations.of(context).musicQualityAria,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.accSoft,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.transparent),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppFont.px9_5,
              fontWeight: FontWeight.w700,
              color: palette.accInk,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

/// 音质弹层（N11）：5 档列表，含码率与会员标注、当前档高亮。
Future<void> _showQualityPopover(BuildContext context, WidgetRef ref, Offset position) async {
  final l10n = AppLocalizations.of(context);
  final current = ref.read(playerProvider).quality;
  await showAnchoredMusicPanel<void>(
    context,
    position: position,
    width: 250,
    builder: (ctx) => MusicPanelBox(
      width: 250,
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
              icon: LucideIcons.audioLines,
              label: qualityLabel(l10n, q),
              sub: '${qualitySub(l10n, q)}${qualityLimit(l10n, q) == null ? '' : ' · ${qualityLimit(l10n, q)}'}',
              checked: q == current,
              onTap: () {
                Navigator.of(ctx).pop();
                ref.read(playerProvider.notifier).setQuality(q);
                showAppToast(ctx, l10n.musicQualityNow(qualityLabel(l10n, q)));
              },
            ),
        ],
      ),
    ),
  );
}

/// 音量区（N12）：图标点击静音（volume-x），悬停滑出滑杆；记住原音量由 controller 负责。
class _VolumeRegion extends ConsumerStatefulWidget {
  @override
  ConsumerState<_VolumeRegion> createState() => _VolumeRegionState();
}

class _VolumeRegionState extends ConsumerState<_VolumeRegion> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final player = ref.watch(playerProvider);
    final icon = player.muted
        ? LucideIcons.volumeX
        : player.volume > 55
        ? LucideIcons.volume2
        : LucideIcons.volume1;
    // 外层恒定占 108px：滑杆展开时不再把右侧队列/关闭按钮挤出固定区域。
    return SizedBox(
      key: const ValueKey('music-volume-region'),
      width: 108,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Row(
          children: [
            _BarIcon(
              icon: icon,
              tooltip: player.muted ? l10n.musicVolumeUnmute : l10n.musicVolumeMute,
              onTap: () => ref.read(playerProvider.notifier).toggleMute(),
            ),
            ClipRect(
              child: AnimatedContainer(
                duration: AppMotion.hover,
                curve: AppMotion.morphCurve,
                width: _hover ? 74 : 0,
                height: 18,
                child: MusicSeek(
                  thin: true,
                  value: player.muted ? 0 : player.volume / 100,
                  totalMs: 100,
                  showTip: false,
                  onRatio: (r) => ref.read(playerProvider.notifier).setVolume((r * 100).round()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 进度条（播放条 / 沉浸播放器 / 灵动岛共用）────────────────────────────────

/// 可拖拽进度条（N09）：悬停时间气泡、拖拽时轨道 4→6px、旋钮放大；
/// 拖拽实时跟随指针，[onRatio] 以 0–1 回调（seekRatio / setVolume 由调用方接）。
class MusicSeek extends StatefulWidget {
  const MusicSeek({
    super.key,
    required this.value,
    required this.totalMs,
    required this.onRatio,
    this.height = 18,
    this.thin = false,
    this.showTip = true,
  });

  /// 当前比例 0–1。
  final double value;

  /// 总时长（气泡文本用；音量条传 100 → 显示成 0:00~1:40? 不可，音量传 totalMs=100 时
  /// 由 [thin] 关闭气泡，文本不展示）。
  final int totalMs;

  final ValueChanged<double> onRatio;

  /// 热区高度（视觉轨道恒 4px，hover/drag 6px）。
  final double height;

  /// 音量条等细条：无旋钮、无气泡。
  final bool thin;

  final bool showTip;

  @override
  State<MusicSeek> createState() => _MusicSeekState();
}

class _MusicSeekState extends State<MusicSeek> {
  bool _hover = false;
  bool _dragging = false;
  double _hoverRatio = 0;
  double _dragRatio = 0;

  double get _ratio => (_dragging ? _dragRatio : widget.value).clamp(0.0, 1.0);

  String _tipText(double ratio) {
    final sec = (widget.totalMs * ratio / 1000).round();
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double _ratioOfLocal(Offset local) {
    final box = context.findRenderObject()! as RenderBox;
    return (local.dx / box.size.width).clamp(0.0, 1.0);
  }

  void _applyRatio(double ratio, {required bool drag}) {
    setState(() {
      if (drag) {
        _dragging = true;
        _dragRatio = ratio;
      } else {
        _hoverRatio = ratio;
      }
    });
    if (drag) widget.onRatio(ratio);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final thick = (_hover || _dragging) && !widget.thin ? 6.0 : 4.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _dragging = false;
      }),
      onHover: (e) => _applyRatio(_ratioOfLocal(e.localPosition), drag: false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final r = _ratioOfLocal(d.localPosition);
          _applyRatio(r, drag: false);
          // 点击也要 seek（不只是拖拽）。
          widget.onRatio(r);
        },
        onHorizontalDragStart: (d) => _applyRatio(_ratioOfLocal(d.localPosition), drag: true),
        onHorizontalDragUpdate: (d) => _applyRatio(_ratioOfLocal(d.localPosition), drag: true),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        child: SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              final h = box.maxHeight;
              final ratio = _ratio;
              final knobSize = widget.thin ? 0.0 : 11.0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // 轨道
                  Center(
                    child: AnimatedContainer(
                      duration: AppMotion.hover,
                      width: w,
                      height: thick,
                      decoration: BoxDecoration(
                        color: palette.hi,
                        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                      ),
                    ),
                  ),
                  // 已播填充
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: w * ratio,
                      height: thick,
                      decoration: BoxDecoration(
                        color: palette.acc,
                        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                      ),
                    ),
                  ),
                  // 旋钮
                  if (!widget.thin)
                    Positioned(
                      left: (w * ratio - knobSize / 2).clamp(0.0, w - knobSize),
                      top: h / 2 - knobSize / 2,
                      child: AnimatedOpacity(
                        duration: AppMotion.fast,
                        opacity: (_hover || _dragging) ? 1 : 0,
                        child: AnimatedScale(
                          scale: (_hover || _dragging) ? 1 : 0.6,
                          duration: AppMotion.fast,
                          child: Container(
                            width: knobSize,
                            height: knobSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: palette.acc,
                              boxShadow: [
                                BoxShadow(
                                  color: palette.shadow.withValues(alpha: 0.5),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // 悬停时间气泡（N09）
                  if (widget.showTip && _hover && !_dragging && !widget.thin)
                    Positioned(
                      left: (w * _hoverRatio - 22).clamp(0.0, math.max(0.0, w - 44)),
                      bottom: h,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: palette.panel,
                          border: Border.all(color: palette.line2),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          _tipText(_hoverRatio),
                          style: TextStyle(
                            fontSize: AppFont.px9_5,
                            color: palette.ink,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 等宽数字时间（播放条 / 沉浸播放器共用）。
class MusicTimeText extends StatelessWidget {
  const MusicTimeText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: 34,
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppFont.px10_5,
          color: palette.mut,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
