import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/widgets/app_checkbox.dart';
import '../../../../shared/widgets/app_table.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/toast.dart';
import '../controller/queue_controller.dart';
import '../domain/manga_status.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/manga_task.dart';

/// 队列表格（设计稿 H TableCard）：40 表头 + 58px 行；
/// 勾选模式让位 36px 勾选列，选中行主题色底 + 左 3px 色条（H Note 03）；
/// 翻译中 / 排队中行的勾选框置灰（不可删，悬停原因见空态提示）。
class QueueTable extends ConsumerWidget {
  const QueueTable({super.key, required this.tasks});

  final List<MangaTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pager = ref.watch(pagerProvider);
    final selection = ref.watch(selectionProvider);
    final start = (pager.page - 1) * pager.pageSize;
    final rows = tasks.skip(start).take(pager.pageSize).toList();
    final pageDeletableIds = {
      for (final t in rows)
        if (t.deletable) t.id,
    };
    final allChecked = pageDeletableIds.isNotEmpty && pageDeletableIds.every(selection.ids.contains);
    final someChecked = !allChecked && rows.any((t) => selection.ids.contains(t.id));

    return AppTable(
      columns: const [
        AppTableColumn('漫画', flex: true),
        AppTableColumn('进度', width: 180),
        AppTableColumn('状态', width: 120),
        AppTableColumn('操作', width: 150),
      ],
      rowCount: rows.length,
      headerLeading: selection.enabled
          ? AppCheckbox(
              value: allChecked ? true : (someChecked ? null : false),
              onChanged: (_) => ref.read(selectionProvider.notifier).selectAllPage(allChecked ? {} : pageDeletableIds),
            )
          : null,
      rowLeading: selection.enabled
          ? (context, i) => AppCheckbox(
              value: selection.ids.contains(rows[i].id),
              enabled: rows[i].deletable,
              onChanged: (_) => ref.read(selectionProvider.notifier).toggle(rows[i].id),
            )
          : null,
      onRowTap: selection.enabled
          ? (context, i) {
              final task = rows[i];
              if (task.deletable) {
                ref.read(selectionProvider.notifier).toggle(task.id);
              }
            }
          : null,
      rowColor: (_, i) => selection.ids.contains(rows[i].id) ? AppTokens.navActive : null,
      rowAccentColor: (_, i) => selection.ids.contains(rows[i].id) ? AppTokens.accent : null,
      rowBuilder: (context, i) => [
        _NameCell(task: rows[i]),
        _ProgressCell(task: rows[i]),
        _StatusCell(task: rows[i]),
        _ActionCell(task: rows[i]),
      ],
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.task});

  final MangaTask task;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.queueTaskSubtitle(task.donePages, task.pageCount, task.batchNo),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
        ),
      ],
    );
  }
}

class _ProgressCell extends StatelessWidget {
  const _ProgressCell({required this.task});

  final MangaTask task;

  @override
  Widget build(BuildContext context) {
    final ratio = task.pageCount == 0 ? 0.0 : task.donePages / task.pageCount;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${task.donePages} / ${task.pageCount}',
          style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 4,
            child: LinearProgressIndicator(
              value: ratio == 0 ? null : ratio,
              backgroundColor: AppTokens.progressTrack,
              valueColor: AlwaysStoppedAnimation(task.status.color),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.task});

  final MangaTask task;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: task.status.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(task.status.label, style: const TextStyle(fontSize: 12.5, color: AppTokens.textPrimary)),
      ],
    );
  }
}

class _ActionCell extends ConsumerWidget {
  const _ActionCell({required this.task});

  final MangaTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!task.deletable)
          AppTextAction(
            label: '取消',
            onTap: () async {
              final kept = await ref.read(queueProvider.notifier).cancelTask(task.id);
              if (context.mounted) {
                showAppToast(context, '已取消「${task.name}」，保留了 $kept 张已落盘的译文');
              }
            },
          ),
        if (task.deletable)
          AppTextAction(
            label: '打开',
            onTap: () {
              /* TODO: 打开落盘目录，随服务端点落地 */
            },
          ),
        const SizedBox(width: 6),
        AppTextAction(
          label: '更多',
          onTap: () {
            /* TODO: 右键菜单同源操作，随详情落地 */
          },
        ),
      ],
    );
  }
}
