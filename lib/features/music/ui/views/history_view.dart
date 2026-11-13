import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_player.dart';
import '../../controller/music_providers.dart';
import '../../domain/music_models.dart';
import '../widgets/fail_magic.dart';
import '../widgets/music_shared.dart';
import '../widgets/music_scroll_memory.dart';
import '../widgets/music_empty_state.dart';

/// 播放历史（N26）：计数 + 清空（带撤销）+ 今天 / 昨天 / 更早 分组 + 点行重播。
class HistoryView extends ConsumerStatefulWidget {
  const HistoryView({super.key});

  @override
  ConsumerState<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends ConsumerState<HistoryView> {
  List<HistoryRowData>? _undoSnapshot;
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final history = ref.watch(historyFeedProvider);
    final entries = history.value ?? const <MusicHistoryEntry>[];

    final head = Row(
      children: [
        Text(
          l10n.viewHistory,
          style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w700, color: palette.ink),
        ),
        const SizedBox(width: 10),
        Text(
          l10n.musicCountSongs(entries.length),
          style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
        ),
        const Spacer(),
        if (entries.isNotEmpty)
          AppButton(
            label: l10n.musicHistoryClear,
            icon: LucideIcons.trash2,
            variant: AppButtonVariant.ghost,
            height: 26,
            fontSize: AppFont.px11_5,
            color: palette.bad,
            onTap: _clear,
          ),
      ],
    );

    final Widget body;
    if (history.hasError && history.value == null) {
      body = Center(
        child: FailMagicCircle(
          reason: l10n.musicFailReasonNetwork,
          lastSyncLabel: l10n.musicFailLastSync(_hhmm()),
          queueHint: l10n.musicFailQueueHint(ref.watch(playerProvider).queue.length),
          retryLabel: l10n.musicRetry,
          onRetry: () => ref.invalidate(historyFeedProvider),
        ),
      );
    } else if (history.isLoading) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          const SizedBox(height: 12),
          for (var i = 0; i < 7; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              child: SkeletonBox(height: 12, width: 200),
            ),
        ],
      );
    } else if (entries.isEmpty) {
      // N30：空态（与失败分开画）：插画 + 一句话 + 一个明确动作（去发现页）。
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          Expanded(
            child: MusicEmptyState(
              title: l10n.musicHistoryEmptyTitle,
              description: l10n.musicHistoryEmptyDesc,
              actionLabel: l10n.musicHistoryEmptyAction,
              onAction: () => GoRouter.of(context).go('/music/discover'),
              mobileStacked: context.isMobile,
            ),
          ),
        ],
      );
    } else {
      final now = DateTime.now();
      final groups = _groupEntries(entries, now, l10n);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          const SizedBox(height: 4),
          Expanded(
            // N03：切视图后回来恢复滚动位置。
            child: MusicScrollMemory(
              storageKey: 'history',
              builder: (context, controller) => ListView(
                controller: controller,
                padding: EdgeInsets.zero,
                children: [
                  for (final group in groups) ...[
                    _DaySeparator(label: group.label),
                    for (final row in group.rows) _HistoryRow(data: row, onReplay: () => _replay(row)),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_undoSnapshot != null) ...[
          _UndoStrip(text: l10n.musicHistoryCleared, undoLabel: l10n.musicUndo, onUndo: _restore),
          const SizedBox(height: 10),
        ],
        Expanded(child: body),
      ],
    );
  }

  void _clear() {
    final notifier = ref.read(historyFeedProvider.notifier);
    final snapshot = notifier.clearKeepSnapshot();
    final now = DateTime.now();
    final l10n = AppLocalizations.of(context);
    _undoTimer?.cancel();
    setState(() {
      _undoSnapshot = [
        for (final e in snapshot)
          HistoryRowData(
            entry: e,
            group: historyGroupOf(e.playedAt, now),
            timeText: _timeText(e.playedAt, historyGroupOf(e.playedAt, now)),
          ),
      ];
    });
    _undoTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _undoSnapshot = null);
    });
    showAppToast(context, l10n.musicHistoryCleared, tone: ToastTone.info);
  }

  void _restore() {
    final snapshot = _undoSnapshot;
    if (snapshot == null) return;
    _undoTimer?.cancel();
    ref.read(historyFeedProvider.notifier).restore([for (final r in snapshot) r.entry]);
    setState(() => _undoSnapshot = null);
  }

  void _replay(HistoryRowData row) {
    ref.read(playerProvider.notifier).playSong(row.entry.song);
    showAppToast(context, AppLocalizations.of(context).musicPlayingNow(row.entry.song.title), tone: ToastTone.good);
  }

  List<_HistoryGroup> _groupEntries(List<MusicHistoryEntry> entries, DateTime now, AppLocalizations l10n) {
    final labels = {
      HistoryGroup.today: l10n.musicToday,
      HistoryGroup.yesterday: l10n.musicYesterday,
      HistoryGroup.earlier: l10n.musicEarlier,
    };
    final result = <_HistoryGroup>[];
    for (final g in HistoryGroup.values) {
      final rows = <HistoryRowData>[];
      for (final e in entries) {
        if (historyGroupOf(e.playedAt, now) == g) {
          rows.add(HistoryRowData(entry: e, group: g, timeText: _timeText(e.playedAt, g)));
        }
      }
      if (rows.isNotEmpty) result.add(_HistoryGroup(label: labels[g]!, rows: rows));
    }
    return result;
  }

  /// 时间列：今/昨只给 HH:mm；更早给 MM-dd HH:mm（不硬编码中文星期）。
  static String _timeText(DateTime t, HistoryGroup g) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    if (g == HistoryGroup.earlier) {
      final mo = t.month.toString().padLeft(2, '0');
      final dd = t.day.toString().padLeft(2, '0');
      return '$mo-$dd $hh:$mm';
    }
    return '$hh:$mm';
  }

  static String _hhmm() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

