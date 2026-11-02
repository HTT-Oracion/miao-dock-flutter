import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/widgets/app_checkbox.dart';
import '../../../../shared/widgets/app_table.dart';
import '../../../../shared/widgets/app_dropdown.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/toast.dart';
import '../controller/library_controller.dart';
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
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final pager = ref.watch(pagerProvider);
    final selection = ref.watch(selectionProvider);
    final filter = ref.watch(queueFilterProvider);
    final filtered = applyQueueFilter(tasks, filter);
    // 筛选后不足一页时钳制起始行，避免空白页。
    var start = (pager.page - 1) * pager.pageSize;
    if (filtered.isEmpty) {
      start = 0;
    } else if (start > filtered.length - 1) {
      start = filtered.length - 1;
    }
    final rows = filtered.skip(start).take(pager.pageSize).toList();
    final pageDeletableIds = {
      for (final t in rows)
        if (t.deletable) t.id,
    };
    final allChecked = pageDeletableIds.isNotEmpty && pageDeletableIds.every(selection.ids.contains);
    final someChecked = !allChecked && rows.any((t) => selection.ids.contains(t.id));

    return AppTable(
      columns: [
        AppTableColumn(l10n.colComic, flex: true),
        AppTableColumn(
          l10n.colSource,
          width: 92,
          headerWidget: _HeaderFilter(
            label: l10n.colSource,
            active: filter.sources.isNotEmpty,
            options: [
              (MangaTaskSource.app, l10n.queueSrcLocal),
              (MangaTaskSource.plugin, l10n.queueSrcPlugin),
              (MangaTaskSource.desktop, l10n.queueSrcOther),
              (MangaTaskSource.unknown, l10n.queueSrcOther),
            ],
            selected: filter.sources,
            onToggle: (v) => ref.read(queueFilterProvider.notifier).toggleSource(v),
            onClear: () => ref.read(queueFilterProvider.notifier).clearSources(),
          ),
        ),
        AppTableColumn(l10n.colProgress, width: 180),
        AppTableColumn(
          l10n.colStatus,
          width: 132,
          headerWidget: _HeaderFilter(
            label: l10n.colStatus,
            active: filter.statuses.isNotEmpty,
            options: [for (final st in MangaTaskStatus.values) (st, st.label(l10n))],
            selected: filter.statuses,
            onToggle: (st) => ref.read(queueFilterProvider.notifier).toggleStatus(st),
            onClear: () => ref.read(queueFilterProvider.notifier).clearStatuses(),
          ),
        ),
        AppTableColumn(l10n.colActions, width: 150),
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
      rowColor: (_, i) => selection.ids.contains(rows[i].id) ? palette.navActive : null,
      rowAccentColor: (_, i) => selection.ids.contains(rows[i].id) ? palette.accent : null,
      rowBuilder: (context, i) => [
        _NameCell(task: rows[i]),
        _SourceCell(task: rows[i]),
        _ProgressCell(task: rows[i]),
        _StatusCell(task: rows[i]),
        QueueRowActions(task: rows[i]),
      ],
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.task});

  final MangaTask task;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.name,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: AppFont.px13_5, fontWeight: FontWeight.w600, color: palette.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.queueTaskSubtitle(task.donePages, task.pageCount, task.batchNo),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: AppFont.px12, color: palette.textSecondary),
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
    final palette = AppPalette.of(context);
    final ratio = task.pageCount == 0 ? 0.0 : task.donePages / task.pageCount;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${task.donePages} / ${task.pageCount}',
          style: TextStyle(fontSize: AppFont.px12, color: palette.textSecondary),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 4,
            // 只有**进行中**才允许不确定动画（value: null）；
            // 终态（含全部失败 0/N）必须给确定值，否则失败任务上还挂着来回滚的动画。
            child: LinearProgressIndicator(
              value: task.status.isTerminal || ratio > 0 ? ratio.clamp(0.0, 1.0) : null,
              backgroundColor: palette.progressTrack,
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
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: task.status.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          task.status.label(l10n),
          style: TextStyle(fontSize: AppFont.px12_5, color: palette.textPrimary),
        ),
      ],
    );
  }
}

