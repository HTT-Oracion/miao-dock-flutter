import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/widgets/app_checkbox.dart';
import '../../../../shared/widgets/app_table.dart';
import '../../../../shared/widgets/app_menu.dart';
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
      columns: [
        AppTableColumn(AppLocalizations.of(context).colComic, flex: true),
        AppTableColumn(AppLocalizations.of(context).colProgress, width: 180),
        AppTableColumn(AppLocalizations.of(context).colStatus, width: 120),
        AppTableColumn(AppLocalizations.of(context).colActions, width: 150),
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
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: task.status.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(task.status.label(l10n), style: const TextStyle(fontSize: 12.5, color: AppTokens.textPrimary)),
      ],
    );
  }
}

/// 队列行动作（桌面与移动共用，避免两处各写一套导致行为漂移）。
class QueueRowActions extends ConsumerWidget {
  const QueueRowActions({super.key, required this.task});

  final MangaTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final st = task.status;

    // 重试（miao-dock：同一个 taskId 重跑；失败弹红色吐司 —— 漫画被删也走这条）。
    Future<void> retry() async {
      try {
        await ref.read(queueProvider.notifier).retry(task.id);
        if (context.mounted) showAppToast(context, l10n.queueRetryOk(task.name), tone: ToastTone.good);
      } catch (e) {
        if (context.mounted) showAppToast(context, l10n.queueRetryFailed('$e'), tone: ToastTone.bad);
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
        label = l10n.actionRetry;
        action = retry;
        highlighted = true; // 「重试」是主操作，高亮
      case MangaTaskStatus.cancelled:
        label = l10n.actionContinue;
        action = retry;
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

  static final GlobalKey _chipKey = GlobalKey();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Builder(
      builder: (context) => _HoverChip(
        key: _chipKey,
        label: l10n.actionMore,
        onTapDown: (details) async {
          // 🔴 用**按钮自身的 RenderBox**（`_HoverChip` 内部传入的 context），
          // 不能用外层 Builder 的 context —— 那取到的是表格容器，锚点会偏。
          final box = _chipKey.currentContext?.findRenderObject() as RenderBox?;
          final anchor = box != null
              ? box.localToGlobal(Offset.zero) & box.size
              // 兜底：拿不到 RenderBox 时用点击点的零宽矩形（至少方向对）。
              : Rect.fromLTWH(details.globalPosition.dx, details.globalPosition.dy, 0, 0);
          final value = await showAppMenu(
            context,
            anchor: anchor,
            minWidth: 160,
            items: [
              AppMenuItem(value: 'open', label: l10n.queueOpenDir, icon: LucideIcons.folderUp),
              const AppMenuItem.separator(),
              AppMenuItem(value: 'delete', label: l10n.actionDelete, icon: LucideIcons.trash2, danger: true),
            ],
          );
          if (value != null) onSelected(value);
        },
      ),
    );
  }
}

/// 队列行按钮：统一走 [AppButton]。
/// `primary` = 主操作（查看/重试）用 primary 变体；其余用 secondary（与「更多」一致）。
class _HoverChip extends StatelessWidget {
  const _HoverChip({super.key, required this.label, required this.onTapDown, this.primary = false});

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
