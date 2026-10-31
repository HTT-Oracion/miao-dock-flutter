import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/toast.dart';
import '../controller/queue_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/manga_status.dart';

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
    final l10n = AppLocalizations.of(context);
    final counts = {for (final s in MangaTaskStatus.values) s: tasks.where((t) => t.status == s).length};
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context).queueTotalCount(tasks.length),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
          ),
          const SizedBox(width: 14),
          for (final status in MangaTaskStatus.values)
            if (counts[status]! > 0)
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(status.label(l10n), style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary)),
                  ],
                ),
              ),
          const Spacer(),
          AppGhostButton(
            label: AppLocalizations.of(context).queueMultiSelect,
            onTap: () => ref.read(selectionProvider.notifier).toggleMode(),
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
      decoration: BoxDecoration(color: AppTokens.navActive, borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context).queueSelectedCount(enabled.ids.length),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
          ),
          const SizedBox(width: 16),
          AppGhostButton(
            label: AppLocalizations.of(context).queueSelectPage,
            onTap: () => ref.read(selectionProvider.notifier).selectAllPage(deletableIds),
          ),
          if (showSelectAll) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => ref.read(selectionProvider.notifier).selectAllPage(deletableIds),
              child: Text(
                AppLocalizations.of(context).queueSelectAll(deletableIds.length),
                style: const TextStyle(fontSize: 12, color: AppTokens.accent),
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
              style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
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