/// 队列行动作（桌面与移动共用，避免两处各写一套导致行为漂移）。
class QueueRowActions extends ConsumerStatefulWidget {
  const QueueRowActions({super.key, required this.task});

  final MangaTask task;

  @override
  ConsumerState<QueueRowActions> createState() => _QueueRowActionsState();
}

class _QueueRowActionsState extends ConsumerState<QueueRowActions> {
  /// 重试进行中（含远程探测）：按钮禁用，避免双击重复排队。
  bool _busy = false;

  MangaTask get task => widget.task;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final st = task.status;

    // 重试（miao-dock：同一个 taskId 重跑；失败弹红色吐司 —— 漫画被删也走这条）。
    Future<void> retry() async {
      try {
        final blocked = await ref.read(queueProvider.notifier).retry(task.id, blockedReason: l10n.remoteConfigInvalid);
        if (!context.mounted) return;
        // 被远程校验拦下 ⇒ 任务回到 failed、不进流水线：红色提示让用户去设置页。
        showAppToast(
          context,
          blocked ? l10n.remoteConfigInvalid : l10n.queueRetryOk(task.name),
          tone: blocked ? ToastTone.bad : ToastTone.good,
        );
      } catch (e) {
        if (context.mounted) showAppToast(context, l10n.queueRetryFailed('$e'), tone: ToastTone.bad);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    /// 查看：先判漫画库有没有这本，没有就只提示、不跳（miao-dock `viewComic`）。
    void view() {
      final books = ref.read(libraryProvider).value ?? ref.read(libraryProvider.notifier).lastGood;
      final hit = books.where((b) => b.key == task.name || b.name == task.name).firstOrNull;
      if (hit == null) {
        showAppToast(context, l10n.queueViewMissing(task.name), tone: ToastTone.bad);
        return;
      }
      ref.read(selectedBookProvider.notifier).select(hit.key);
      context.go('/manga/library');
    }

    String label;
    VoidCallback? action;
    var highlighted = false;
    switch (st) {
      case MangaTaskStatus.translating:
      case MangaTaskStatus.queued:
        label = l10n.actionCancel;
        action = () async {
          final kept = await ref.read(queueProvider.notifier).cancelTask(task.id);
          if (context.mounted) {
            showAppToast(context, l10n.queueCancelledToast(task.name, kept));
          }
        };
      case MangaTaskStatus.failed:
      case MangaTaskStatus.partialFailed:
        label = _busy ? l10n.remoteChecking : l10n.actionRetry;
        action = _busy ? null : retry;
        highlighted = true; // 「重试」是主操作，高亮
      case MangaTaskStatus.cancelled:
        label = _busy ? l10n.remoteChecking : l10n.actionContinue;
        action = _busy ? null : retry;
      case MangaTaskStatus.done:
        label = l10n.actionView;
        action = view;
        highlighted = true; // 「查看」高亮
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 主操作（查看/重试）= 「新建漫画」样式；其余（取消/继续）= 「更多」样式。
        _HoverChip(label: label, primary: highlighted, onTapDown: (_) => action?.call()),
        const SizedBox(width: 6),
        _MoreButton(
          onSelected: (v) async {
            switch (v) {
              case 'open':
                try {
                  await ref.read(mangaSvcClientProvider).revealBook(task.name);
                } catch (e) {
                  if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
                }
              case 'delete':
                await ref.read(queueProvider.notifier).deleteTasks({task.id});
                if (context.mounted) {
                  showAppToast(context, l10n.queueDeletedToast(task.name), tone: ToastTone.info);
                }
            }
          },
        ),
      ],
    );
  }
}

