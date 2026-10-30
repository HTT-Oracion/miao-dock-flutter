import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol/protocol.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/widgets/app_checkbox.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/toast.dart';
import '../controller/queue_controller.dart';
import '../domain/manga_status.dart';

/// 队列移动端（H Note 08）：卡片流替代表格——
/// 任务名 + 状态徽标 + 位次/完成时间 + 进度条 + 行内主动作；多选态前置勾选框。
class QueueCardList extends ConsumerWidget {
  const QueueCardList({super.key, required this.tasks});

  final List<MangaTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pager = ref.watch(pagerProvider);
    final selection = ref.watch(selectionProvider);
    final start = (pager.page - 1) * pager.pageSize;
    final rows = tasks.skip(start).take(pager.pageSize).toList();

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.only(bottom: 64),
          itemCount: rows.length,
          itemBuilder: (context, i) => _TaskCard(task: rows[i], selection: selection),
        ),
        if (selection.enabled) Positioned(left: 0, right: 0, bottom: 0, child: _MobileSelectionBar(tasks: rows)),
      ],
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({required this.task, required this.selection});

  final MangaTask task;
  final SelectionState selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = selection.ids.contains(task.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? AppTokens.accent : Colors.transparent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selection.enabled)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: AppCheckbox(
                value: selected,
                enabled: task.deletable,
                onChanged: (_) => ref.read(selectionProvider.notifier).toggle(task.id),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.textPrimary,
                        ),
                      ),
                    ),
                    _StatusBadge(status: task.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${task.subtitle} · 第 ${task.batchNo} 批 · ${task.source}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      value: task.pageCount == 0 ? null : task.donePages / task.pageCount,
                      backgroundColor: AppTokens.progressTrack,
                      valueColor: AlwaysStoppedAnimation(task.status.color),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      task.completedAt == null
                          ? '队内 ${task.batchNo} 批'
                          : '完成于 ${task.completedAt!.month}/${task.completedAt!.day}',
                      style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary),
                    ),
                    const Spacer(),
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
                    if (task.deletable) ...[
                      AppTextAction(
                        label: '打开',
                        onTap: () {
                          /* TODO: 随落盘目录端点落地 */
                        },
                      ),
                      const SizedBox(width: 6),
                      AppTextAction(
                        label: '更多',
                        onTap: () {
                          /* TODO: 随详情菜单落地 */
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final MangaTaskStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: status.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5)),
      child: Text(status.label, style: TextStyle(fontSize: 11, color: status.color)),
    );
  }
}

class _MobileSelectionBar extends ConsumerWidget {
  const _MobileSelectionBar({required this.tasks});

  final List<MangaTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppTokens.navBg,
        border: const Border(top: BorderSide(color: AppTokens.divider)),
      ),
      child: Row(
        children: [
          Text(
            '已选 ${selection.ids.length} 项',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
          ),
          const Spacer(),
          AppGhostButton(
            label: '全选本页',
            onTap: () {
              final deletable = {
                for (final t in tasks)
                  if (t.deletable) t.id,
              };
              ref.read(selectionProvider.notifier).selectAllPage(deletable);
            },
          ),
          const SizedBox(width: 10),
          AppGhostButton(
            label: '删除选中（${selection.ids.length}）',
            onTap: selection.ids.isEmpty
                ? null
                : () async {
                    final ids = ref.read(selectionProvider).ids;
                    final deleted = await ref.read(queueProvider.notifier).deleteTasks(ids);
                    ref.read(selectionProvider.notifier).clear();
                    if (context.mounted) {
                      showAppToast(context, '已删除 $deleted 条任务记录');
                    }
                  },
          ),
        ],
      ),
    );
  }
}
