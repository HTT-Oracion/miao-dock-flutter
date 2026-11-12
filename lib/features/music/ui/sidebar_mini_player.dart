import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../controller/music_player.dart';
import '../controller/music_session.dart';
import 'widgets/music_shared.dart';

/// 侧栏迷你播放器（设计稿 N35 修订稿：整卡可点，播放键 / 封面 / 文案 /
/// 底部进度条在同一张卡里；点播放键只切播放态，点卡片其它区域进入沉浸播放器）。
///
/// 数据只来自 [playerProvider]；队列为空时不渲染整块（壳层另有空态槽位）。
class SidebarMiniPlayer extends ConsumerWidget {
  const SidebarMiniPlayer({super.key, required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final song = player.current;
    if (song == null) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final progress = player.progressOf(song);

    if (collapsed) {
      // 收起态只留封面与进度条（N35 边界）。
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: GestureDetector(
          onTap: () => ref.read(musicUiProvider.notifier).setImmersive(true),
          child: Column(
            children: [
              _Cover(seed: song.title, imageUrl: song.coverUrl, size: 30),
              const SizedBox(height: 6),
              _ProgressBar(progress: progress, palette: palette),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: GestureDetector(
        // 整卡可点（进入沉浸播放器）；播放键单独处理，不冒泡（N35）。
        onTap: () => ref.read(musicUiProvider.notifier).setImmersive(true),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              Row(
                children: [
                  _Cover(seed: song.title, imageUrl: song.coverUrl, size: 30),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppFont.px9, fontWeight: FontWeight.w600, color: palette.ink),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          song.artist,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppFont.px7_5, color: palette.mut),
                        ),
                      ],
                    ),
                  ),
                  _PlayButton(player: player, l10n: l10n, palette: palette),
                ],
              ),
              const SizedBox(height: 7),
              _ProgressBar(progress: progress, palette: palette),
            ],
          ),
        ),
      ),
    );
  }
}

/// 独立播放键（28px 橙圆底，按下缩 0.9；点击不冒泡到整卡）。
class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.player, required this.l10n, required this.palette});

  final MusicPlayerState player;
  final AppLocalizations l10n;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => ref.read(playerProvider.notifier).toggle(),
      child: Tooltip(
        message: player.playing ? l10n.musicPauseAria : l10n.musicPlayAria,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: palette.acc, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(player.playing ? LucideIcons.pause : LucideIcons.play, size: 13, color: palette.onAcc, fill: 1),
        ),
      ),
    );
  }
}

/// 封面占位（app.css `.mp-cov`：`linear-gradient(140deg, acc, #6B4423)`）。
class _Cover extends StatelessWidget {
  const _Cover({required this.seed, required this.size, this.imageUrl});

  final String seed;
  final double size;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          headers: musicImageHeaders,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.acc, palette.coverEnd],
        ),
      ),
    );
  }
}

/// 进度条（3px 高、`--hi` 槽 + `--acc` 填充）。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress, required this.palette});

  final double progress;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 3,
        backgroundColor: palette.hi,
        valueColor: AlwaysStoppedAnimation(palette.acc),
      ),
    );
  }
}
