import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/widgets/app_checkbox.dart';
import '../../../../shared/widgets/app_table.dart';
import '../../../../shared/widgets/app_dropdown.dart';
import '../../../../shared/widgets/empty_state.dart';
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
          width: 96,
          headerWidget: _HeaderFilter(
            label: l10n.colSource,
            active: filter.sources.isNotEmpty,
            options: [
              (null, l10n.queueFilterAllSource),
              (MangaTaskSource.app, l10n.queueSrcLocal),
              (MangaTaskSource.plugin, l10n.queueSrcPlugin),
              (MangaTaskSource.desktop, l10n.queueSrcOther),
              (MangaTaskSource.unknown, l10n.queueSrcOther),
            ],
            selected: filter.sources,
            onToggle: (v) => v == null
                ? ref.read(queueFilterProvider.notifier).clearSources()
                : ref.read(queueFilterProvider.notifier).toggleSource(v),
            onClear: () => ref.read(queueFilterProvider.notifier).clearSources(),
          ),
        ),
        AppTableColumn(l10n.colProgress, width: 150),
        AppTableColumn(
          l10n.colStatus,
          width: 150,
          headerWidget: _HeaderFilter(
            label: l10n.colStatus,
            active: filter.statuses.isNotEmpty,
            options: [(null, l10n.queueFilterAllStatus), for (final st in MangaTaskStatus.values) (st, st.label(l10n))],
            selected: filter.statuses,
            onToggle: (st) => st == null
                ? ref.read(queueFilterProvider.notifier).clearStatuses()
                : ref.read(queueFilterProvider.notifier).toggleStatus(st),
            onClear: () => ref.read(queueFilterProvider.notifier).clearStatuses(),
          ),
        ),
        AppTableColumn(l10n.colActions, width: 118),
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
      // 行底色：选中 = navActive；进行中行抬升为 card 底（重设计稿 `.qt-row.is-running`，
      // 让「现在在跑哪一行」一眼可辨）；其余不渲染。
      rowColor: (_, i) {
        if (selection.ids.contains(rows[i].id)) return palette.navActive;
        if (rows[i].status == MangaTaskStatus.translating) return palette.card;
        return null;
      },
      // 行左 3px 状态条（重设计稿 `.qt-row[data-status]::before`）：
      // 未选中行按状态着色，选中行让位主色（选中语义优先）。
      rowAccentColor: (_, i) => selection.ids.contains(rows[i].id) ? palette.accent : rows[i].status.color,
      // 🔴 空态只占表格主体，表头常驻——筛选入口消失就恢复不了列表（用户实测）。
      emptyPlaceholder: filter.active
          ? EmptyState(icon: LucideIcons.filterX, title: l10n.queueFilterEmpty, description: l10n.queueFilterEmptyHint)
          : null,
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
          style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
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
    final failed = task.status == MangaTaskStatus.failed || task.status == MangaTaskStatus.partialFailed;
    // 重设计稿 qt-prog：数值 12/600 + 注记 9.5（有失败先说失败，警告色）；条 5px 圆角 3、最宽 110。
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${task.donePages} / ${task.pageCount}',
              style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w600, color: palette.textPrimary),
            ),
            const SizedBox(width: 6),
            Text(
              failed ? '!' : '${(ratio * 100).round()}%',
              style: TextStyle(fontSize: AppFont.px9_5, color: failed ? palette.warn : palette.mut),
            ),
          ],
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: 110,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: _StripedBar(
                value: task.status.isTerminal || ratio > 0 ? ratio.clamp(0.0, 1.0) : null,
                color: task.status.color,
                track: palette.progressTrack,
                striped: task.status == MangaTaskStatus.translating,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 流动条纹进度条（重设计稿 `.qt-bar.striped`：45° 白纹 14px 周期、.9s 流动）。
/// 确定值画填充；running（value=null）画不确定条纹流动。
class _StripedBar extends StatefulWidget {
  const _StripedBar({required this.value, required this.color, required this.track, required this.striped});

  final double? value;
  final Color color;
  final Color track;
  final bool striped;

  @override
  State<_StripedBar> createState() => _StripedBarState();
}

class _StripedBarState extends State<_StripedBar> with SingleTickerProviderStateMixin {
  late final AnimationController _flow;

  @override
  void initState() {
    super.initState();
    _flow = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.striped) _flow.repeat();
  }

  @override
  void didUpdateWidget(covariant _StripedBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.striped && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!widget.striped && _flow.isAnimating) {
      _flow.stop();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flow,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _StripedBarPainter(
          value: widget.value,
          color: widget.color,
          track: widget.track,
          striped: widget.striped,
          offset: _flow.value * 14,
        ),
      ),
    );
  }
}