/// 「更多」触发器：点开后用统一样式的下拉（AppMenu），并提供 hover 反馈。
class _MoreButton extends ConsumerWidget {
  const _MoreButton({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // 位置交给 Material 3 的 MenuAnchor（AppDropdownMenu）：
    // 它用**触发按钮的实际矩形**定位，正下方 + 左对齐，越界自动翻转。
    return AppDropdownMenu(
      minWidth: 160,
      onSelected: onSelected,
      items: [
        AppDropdownItem(value: 'open', label: l10n.queueOpenDir, icon: LucideIcons.folderUp),
        const AppDropdownItem.divider(),
        AppDropdownItem(value: 'delete', label: l10n.actionDelete, icon: LucideIcons.trash2, danger: true),
      ],
      child: AppButton(
        label: l10n.actionMore,
        // null = 不吸收点击，由 AppDropdownMenu 的触发器打开菜单。
        onTap: null,
        variant: AppButtonVariant.secondary,
        height: 24,
        horizontalPadding: 9,
      ),
    );
  }
}

/// 队列行按钮：统一走 [AppButton]。
/// `primary` = 主操作（查看/重试）用 primary 变体；其余用 secondary（与「更多」一致）。
class _HoverChip extends StatelessWidget {
  const _HoverChip({required this.label, required this.onTapDown, this.primary = false});

  final String label;
  final void Function(TapDownDetails) onTapDown;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => AppButton(
        label: label,
        onTap: () => onTapDown(TapDownDetails(globalPosition: _centerOf(ctx))),
        variant: primary ? AppButtonVariant.primary : AppButtonVariant.secondary,
        height: 24,
        horizontalPadding: 9,
      ),
    );
  }

  Offset _centerOf(BuildContext ctx) {
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.localToGlobal(box.size.center(Offset.zero));
  }
}

/// 来源列单元格：圆点 + 文案胶囊（本地=蓝 / 插件端=主色 / 其他=灰）。
class _SourceCell extends StatelessWidget {
  const _SourceCell({required this.task});

  final MangaTask task;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        task.source.label(AppLocalizations.of(context)),
        style: TextStyle(fontSize: AppFont.px10_5, color: palette.ink2),
      ),
    );
  }
}

/// 表头筛选（方案 A）：列名 + 筛选图标，点开多选勾选面板（清除 / 确定）。
/// 有活跃筛选时图标转主色，一眼知道哪列在过滤。
class _HeaderFilter<T> extends StatefulWidget {
  const _HeaderFilter({
    required this.label,
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.onClear,
    this.active = false,
  });

  final String label;
  final List<(T, String)> options;
  final Set<T> selected;
  final ValueChanged<T> onToggle;
  final VoidCallback onClear;
  final bool active;

  @override
  State<_HeaderFilter<T>> createState() => _HeaderFilterState<T>();
}

class _HeaderFilterState<T> extends State<_HeaderFilter<T>> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 4),
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.panel),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: palette.line2),
          ),
        ),
      ),
      menuChildren: [
        for (final (value, label) in widget.options)
          InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: () => widget.onToggle(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppCheckbox(
                    value: widget.selected.contains(value),
                    tristate: false,
                    onChanged: (_) => widget.onToggle(value),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(fontSize: AppFont.px11, color: palette.ink),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
          child: Divider(height: 1, thickness: 1, color: palette.divider),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AppButton(
              label: AppLocalizations.of(context).queueFilterClear,
              variant: AppButtonVariant.link,
              fontSize: AppFont.px10_5,
              onTap: widget.onClear,
            ),
            AppButton(
              label: AppLocalizations.of(context).queueFilterApply,
              variant: AppButtonVariant.link,
              fontSize: AppFont.px10_5,
              onTap: _controller.close,
            ),
          ],
        ),
      ],
      builder: (context, controller, child) => InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(fontSize: AppFont.px12, color: palette.textSecondary),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.filter, size: 12, color: widget.active ? palette.accent : palette.mut),
            ],
          ),
        ),
      ),
    );
  }
}
