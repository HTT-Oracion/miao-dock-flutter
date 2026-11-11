import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../controller/music_player.dart';
import '../../controller/music_session.dart';
import '../../domain/music_models.dart';
import '../widgets/music_shared.dart';

/// 迷你播放条本体高度（不含底部安全区，M03）。
const double kMiniBarHeight = 56;

/// 横滑提交阈值（M16：≥56px 先滑到位再切歌，未过阈值原样回弹）。
const double _commitDistance = 56;

/// 横滑后吞掉一次 click 的窗口（M03：避免滑动结束又误展开播放器）。
const Duration _swallowWindow = Duration(milliseconds: 400);

/// 迷你播放条（M03/M16）：播放 / 暂停 + 播放列表两键；文字与封面区域
/// 支持横滑切歌（相邻曲以整卡从对应侧跟手滑入）与上滑展开全屏播放器。
class MiniMusicBar extends ConsumerWidget {
  const MiniMusicBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final song = player.current;
    if (song == null) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final n = player.queue.length;
    final prev = player.queue[(player.idx - 1 + n) % n];
    final next = player.queue[(player.idx + 1) % n];

    return SafeArea(
      top: false,
      child: Container(
        height: kMiniBarHeight,
        decoration: BoxDecoration(
          color: palette.panel,
          border: Border(top: BorderSide(color: palette.line)),
        ),
        child: Stack(
          children: [
            // 顶部 2px 进度线（M03：滑块本身就是反馈，不弹任何提示）。
            Positioned(left: 0, right: 0, top: 0, child: _MiniProgressLine(progress: player.progressOf(song))),
            Row(
              children: [
                Expanded(
                  child: _MiniSwipeArea(current: song, prev: prev, next: next, positionMs: player.positionMs),
                ),
                const _MiniPlayButton(),
                const _MiniQueueButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniProgressLine extends StatelessWidget {
  const _MiniProgressLine({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 2,
      color: palette.hi,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress.clamp(0.0, 1.0),
        child: Container(color: palette.acc),
      ),
    );
  }
}

/// 横滑 / 上滑手势区（M16）：当前卡随手指位移 42% 并淡出，相邻曲卡以
/// 1.35 倍跟手从屏外滑入但夹在「最多刚好就位」；松手过阈值先让来卡
/// 滑到位（[AppMotion.hover]）再切歌重绘，避免闪一下旧内容。
///
/// 轴锁定说明：横 / 竖识别器交给 Flutter 手势竞技场按首位移方向裁决
/// （胜出即锁轴），与设计稿「首个超过 9px 方向锁定」同义，阈值用框架
/// touch slop（18px），记入偏差报告。
class _MiniSwipeArea extends ConsumerStatefulWidget {
  const _MiniSwipeArea({required this.current, required this.prev, required this.next, required this.positionMs});

  final MusicSong current;
  final MusicSong prev;
  final MusicSong next;
  final int positionMs;

  @override
  ConsumerState<_MiniSwipeArea> createState() => _MiniSwipeAreaState();
}

enum _SlidePhase { idle, dragging, settle, rollback }

class _MiniSwipeAreaState extends ConsumerState<_MiniSwipeArea> with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(vsync: this, duration: AppMotion.hover, value: 1)
    ..value = 1;
  final ValueNotifier<double> _dx = ValueNotifier(0);
  _SlidePhase _phase = _SlidePhase.idle;
  double _startDx = 0;
  bool _commitNext = false;
  double _dy = 0;
  Timer? _swallow;

  @override
  void initState() {
    super.initState();
    // 🔴 不用 TickerFuture.whenComplete：测试时钟下 forward() 的 TickerFuture
    // 不保证在 pump 内 resolve；status=completed 的监听是可靠收口点。
    _settle.addStatusListener(_onSettleCompleted);
  }

  /// settle / rollback 动画收尾：settle 先切歌再复位（M16 先滑到位再切歌）。
  void _onSettleCompleted(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_phase == _SlidePhase.settle) _startSlide(_commitNext);
    _phase = _SlidePhase.idle;
    _dx.value = 0;
    _settle.value = 1;
  }

  @override
  void dispose() {
    _swallow?.cancel();
    _settle.dispose();
    _dx.dispose();
    super.dispose();
  }

  bool get _swallowActive => _swallow != null;

  void _armSwallow() {
    _swallow?.cancel();
    _swallow = Timer(_swallowWindow, () => _swallow = null);
  }

  void _startSlide(bool next) {
    if (next) {
      ref.read(playerProvider.notifier).nextTrack();
    } else {
      ref.read(playerProvider.notifier).prevTrack();
    }
  }

  void _openFull() {
    ref.read(musicUiProvider.notifier).setImmersive(true);
  }

  /// 当前卡透明度：位移越大越透明（fade 半程 = 55% 卡宽）。
  double _fadeOf(double dx, double w) => 1 - (dx.abs() / (w * 0.55)).clamp(0.0, 1.0);

  /// 来卡位置：从屏外跟手滑入（1.35 倍），夹在「最多刚好就位」。
  double _followOf(double dx, double w, {required bool next}) {
    final base = next ? w : -w;
    final follow = base + dx * 1.35;
    return next ? follow.clamp(0.0, w) : follow.clamp(-w, 0.0);
  }

  void _onHorizontalEnd(double w) {
    if (_phase != _SlidePhase.dragging) return;
    final dx = _dx.value;
    _startDx = dx;
    _armSwallow();
    if (dx.abs() >= _commitDistance) {
      _commitNext = dx < 0;
      _phase = _SlidePhase.settle;
      _settle.forward(from: 0);
    } else if (dx.abs() > 0.5) {
      _phase = _SlidePhase.rollback;
      _settle.forward(from: 0);
    } else {
      _dx.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final song = widget.current;
    return LayoutBuilder(
      builder: (context, bc) {
        final w = bc.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // down 基准：触发 start 的那段位移不吞掉，全部计入 update（设计稿
          // 的 pointer capture 语义等价 —— 跟手位移从按下点起算）。
          dragStartBehavior: DragStartBehavior.down,
          onTap: () {
            if (_swallowActive || _phase != _SlidePhase.idle) return;
            _openFull();
          },
          // 🔴 回调必须**常驻**、在回调内部判相位：如果按 phase 置 null，
          // start 同帧内的 move/end 事件拿到的还是旧配置（null），整条拖动会被丢掉。
          onHorizontalDragStart: (_) {
            if (_phase != _SlidePhase.idle) return;
            setState(() => _phase = _SlidePhase.dragging);
            _settle.value = 1;
          },
          onHorizontalDragUpdate: (d) {
            if (_phase != _SlidePhase.dragging) return;
            _dx.value = (_dx.value + d.delta.dx).clamp(-w, w);
          },
          onHorizontalDragEnd: (_) => _onHorizontalEnd(w),
          onHorizontalDragCancel: () => _onHorizontalEnd(w),
          onVerticalDragUpdate: (d) => _dy += d.delta.dy,
          onVerticalDragEnd: (d) {
            if (_dy < -24) _openFull(); // M03：上滑 >24px 展开
            _dy = 0;
          },
          child: ClipRect(
            child: AnimatedBuilder(
              animation: Listenable.merge([_dx, _settle]),
              builder: (context, _) {
                final dx = _dx.value;
                var curOffset = dx * 0.42;
                var curOpacity = _fadeOf(dx, w);
                var nextOffset = w.toDouble();
                var nextOpacity = 0.0;
                var prevOffset = -w.toDouble();
                var prevOpacity = 0.0;
                final t = Curves.easeOutCubic.transform(_settle.value);
                if (_phase == _SlidePhase.dragging && dx != 0) {
                  final isNext = dx < 0;
                  nextOffset = _followOf(dx, w, next: true);
                  nextOpacity = isNext ? 1.0 : 0.0;
                  prevOffset = _followOf(dx, w, next: false);
                  prevOpacity = isNext ? 0.0 : 1.0;
                } else if (_phase == _SlidePhase.settle) {
                  // 来卡先滑到位，当前卡继续滑出并淡到 0（M16）。
                  curOffset = _startDx * 0.42;
                  curOpacity = 0.0;
                  if (_commitNext) {
                    nextOffset = _lerp(_followOf(_startDx, w, next: true), 0, t);
                    nextOpacity = 1.0;
                    prevOffset = _lerp(_startDx * 0.42, -w * 0.42, t);
                    prevOpacity = 0.0;
                  } else {
                    prevOffset = _lerp(_followOf(_startDx, w, next: false), 0, t);
                    prevOpacity = 1.0;
                    nextOffset = _lerp(_startDx * 0.42, w * 0.42, t);
                    nextOpacity = 0.0;
                  }
                } else if (_phase == _SlidePhase.rollback) {
                  curOffset = _lerp(_startDx * 0.42, 0, t);
                  curOpacity = _lerp(_fadeOf(_startDx, w), 1, t);
                  nextOffset = _followOf(_startDx, w, next: true);
                  nextOpacity = (1 - t) * (nextOffset > 0 && nextOffset < w ? 1.0 : 0.0);
                  prevOffset = _followOf(_startDx, w, next: false);
                  prevOpacity = (1 - t) * (prevOffset < 0 && prevOffset > -w ? 1.0 : 0.0);
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: curOpacity.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(curOffset, 0),
                          child: _CurrentSlide(song: song, positionMs: widget.positionMs),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Opacity(
                        opacity: nextOpacity.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(nextOffset, 0),
                          child: _IncomingSlide(
                            song: widget.next,
                            tag: l10n.musicNextAria,
                            directionIcon: LucideIcons.cornerDownRight,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Opacity(
                        opacity: prevOpacity.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(prevOffset, 0),
                          child: _IncomingSlide(
                            song: widget.prev,
                            tag: l10n.musicPrevAria,
                            directionIcon: LucideIcons.cornerUpLeft,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// `a + (b - a) * t`：插值助手（避免与 dart:ui 的 lerpDouble 语义混淆，故私有命名）。
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// 当前卡：封面 40（点击展开）+ 歌名 / 歌手两行 + 当前时间。
class _CurrentSlide extends StatelessWidget {
  const _CurrentSlide({required this.song, required this.positionMs});

  final MusicSong song;
  final int positionMs;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        SeedCover(seed: song.title, imageUrl: song.coverUrl, size: 40, radius: 8),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w600, color: palette.ink),
              ),
              const SizedBox(height: 1),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          formatSongDuration(Duration(milliseconds: positionMs)),
          style: TextStyle(
            fontSize: AppFont.px10,
            color: palette.mut,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 相邻曲滑入卡：封面头像 + 歌名 + 歌手 + 方向标签（M16）。
class _IncomingSlide extends StatelessWidget {
  const _IncomingSlide({required this.song, required this.tag, required this.directionIcon});

  final MusicSong song;
  final String tag;
  final IconData directionIcon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
          border: Border.all(color: palette.line2),
        ),
        child: Row(
          children: [
            SeedCover(seed: song.title, imageUrl: song.coverUrl, size: 38, radius: 8),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w600, color: palette.ink),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: palette.accSoft, borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(directionIcon, size: 9, color: palette.accInk),
                  const SizedBox(width: 3),
                  Text(
                    tag,
                    style: TextStyle(fontSize: AppFont.px9, fontWeight: FontWeight.w600, color: palette.accInk),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 播放 / 暂停键（M03：34px，按下 scale .94 —— M08）。
class _MiniPlayButton extends ConsumerWidget {
  const _MiniPlayButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playerProvider.select((p) => p.playing));
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return TapScaleButton(
      onTap: () => ref.read(playerProvider.notifier).toggle(),
      semantics: playing ? l10n.musicPauseAria : l10n.musicPlayAria,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: palette.acc, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(playing ? LucideIcons.pause : LucideIcons.play, size: 14, color: palette.onAcc),
      ),
    );
  }
}

/// 播放列表键：直接 setQueue(true)，队列抽屉由容器渲染（M03）。
class _MiniQueueButton extends ConsumerWidget {
  const _MiniQueueButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return TapScaleButton(
      onTap: () => ref.read(musicUiProvider.notifier).setQueue(true),
      semantics: l10n.musicSheetQueueAria,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(LucideIcons.listMusic, size: 18, color: AppPalette.of(context).ink2),
      ),
    );
  }
}

/// 按下缩放包裹器（M08：按下态 scale .94，手指有反馈）。
/// 迷你条 / 全屏播放器 / 底部抽屉共用，故做成公开类供 mobile 内部复用。
class TapScaleButton extends StatefulWidget {
  const TapScaleButton({super.key, required this.onTap, required this.child, this.scale = 0.94, this.semantics});

  final VoidCallback onTap;
  final Widget child;
  final double scale;

  /// 无障碍标签（等价设计稿 aria-label）。
  final String? semantics;

  @override
  State<TapScaleButton> createState() => _TapScaleButtonState();
}

class _TapScaleButtonState extends State<TapScaleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final inner = AnimatedScale(
      scale: _pressed ? widget.scale : 1,
      duration: AppMotion.fast,
      curve: AppMotion.easeOutCubic,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: widget.child),
    );
    final labeled = Semantics(button: true, label: widget.semantics, child: inner);
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: labeled,
    );
  }
}
