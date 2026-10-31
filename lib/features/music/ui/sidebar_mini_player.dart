import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../controller/player_controller.dart';
import '../domain/now_playing.dart';

/// 侧栏 MiniPlayer（design.html §03 侧栏结构：展开态显示在视图组与设置脚之间）。
///
/// 数据只来自 [nowPlayingProvider]；**无播放状态时不渲染整块**，
/// 不写死曲目（对照旧实现的 `夜に駆ける / YOASOBI / 60/190` 硬编码）。
class SidebarMiniPlayer extends ConsumerWidget {
  const SidebarMiniPlayer({super.key, required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowPlayingProvider);
    if (now == null) return const SizedBox.shrink();
    final palette = AppPalette.of(context);

    if (collapsed) {
      // app.css `.sidebar.mini .miniplayer{justify-content:center;padding:4px}`
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: _Cover(now: now, size: 30),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            Row(
              children: [
                _Cover(now: now, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        now.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: palette.ink),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        now.artist,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 7.5, color: palette.mut),
                      ),
                    ],
                  ),
                ),
                Icon(now.playing ? LucideIcons.pause : LucideIcons.play, size: 12, color: palette.ink2),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: now.progress,
                minHeight: 3,
                backgroundColor: palette.hi,
                valueColor: AlwaysStoppedAnimation(palette.acc),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面占位（app.css `.mp-cov`：30 方形、圆角 6、`linear-gradient(140deg, acc, #6B4423)`）。
class _Cover extends StatelessWidget {
  const _Cover({required this.now, required this.size});

  final NowPlaying now;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
