import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/widgets/app_checkbox.dart';
import '../../../../shared/widgets/app_dropdown.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/toast.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';
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
                  subtitle: _statusSummary(filtered, AppLocalizations.of(context)),
                  filter: filter,
                  selection: selection,
                  onFilter: () => _showFilterSheet(context, tasks),
                  onToggleSelect: () => ref.read(selectionProvider.notifier).toggleMode(),
                  onCancelSelect: () => ref.read(selectionProvider.notifier).toggleMode(),
                  canSelect: rows.isNotEmpty,
                  deletableOnPage: {
                    for (final t in rows)
                      if (t.deletable) t.id,
                  },
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
        // 选择栏要**贴到屏幕左右边缘**：外层 QueueScreen 有 10px 内距，
        // OverflowBox 向外扩 10 抵消，否则两侧各留一条缝（用户实测）。
        if (selection.enabled) Positioned(left: -10, right: -10, bottom: 0, child: _MobileSelectionBar(tasks: rows)),
        // 筛选后无结果：表格/列表区给**空状态**（不是空白页），
        // 并提示可取消筛选（头部筛选图标此刻是橙色，点开即可取消）。
        if (rows.isEmpty && filter.active)
          Positioned.fill(
            top: 44,
            child: IgnorePointer(
              ignoring: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: EmptyState(
                  icon: LucideIcons.filterX,
                  title: AppLocalizations.of(context).queueFilterEmpty,
                  description: AppLocalizations.of(context).queueFilterEmptyHint,
                ),
              ),
            ),
          ),
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
          // 点 chip **只切换条件、不关闭面板**（用户要求：可以连续勾选多项）。
          // 关闭靠面板外的点击 / 下滑手势。
          Widget chip(String label, bool on, VoidCallback onTap) => GestureDetector(
            onTap: onTap,
            child: Container(
              // 🔴 不能用 alignment/height：Container 一带 alignment 就撑满
              // 可用宽度 → 每个 chip 独占一行（与原型不符）。对称垂直 padding
              // 让宽度收缩到文字，垂直方向天然居中。
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
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
                          // 「其他」= desktop + unknown 两个 wire 值的聚合。
                          // 用 setSources **幂等**写入：开着就全关，关着就全开。
                          final n = ref.read(queueFilterProvider.notifier);
                          final on =
                              f.sources.contains(MangaTaskSource.desktop) ||
                              f.sources.contains(MangaTaskSource.unknown);
                          final next = {...f.sources}
                            ..remove(MangaTaskSource.desktop)
                            ..remove(MangaTaskSource.unknown);
                          if (!on) {
                            next
                              ..add(MangaTaskSource.desktop)
                              ..add(MangaTaskSource.unknown);
                          }
                          n.setSources(next);
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
    required this.subtitle,
    required this.filter,
    required this.selection,
    required this.onFilter,
    required this.onToggleSelect,
    required this.onCancelSelect,
    required this.onSelectAll,
    required this.deletableOnPage,
    required this.canSelect,
  });

  final int total;
  final String subtitle;
  final QueueFilterState filter;
  final SelectionState selection;
  final VoidCallback onFilter;
  final VoidCallback onToggleSelect;
  final VoidCallback onCancelSelect;
  final VoidCallback onSelectAll;

  /// 当前页可删除的任务 id（多选头部「可删 N」用）。
  final Set<String> deletableOnPage;

  /// 列表是否有可显示任务（无任务时多选按钮置灰）。
  final bool canSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final selecting = selection.enabled;
    return Padding(
      // 设计稿：上下 8 / 6、左右 10（与卡片同内距）。
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Row(
        children: [
          if (selecting)
            GestureDetector(
              onTap: onCancelSelect,
              child: Text(
                l10n.actionCancel,
                style: TextStyle(fontSize: AppFont.px10_5, color: palette.ink2),
              ),
            )
          else ...[
            // 标题 13/700 + 副标 9.5/mut；副标过长时**换行到下一行**（不截断）。
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.queueTaskCount(total),
                    style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.textPrimary),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      softWrap: true,
                      style: TextStyle(fontSize: AppFont.px9_5, height: 1.4, color: palette.mut),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const Spacer(),
          if (selecting) ...[
            Text(
              // 设计稿：`已选 2 / 可删 4`（可删 = 本页里 deletable 的数量）。
              l10n.queueSelectedDeletable(selection.ids.length, deletableOnPage.whereType<String>().length),
              style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onSelectAll,
              child: Text(
                l10n.queueSelectPage,
                style: TextStyle(fontSize: AppFont.px10_5, color: palette.accent),
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
            // 没有可显示任务时多选无意义 → 置灰且不可点（用户要求）。
            MouseRegion(
              cursor: canSelect ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
              child: GestureDetector(
                onTap: canSelect ? onToggleSelect : null,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: palette.hi, borderRadius: BorderRadius.circular(6)),
                  child: Icon(
                    LucideIcons.squareCheckBig,
                    size: 12,
                    color: canSelect ? palette.ink2 : palette.mut.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 头部副标：只列非零状态（"1 翻译中 · 1 已完成"）；全为 0 返回空串。
String _statusSummary(List<MangaTask> tasks, AppLocalizations l10n) {
  const order = [
    MangaTaskStatus.translating,
    MangaTaskStatus.queued,
    MangaTaskStatus.done,
    MangaTaskStatus.partialFailed,
    MangaTaskStatus.failed,
    MangaTaskStatus.cancelled,
  ];
  final parts = <String>[];
  for (final st in order) {
    final c = tasks.where((t) => t.status == st).length;
    if (c > 0) parts.add('$c ${st.label(l10n)}');
  }
  return parts.join(' · ');
}

/// 「查看」：先判漫画库还有没有这本（被删就不跳，只提示），再定位到该书。
void _view(BuildContext context, WidgetRef ref, MangaTask task, AppLocalizations l10n) {
  final books = ref.read(libraryProvider).value ?? ref.read(libraryProvider.notifier).lastGood;
  final hit = books.where((b) => b.key == task.name || b.name == task.name).firstOrNull;
  if (hit == null) {
    showAppToast(context, l10n.queueViewMissing(task.name), tone: ToastTone.bad);
    return;
  }
  ref.read(selectedBookProvider.notifier).select(hit.key);
  context.go('/manga/library');
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
    final selecting = selection.enabled;

    // 设计稿 `.pcard`：内距 10×11 / 圆角 10 / card 底 + line 描边；
    // 选中 = acc 描边 + accSoft 底。
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? palette.accSoft : palette.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? palette.accent : palette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selecting)
            Padding(
              padding: const EdgeInsets.only(right: 9),
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
                // 标题行：名称（限宽 + 省略号）+ 状态胶囊 + 右上角两个按钮。
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFont.px12,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    // 多选态只留基本信息（设计稿 `.pcard.sel` 无胶囊/无按钮）。
                    if (!selecting) ...[
                      const SizedBox(width: 6),
                      _StatusBadge(status: task.status),
                      const SizedBox(width: 6),
                      _MobileCardActions(task: task),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                // 副标：页数 · 批次 · 来源，末尾接完成时间（用户裁定）。
                Text(
                  _subtitleWithTime(task, l10n),
                  softWrap: true,
                  style: TextStyle(fontSize: AppFont.px9_5, height: 1.45, color: palette.mut),
                ),
                // 多选态不画进度条（设计稿同）。
                if (!selecting && task.pageCount > 0) ...[
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: 3,
                      child: LinearProgressIndicator(
                        value: task.donePages / task.pageCount,
                        backgroundColor: palette.line2,
                        valueColor: AlwaysStoppedAnimation(palette.acc),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 副标 + 完成时间（时间接在末尾，不新增一行）。
String _subtitleWithTime(MangaTask task, AppLocalizations l10n) {
  final base = l10n.queueTaskSubtitleWithSource(task.donePages, task.pageCount, task.batchNo, task.source.label(l10n));
  final time = task.completedAt == null
      ? l10n.queueBatchWithin(task.batchNo)
      : l10n.queueFinishedAt(task.completedAt!.month, task.completedAt!.day);
  return '$base · $time';
}

/// 卡片右上角：状态相关的主操作（查看/重试/取消/继续）+ 文本「...」更多菜单。
///
/// 与桌面 `QueueRowActions` 的区别：这里**不并排**（窄屏放不下），
/// 主操作按状态切换，其余操作收进「...」下拉。
class _MobileCardActions extends ConsumerStatefulWidget {
  const _MobileCardActions({required this.task});

  final MangaTask task;

  @override
  ConsumerState<_MobileCardActions> createState() => _MobileCardActionsState();
}

class _MobileCardActionsState extends ConsumerState<_MobileCardActions> {
  bool _busy = false;

  MangaTask get task => widget.task;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final st = task.status;

    // 主操作文案随状态变化（查看 / 重试 / 取消）。
    final (String label, VoidCallback? action) = switch (st) {
      MangaTaskStatus.done => (l10n.actionView, () => _view(context, ref, task, l10n)),
      MangaTaskStatus.failed ||
      MangaTaskStatus.partialFailed => (_busy ? l10n.remoteChecking : l10n.actionRetry, _busy ? null : _retry),
      MangaTaskStatus.cancelled => (_busy ? l10n.remoteChecking : l10n.actionContinue, _busy ? null : _retry),
      _ => (l10n.actionCancel, _cancel),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          label: label,
          onTap: action,
          variant: AppButtonVariant.ghost,
          height: 22,
          horizontalPadding: 8,
          fontSize: AppFont.px10,
        ),
        const SizedBox(width: 4),
        // 「...」是**文本按钮**（用户裁定），点开下拉给其余操作。
        AppDropdownMenu(
          minWidth: 150,
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
          items: [
            AppDropdownItem(value: 'open', label: l10n.queueOpenDir, icon: LucideIcons.folderUp),
            const AppDropdownItem.divider(),
            AppDropdownItem(value: 'delete', label: l10n.actionDelete, icon: LucideIcons.trash2, danger: true),
          ],
          child: AppButton(
            label: '...',
            onTap: null,
            variant: AppButtonVariant.ghost,
            height: 22,
            horizontalPadding: 6,
            fontSize: AppFont.px10,
          ),
        ),
      ],
    );
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final messengerCtx = context;
    try {
      final blocked = await ref.read(queueProvider.notifier).retry(task.id, blockedReason: l10n.remoteConfigInvalid);
      if (!messengerCtx.mounted) return;
      showAppToast(
        messengerCtx,
        blocked ? l10n.remoteConfigInvalid : l10n.queueRetryOk(task.name),
        tone: blocked ? ToastTone.bad : ToastTone.good,
      );
    } catch (e) {
      if (messengerCtx.mounted) showAppToast(messengerCtx, l10n.queueRetryFailed('$e'), tone: ToastTone.bad);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final l10n = AppLocalizations.of(context);
    final ctx = context;
    final kept = await ref.read(queueProvider.notifier).cancelTask(task.id);
    if (ctx.mounted) showAppToast(ctx, l10n.queueCancelledToast(task.name, kept));
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final MangaTaskStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 设计稿 `.pill`：h19 / padding 0 8 / radius 999 / 字号 10。
    return Container(
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: status.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Text(
        status.label(l10n),
        style: TextStyle(fontSize: AppFont.px10, color: status.color),
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
    // 设计稿 `.pselbar`：padding 10×12 / 计数 11(600) / 按钮 30 高 10.5 号；
    // 删除按钮用 danger（设计稿 `.b.danger`）。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(top: BorderSide(color: palette.line2)),
      ),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context).queueSelectedCount(selection.ids.length),
            style: TextStyle(fontSize: AppFont.px11, fontWeight: FontWeight.w600, color: palette.textPrimary),
          ),
          const Spacer(),
          // 设计稿 `.pselbar` 只放「已选 N」+「删除选中」；
          // 全选在**头部**（`queueSelectPage`），这里不再重复。
          AppButton(
            label: AppLocalizations.of(context).queueDeleteSelectedShort,
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
            variant: AppButtonVariant.danger,
            height: 30,
            horizontalPadding: 12,
            fontSize: AppFont.px10_5,
          ),
        ],
      ),
    );
  }
}