class _StripedBarPainter extends CustomPainter {
  const _StripedBarPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.striped,
    required this.offset,
  });

  final double? value;
  final Color color;
  final Color track;
  final bool striped;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(3);
    final trackRect = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(trackRect, Paint()..color = track);
    final fillW = value == null ? size.width : size.width * value!.clamp(0.0, 1.0);
    if (fillW <= 0) return;
    final fillRect = RRect.fromRectAndRadius(Offset.zero & Size(fillW, size.height), r);
    canvas.drawRRect(fillRect, Paint()..color = color);
    if (!striped) return;
    // 45° 白纹 .22：14px 周期，随 offset 流动；先裁剪到填充区。
    canvas.save();
    canvas.clipRRect(fillRect);
    final stripe = Paint()
      ..strokeWidth = 5
      ..color = Colors.white.withValues(alpha: 0.22);
    for (var x = -size.height + (offset % 14); x < fillW + size.height; x += 14) {
      canvas.drawLine(Offset(x, size.height + 2), Offset(x + size.height + 4, -2), stripe);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StripedBarPainter old) =>
      old.value != value || old.color != color || old.striped != striped || old.offset != offset;
}

class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.task});

  final MangaTask task;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final st = task.status;
    // 重设计稿 `.badge`：高 24 / r999 / min-width 84 / 10.5px / 圆点 7；
    // 色相由圆点与描边承载（is-live 描边 rgba(blue,.4)、is-ok good .35、is-warn warn .4、is-bad bad .4）。
    final borderColor = switch (st) {
      MangaTaskStatus.translating => palette.blue.withValues(alpha: 0.4),
      MangaTaskStatus.done => palette.good.withValues(alpha: 0.35),
      MangaTaskStatus.partialFailed => palette.warn.withValues(alpha: 0.4),
      MangaTaskStatus.failed => palette.bad.withValues(alpha: 0.4),
      _ => palette.line2,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: palette.card,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusDot(color: st.color, live: st == MangaTaskStatus.translating),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                st.label(AppLocalizations.of(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppFont.px10_5, color: palette.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 徽标圆点：进行中 1.6s 脉冲（重设计稿 `.badge.is-live .dot`）。
class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.live});

  final Color color;
  final bool live;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: AppMotion.nodePulse);
    if (widget.live) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.live && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.live && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.35).animate(_c),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
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
      child: Builder(
        builder: (context) {
          final palette = AppPalette.of(context);
          // 重设计稿 `.more-btn`：24×24、圆角 6、纯 ⋯ 图标（hover 反馈由 AppDropdownMenu 触发器承接）。
          return SizedBox(width: 24, height: 24, child: Icon(LucideIcons.ellipsis, size: 14, color: palette.ink2));
        },
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

/// 来源列单元格：直接显示文本（本地 / 插件端 / 其他），不做容器处理。
class _SourceCell extends StatelessWidget {
  const _SourceCell({required this.task});

  final MangaTask task;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // 来源直接显示文本，不做任何容器处理（用户要求）。
    return Text(
      task.source.label(AppLocalizations.of(context)),
      style: TextStyle(fontSize: AppFont.px11, color: palette.ink2),
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

  /// 首项语义 = 「全部」（清空集合）；其余项点击 = 切换集合成员（即时生效）。
  final List<(T?, String)> options;
  final Set<T> selected;
  final ValueChanged<T?> onToggle;
  final VoidCallback onClear;
  final bool active;

  @override
  State<_HeaderFilter<T>> createState() => _HeaderFilterState<T>();
}

class _HeaderFilterState<T> extends State<_HeaderFilter<T>> {
  final _controller = MenuController();

  /// 触发器文案（重设计稿 index.html：显示当前筛选词；未筛选 = 列名）。
  String get _label {
    if (widget.selected.isEmpty) return widget.label;
    if (widget.selected.length == 1) {
      return widget.options
          .firstWhere((o) => o.$1 == widget.selected.first, orElse: () => (widget.selected.first, widget.label))
          .$2;
    }
    return '${widget.label} · ${widget.selected.length}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // 对齐设计稿 hdmenu：panel 底 / r10 / shadow / p5；选项行 11.5、.on = 主色加粗；
    // 无勾选框、无底部按钮行（首项「全部…」即清除）。
    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 4),
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        visualDensity: VisualDensity.standard,
      ),
      menuChildren: [
        Container(
          constraints: const BoxConstraints(minWidth: 150),
          decoration: BoxDecoration(
            color: palette.panel,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(color: palette.shadow.withValues(alpha: 0.5), blurRadius: 34, offset: const Offset(0, 10)),
            ],
          ),
          padding: const EdgeInsets.all(5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (value, label) in widget.options)
                _MenuOption(label: label, active: widget.selected.contains(value), onTap: () => widget.onToggle(value)),
            ],
          ),
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
                _label,
                style: TextStyle(
                  fontSize: AppFont.px10_5,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '▾',
                style: TextStyle(fontSize: AppFont.px9_5, color: palette.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 筛选下拉选项行（设计稿 `.hdmenu .menu button` 1:1）：
/// hover = hi 底 + 字色 ink + **pointer 光标**（HTML button 默认行为）；
/// .on = 主色 + 加粗（透明底，非 hi）。
class _MenuOption extends StatefulWidget {
  const _MenuOption({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_MenuOption> createState() => _MenuOptionState();
}

class _MenuOptionState extends State<_MenuOption> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.hover,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _hover && !widget.active ? palette.hi : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: AppFont.px11_5,
              color: widget.active
                  ? palette.accent
                  : _hover
                  ? palette.ink
                  : palette.ink2,
              fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
