import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/toast.dart';
import '../controller/queue_controller.dart';
import '../../../l10n/app_localizations.dart';

import '../domain/manga_task.dart';

/// 队列顶栏（设计稿 H SumBar）：共 N 条 + 非零状态图例 + 多选；
/// 多选态整条变操作栏（已选 N 项 · 全选本页 · 删除选中 · 取消）。
class QueueSumBar extends ConsumerWidget {
  const QueueSumBar({super.key, required this.tasks});

  final List<MangaTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    return selection.enabled ? _SelectionBar(enabled: selection, tasks: tasks) : _SummaryBar(tasks: tasks);
  }
}

class _SummaryBar extends ConsumerWidget {
  const _SummaryBar({required this.tasks});

  final List<MangaTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    // 图例四项恒显（设计稿 qt-head legend：进行中/等待中/需要处理/已完成，全量统计）。
    final counts = {
      'running': tasks.where((t) => t.status == MangaTaskStatus.translating).length,
      'queued': tasks.where((t) => t.status == MangaTaskStatus.queued).length,
      'need': tasks
          .where((t) => t.status == MangaTaskStatus.failed || t.status == MangaTaskStatus.partialFailed)
          .length,
      'done': tasks.where((t) => t.status == MangaTaskStatus.done).length,
    };
    final legend = <(Color, String, int)>[
      (palette.blue, l10n.legendRunning, counts['running']!),
      (palette.mut, l10n.legendQueued, counts['queued']!),
      (palette.bad, l10n.legendNeed, counts['need']!),
      (palette.good, l10n.legendDone, counts['done']!),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context).queueTotalCount(tasks.length),
            style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w700, color: palette.textPrimary),
          ),
          const SizedBox(width: 6),
          Text(
            AppLocalizations.of(context).queueHeadHint,
            style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
          ),
          const SizedBox(width: 8),
          // 图例（设计稿 .legend：gap 14、点 7、10.5px ink2）。
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                for (final (i, l) in legend.indexed) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: l.$1, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${l.$2} ${l.$3}',
                    style: TextStyle(fontSize: AppFont.px10_5, color: palette.ink2),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          Text(
            AppLocalizations.of(context).queueSortNote,
            style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends ConsumerWidget {
  const _SelectionBar({required this.enabled, required this.tasks});

  final SelectionState enabled;
  final List<MangaTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final deletableIds = {
      for (final t in tasks)
        if (t.deletable) t.id,
    };
    final pager = ref.watch(pagerProvider);
    final pageDeletableIds = {
      for (final t in tasks.skip((pager.page - 1) * pager.pageSize).take(pager.pageSize))
        if (t.deletable) t.id,
    };
    final allPageSelected = pageDeletableIds.isNotEmpty && pageDeletableIds.every(enabled.ids.contains);
    // H Note 10：勾满本页可删任务后出现「选择全部 N 条」，一键跨页选中全部可删任务。
    final showSelectAll = allPageSelected && deletableIds.length > pageDeletableIds.length;
    return Container(
      height: 36,
      decoration: BoxDecoration(color: palette.navActive, borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context).queueSelectedCount(enabled.ids.length),
            style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w600, color: palette.textPrimary),
          ),
          const SizedBox(width: 16),
          AppGhostButton(
            label: AppLocalizations.of(context).queueSelectPage,
            onTap: () => ref.read(selectionProvider.notifier).selectAllPage(deletableIds),
          ),
          if (showSelectAll) ...[
            const SizedBox(width: 10),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => ref.read(selectionProvider.notifier).selectAllPage(deletableIds),
                child: Text(
                  AppLocalizations.of(context).queueSelectAll(deletableIds.length),
                  style: TextStyle(fontSize: AppFont.px12, color: palette.accent),
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          AppGhostButton(
            label: AppLocalizations.of(context).queueDeleteSelected(enabled.ids.length),
            onTap: enabled.ids.isEmpty ? null : () => _deleteSelected(context, ref),
          ),
          const SizedBox(width: 10),
          AppGhostButton(
            label: AppLocalizations.of(context).queueCancelMulti,
            onTap: () => ref.read(selectionProvider.notifier).toggleMode(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppLocalizations.of(context).queueDeleteHint,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFont.px11_5, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected(BuildContext context, WidgetRef ref) async {
    final ids = ref.read(selectionProvider).ids;
    final deleted = await ref.read(queueProvider.notifier).deleteTasks(ids);
    ref.read(selectionProvider.notifier).clear();
    if (context.mounted) showAppToast(context, AppLocalizations.of(context).queueDeletedToast(deleted));
  }
}