@immutable
class HistoryRowData {
  const HistoryRowData({required this.entry, required this.group, required this.timeText});

  final MusicHistoryEntry entry;
  final HistoryGroup group;
  final String timeText;
}

class _HistoryGroup {
  const _HistoryGroup({required this.label, required this.rows});

  final String label;
  final List<HistoryRowData> rows;
}

/// 分组头（app.css `.day-sep`）。
class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6, left: 10, right: 10),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppFont.px10_5,
              letterSpacing: 1.4,
              color: palette.mut,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: palette.line)),
        ],
      ),
    );
  }
}

/// 历史行：平台色点 + 来源与时间分列 + 时长右对齐；点行重播（N26）。
/// 历史行不是歌曲行 —— 不弹右键菜单（N36 边界）。
class _HistoryRow extends ConsumerStatefulWidget {
  const _HistoryRow({required this.data, required this.onReplay});

  final HistoryRowData data;
  final VoidCallback onReplay;

  @override
  ConsumerState<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends ConsumerState<_HistoryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final song = widget.data.entry.song;
    final badgeInfo = platformInfoById(song.platformId, ref.watch(musicPlatformInfosProvider));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onReplay,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hover ? palette.card.withValues(alpha: 0.6) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
          ),
          child: Row(
            children: [
              // 平台色点 + 来源名（固定 74 宽列，设计稿 .badge-src）。
              SizedBox(
                width: 74,
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: badgeInfo.color ?? palette.mut),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        badgeInfo.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppFont.px11, color: palette.ink2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px11_5, fontWeight: FontWeight.w500, color: palette.ink),
                    ),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 时间列（分列显示，N26）。
              Text(
                widget.data.timeText,
                style: TextStyle(
                  fontSize: AppFont.px11,
                  color: palette.mut,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 14),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// 撤销条（与本地视图同款模式：toast 文案 + 页内撤销条 6 秒）。
class _UndoStrip extends StatelessWidget {
  const _UndoStrip({required this.text, required this.undoLabel, required this.onUndo});

  final String text;
  final String undoLabel;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: palette.accSoft,
        border: Border.all(color: palette.acc.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 14, color: palette.accInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppFont.px11_5, color: palette.ink2),
            ),
          ),
          AppButton(
            label: undoLabel,
            variant: AppButtonVariant.link,
            height: 26,
            fontSize: AppFont.px11_5,
            fontWeight: FontWeight.w600,
            onTap: onUndo,
          ),
        ],
      ),
    );
  }
}
