import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/widgets/app_checkbox.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/toast.dart';
import '../controller/queue_controller.dart';
import 'queue_table.dart';
import '../domain/manga_status.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/manga_task.dart';

/// 队列移动端（H Note 08）：卡片流替代表格——
/// 任务名 + 状态徽标 + 位次/完成时间 + 进度条 + 行内主动作；多选态前置勾选框。
class QueueCardList extends ConsumerWidget {
  const QueueCardList({super.key, required this.tasks});

  final List<MangaTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pager = ref.watch(pagerProvider);
    final selection = ref.watch(selectionProvider);
    final filter = ref.watch(queueFilterProvider);
    final filtered = applyQueueFilter(tasks, filter);
    var start = (pager.page - 1) * pager.pageSize;
    if (filtered.isEmpty) {
      start = 0;
    } else if (start > filtered.length - 1) {
      start = filtered.length - 1;
    }
    final rows = filtered.skip(start).take(pager.pageSize).toList();

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.only(top: 2, bottom: 64),
          itemCount: rows.length + 1, // 0 = 头部
          itemBuilder: (context, i) => i == 0
              ? _MobileHeader(
                  total: filtered.length,
                  filter: filter,
                  selection: selection,
                  onFilter: () => _showFilterSheet(context, tasks),
                  onToggleSelect: () => ref.read(selectionProvider.notifier).toggleMode(),
                  onCancelSelect: () => ref.read(selectionProvider.notifier).toggleMode(),
                  onSelectAll: () {
                    final deletable = {
                      for (final t in rows)
                        if (t.deletable) t.id,
                    };
                    ref.read(selectionProvider.notifier).selectAllPage(deletable);
                  },
                )
              : GestureDetector(
                  // 长按卡片 = 进入多选并勾选该卡（移动端标配手势）。
                  onLongPress: () {
                    final n = ref.read(selectionProvider.notifier);
                    if (!ref.read(selectionProvider).enabled) n.toggleMode();
                    n.toggle(rows[i - 1].id);
                  },
                  child: _TaskCard(task: rows[i - 1], selection: selection),
                ),
        ),
        if (selection.enabled) Positioned(left: 0, right: 0, bottom: 0, child: _MobileSelectionBar(tasks: rows)),
      ],
    );
  }

  /// 筛选抽屉（方案 A 的移动形态）：来源 / 状态 chip 多选，背景列表实时预览。
  void _showFilterSheet(BuildContext context, List<MangaTask> allTasks) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final palette = AppPalette.of(context);
          final l10n = AppLocalizations.of(context);
          final f = ref.watch(queueFilterProvider);
          final count = applyQueueFilter(allTasks, f).length;
          Widget chip(String label, bool on, VoidCallback onTap) => GestureDetector(
            onTap: onTap,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? palette.accSoft : palette.card,
                border: Border.all(color: on ? palette.accent : palette.line2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: TextStyle(fontSize: AppFont.px10_5, color: on ? palette.accent : palette.ink2),
              ),
            ),
          );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 34,
                      height: 3,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: palette.line2, borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
                  Text(
                    l10n.colSource,
                    style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      chip(
                        l10n.queueSrcLocal,
                        f.sources.contains(MangaTaskSource.app),
                        () => ref.read(queueFilterProvider.notifier).toggleSource(MangaTaskSource.app),
                      ),
                      chip(
                        l10n.queueSrcPlugin,
                        f.sources.contains(MangaTaskSource.plugin),
                        () => ref.read(queueFilterProvider.notifier).toggleSource(MangaTaskSource.plugin),
                      ),
                      chip(
                        l10n.queueSrcOther,
                        f.sources.contains(MangaTaskSource.desktop) || f.sources.contains(MangaTaskSource.unknown),
                        () {
                          final n = ref.read(queueFilterProvider.notifier);
                          final on =
                              f.sources.contains(MangaTaskSource.desktop) ||
                              f.sources.contains(MangaTaskSource.unknown);
                          n.toggleSource(MangaTaskSource.desktop);
                          if (on) n.toggleSource(MangaTaskSource.unknown);
                          if (!on && f.sources.contains(MangaTaskSource.unknown)) {
                            n.toggleSource(MangaTaskSource.unknown);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.colStatus,
                    style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final st in MangaTaskStatus.values)
                        chip(
                          st.label(l10n),
                          f.statuses.contains(st),
                          () => ref.read(queueFilterProvider.notifier).toggleStatus(st),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: l10n.queueFilterClear,
                          onTap: () {
                            final n = ref.read(queueFilterProvider.notifier);
                            n.clearSources();
                            n.clearStatuses();
                          },
                          variant: AppButtonVariant.secondary,
                          height: 32,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppButton(
                          label: l10n.queueFilterShowResults(count),
                          onTap: () => Navigator.of(context).pop(),
                          variant: AppButtonVariant.primary,
                          height: 32,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 移动队列头部：普通态（标题 + 筛选 / 选择）与多选态（取消 / 已选 / 全选）。
class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.total,
    required this.filter,
    required this.selection,
    required this.onFilter,
    required this.onToggleSelect,
    required this.onCancelSelect,
    required this.onSelectAll,
  });

  final int total;
  final QueueFilterState filter;
  final SelectionState selection;
  final VoidCallback onFilter;
  final VoidCallback onToggleSelect;
  final VoidCallback onCancelSelect;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final selecting = selection.enabled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Row(
        children: [
          if (selecting)
            GestureDetector(
              onTap: onCancelSelect,
              child: Text(
                l10n.actionCancel,
                style: TextStyle(fontSize: AppFont.px11, color: palette.ink2),
              ),
            )
          else ...[
            Text(
              l10n.queueTitleCount(total),
              style: TextStyle(fontSize: AppFont.px13_5, fontWeight: FontWeight.w700, color: palette.textPrimary),
            ),
          ],
          const Spacer(),
          if (selecting) ...[
            Text(
              l10n.queueSelectedCount(selection.ids.length),
              style: TextStyle(fontSize: AppFont.px10_5, color: palette.textSecondary),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onSelectAll,
              child: Text(
                l10n.queueSelectPage,
                style: TextStyle(fontSize: AppFont.px11, color: palette.accent),
              ),
            ),
          ] else ...[
            GestureDetector(
              onTap: onFilter,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: filter.active ? palette.accSoft : palette.hi,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(LucideIcons.filter, size: 12, color: filter.active ? palette.accent : palette.ink2),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onToggleSelect,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: palette.hi, borderRadius: BorderRadius.circular(6)),
                child: Icon(LucideIcons.squareCheckBig, size: 12, color: palette.ink2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({required this.task, required this.selection});

  final MangaTask task;
  final SelectionState selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final selected = selection.ids.contains(task.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? palette.accent : Colors.transparent),
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
                        style: TextStyle(
                          fontSize: AppFont.px13_5,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    _StatusBadge(status: task.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.queueTaskSubtitleWithSource(
                    task.donePages,
                    task.pageCount,
                    task.batchNo,
                    task.source.label(l10n),
                  ),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFont.px11_5, color: palette.textSecondary),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      value: task.pageCount == 0 ? null : task.donePages / task.pageCount,
                      backgroundColor: palette.progressTrack,
                      valueColor: AlwaysStoppedAnimation(task.status.color),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      task.completedAt == null
                          ? AppLocalizations.of(context).queueBatchWithin(task.batchNo)
                          : AppLocalizations.of(context)
                                .queueFinishedAt(task.completedAt!.month, task.completedAt!.day),
                      style: TextStyle(fontSize: AppFont.px11, color: palette.textSecondary),
                    ),
                    const Spacer(),
                    QueueRowActions(task: task),
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
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: status.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5)),
      child: Text(
        status.label(l10n),
        style: TextStyle(fontSize: AppFont.px11, color: status.color),
      ),
    );
  }
}

class _MobileSelectionBar extends ConsumerWidget {
  const _MobileSelectionBar({required this.tasks});

  final List<MangaTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final selection = ref.watch(selectionProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: palette.navBg,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context).queueSelectedCount(selection.ids.length),
            style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w600, color: palette.textPrimary),
          ),
          const Spacer(),
          AppGhostButton(
            label: AppLocalizations.of(context).queueSelectPage,
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
            label: AppLocalizations.of(context).queueDeleteSelected(selection.ids.length),
            onTap: selection.ids.isEmpty
                ? null
                : () async {
                    final ids = ref.read(selectionProvider).ids;
                    final deleted = await ref.read(queueProvider.notifier).deleteTasks(ids);
                    ref.read(selectionProvider.notifier).clear();
                    if (context.mounted) {
                      showAppToast(context, AppLocalizations.of(context).queueDeletedToast(deleted));
                    }
                  },
          ),
        ],
      ),
    );
  }
}
