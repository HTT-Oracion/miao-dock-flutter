import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_player.dart';
import '../../controller/music_session.dart';
import '../../domain/music_models.dart';

/// 播放队列抽屉（N14/N15）：右侧 panel 抽屉，不遮播放条（bottom 留播放条高度）。
///
/// 行 = 序号 / 歌名 / 歌手 / 时长；当前行橙底 + ♪；悬停出现移除与拖拽把手；
/// 拖拽排序（ReorderableListView，落点用 M3 默认位移反馈替代 2px 指示线，见报告偏差）；
/// 清空只保留当前曲，toast + 抽屉内撤销条 6 秒（restoreQueue）。
class QueueDrawer extends ConsumerStatefulWidget {
  const QueueDrawer({super.key});

  @override
  ConsumerState<QueueDrawer> createState() => _QueueDrawerState();
}

class _QueueDrawerState extends ConsumerState<QueueDrawer> {
  // 撤销快照：清空前的整条队列 + 当时索引。
  (List<MusicSong>, int)? _undo;
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  void _clear() {
    final player = ref.read(playerProvider.notifier);
    final snapshotIdx = ref.read(playerProvider).idx;
    final snapshot = player.clearQueueKeepCurrent();
    _undoTimer?.cancel();
    setState(() => _undo = (snapshot, snapshotIdx));
    _undoTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _undo = null);
    });
    showAppToast(context, AppLocalizations.of(context).musicQueueCleared, tone: ToastTone.info);
  }

  void _restore() {
    final undo = _undo;
    if (undo == null) return;
    _undoTimer?.cancel();
    ref.read(playerProvider.notifier).restoreQueue(undo.$1, undo.$2);
    setState(() => _undo = null);
  }

  /// 拖拽排序：playerProvider 没有 reorder 动作，用 restoreQueue 以新顺序整条落回，
  /// 索引对回当前曲（与设计稿 bindDrag 的 splice 语义一致；onReorderItem 已
  /// 把「先摘出后插入」的索引偏移修正好，这里不再手动 -1）。
  void _reorder(int oldIndex, int newIndex) {
    final state = ref.read(playerProvider);
    if (oldIndex == newIndex) return;
    final queue = [...state.queue];
    final currentId = state.current?.id;
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex.clamp(0, queue.length), item);
    final newIdx = currentId == null ? state.idx : queue.indexWhere((s) => s.id == currentId);
    ref.read(playerProvider.notifier).restoreQueue(queue, newIdx);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final player = ref.watch(playerProvider);
    final queue = player.queue;

    return Container(
      width: 372,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(left: BorderSide(color: palette.line2)),
        boxShadow: [
          BoxShadow(color: palette.shadow.withValues(alpha: 0.35), blurRadius: 32, offset: const Offset(-14, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头部：标题 + 计数 + 垃圾桶 + ✕（M12：操作收进标题栏）。
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.line)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.listMusic, size: 15, color: palette.ink2),
                const SizedBox(width: 9),
                Text(
                  l10n.musicQueueTitle,
                  style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.musicCountSongs(queue.length),
                  style: TextStyle(
                    fontSize: AppFont.px11,
                    color: palette.mut,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                _DrawerIcon(
                  icon: LucideIcons.trash2,
                  tooltip: l10n.musicQueueClear,
                  onTap: queue.isEmpty ? null : _clear,
                ),
                const SizedBox(width: 4),
                _DrawerIcon(
                  icon: LucideIcons.x,
                  tooltip: l10n.musicQueueClose,
                  onTap: () => ref.read(musicUiProvider.notifier).setQueue(false),
                ),
              ],
            ),
          ),
          if (_undo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: _QueueUndoBar(text: l10n.musicQueueCleared, undoLabel: l10n.musicUndo, onUndo: _restore),
            ),
          Expanded(
            child: queue.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l10n.musicQueueEmptyTitle,
                          style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.musicQueueEmptyDesc,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: AppFont.px11, color: palette.mut, height: 1.6),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    onReorderItem: _reorder,
                    itemCount: queue.length,
                    proxyDecorator: (child, index, animation) => AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) => Material(
                        color: palette.hi,
                        borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
                        child: child,
                      ),
                    ),
                    itemBuilder: (context, i) {
                      final s = queue[i];
                      return _QueueRow(
                        key: ValueKey('queue-${s.id}-$i'),
                        song: s,
                        index: i,
                        current: i == player.idx,
                        onRemove: () => ref.read(playerProvider.notifier).removeAt(i),
                        onPlay: () => ref.read(playerProvider.notifier).playAt(i),
                      );
                    },
                  ),
          ),
          // 底部提示（设计稿队列抽屉脚注）。
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: palette.line)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.gripVertical, size: 12, color: palette.mut),
                const SizedBox(width: 6),
                Text(
                  l10n.musicQueueFooter,
                  style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends ConsumerStatefulWidget {
  const _QueueRow({
    super.key,
    required this.song,
    required this.index,
    required this.current,
    required this.onRemove,
    required this.onPlay,
  });

  final MusicSong song;
  final int index;
  final bool current;
  final VoidCallback onRemove;
  final VoidCallback onPlay;

  @override
  ConsumerState<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends ConsumerState<_QueueRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPlay,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.current ? palette.accSoft : (_hover ? palette.card : Colors.transparent),
            borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Center(
                  child: Text(
                    widget.current ? '♪' : '${widget.index + 1}',
                    style: TextStyle(
                      fontSize: AppFont.px10_5,
                      color: widget.current ? palette.acc : palette.mut,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
                      widget.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFont.px12,
                        fontWeight: widget.current ? FontWeight.w600 : FontWeight.w500,
                        color: widget.current ? palette.accInk : palette.ink,
                      ),
                    ),
                    Text(
                      widget.song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                    ),
                  ],
                ),
              ),
              if (!_hover)
                Text(
                  formatSongDuration(widget.song.duration),
                  style: TextStyle(
                    fontSize: AppFont.px10,
                    color: palette.mut,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              // 悬停出现移除 + 拖拽把手（N14）。
              AnimatedOpacity(
                duration: AppMotion.fast,
                opacity: _hover ? 1 : 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 13,
                        tooltip: l10n.musicQueueRemoveAria,
                        hoverColor: Colors.transparent,
                        onPressed: widget.onRemove,
                        icon: Icon(LucideIcons.x, size: 13, color: palette.ink2),
                      ),
                    ),
                    ReorderableDragStartListener(
                      index: widget.index,
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: Tooltip(
                          message: l10n.musicQueueDragAria,
                          child: Icon(LucideIcons.gripVertical, size: 14, color: palette.mut),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerIcon extends StatelessWidget {
  const _DrawerIcon({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, size: 14, color: onTap == null ? palette.mut : palette.ink2),
        ),
      ),
    );
  }
}

class _QueueUndoBar extends StatelessWidget {
  const _QueueUndoBar({required this.text, required this.undoLabel, required this.onUndo});

  final String text;
  final String undoLabel;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: palette.accSoft,
        border: Border.all(color: palette.acc.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppFont.px10_5, color: palette.ink2),
            ),
          ),
          AppGhostUndo(label: undoLabel, onTap: onUndo),
        ],
      ),
    );
  }
}

class AppGhostUndo extends StatelessWidget {
  const AppGhostUndo({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: TextStyle(fontSize: AppFont.px10_5, fontWeight: FontWeight.w600, color: palette.accInk),
        ),
      ),
    );
  }
}
