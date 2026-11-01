import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_checkbox.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/app_picker.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/toast.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';
import '../domain/lib_book.dart';

/// 书架项目右键菜单（阶段 D）。
///
/// 项序照 miao-dock `LibraryScreen.renderComicMenu`：
/// **打开目录 / ─ / 继续翻译 / 重新翻译整本 / （编辑信息 | 归并到…）/ 删除**
/// ——「看得见的在前、破坏性的在后」。
class ShelfContextMenu {
  static Future<void> show(BuildContext context, WidgetRef ref, LibBook book, Offset globalPosition) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showAppMenuAt(
      context,
      position: globalPosition,
      minWidth: 180,
      items: [
        AppDropdownItem(value: 'open', label: l10n.shelfMenuOpenDir, icon: LucideIcons.folderUp),
        const AppDropdownItem.divider(),
        AppDropdownItem(value: 'resume', label: l10n.shelfMenuContinue, icon: LucideIcons.play),
        AppDropdownItem(value: 'retranslate', label: l10n.shelfMenuRetranslate, icon: LucideIcons.rotateCcw),
        if (book.isBook)
          AppDropdownItem(value: 'edit', label: l10n.shelfMenuEdit, icon: LucideIcons.pencil)
        else
          AppDropdownItem(value: 'merge', label: l10n.shelfMenuMerge, icon: LucideIcons.gitMerge),
        AppDropdownItem(
          value: 'delete',
          label: l10n.shelfMenuDelete(book.isBook ? l10n.kindBook : l10n.kindChapter),
          icon: LucideIcons.trash2,
          danger: true,
        ),
      ],
    );
    if (selected == null || !context.mounted) return;
    await _run(context, ref, book, selected);
  }

  static Future<void> _run(BuildContext context, WidgetRef ref, LibBook book, String action) async {
    final l10n = AppLocalizations.of(context);
    final client = ref.read(mangaSvcClientProvider);
    try {
      switch (action) {
        case 'open':
          await client.revealBook(book.key);
        case 'resume':
          final plan = await client.getResumePlan(book.key);
          if (plan.pendingCount == 0) {
            if (context.mounted) showAppToast(context, l10n.shelfAllTranslated, tone: ToastTone.info);
            return;
          }
          await client.resumeBook(book.key);
          if (context.mounted) showAppToast(context, l10n.shelfContinueOk(book.name), tone: ToastTone.good);
        case 'retranslate':
          await client.retranslateBook(book.key);
          if (context.mounted) showAppToast(context, l10n.shelfRetranslateOk(book.name), tone: ToastTone.good);
        case 'merge':
          // 归并交互与详情页一致（选目标书 + 话号）。
          final result = await showMergeDialog(context, src: book.key);
          if (result == null) return;
          await client.mergeChapter(book.key, targetBook: result.$1, no: result.$2);
          await ref.read(libraryProvider.notifier).refresh();
          if (context.mounted) showAppToast(context, l10n.shelfMergeDone(book.name), tone: ToastTone.good);
        case 'delete':
          final confirmed = await showDeleteComicDialog(context, book: book);
          if (confirmed == null) return;
          await client.deleteBook(book.key, deleteFiles: confirmed);
          await ref.read(libraryProvider.notifier).refresh();
          if (context.mounted) {
            showAppToast(
              context,
              confirmed ? l10n.shelfDeletedFilesDone(book.name) : l10n.shelfHiddenDone(book.name),
              tone: ToastTone.info,
            );
          }
      }
    } catch (e) {
      if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
    }
  }
}

/// 归并对话框（书架菜单与详情页共用）。
Future<(String, double)?> showMergeDialog(BuildContext context, {required String src}) =>
    showAppDialog<(String, double)>(
      context: context,
      builder: (_) => _MergeDialog(src: src),
    );

class _MergeDialog extends ConsumerStatefulWidget {
  const _MergeDialog({required this.src});

  final String src;

  @override
  ConsumerState<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends ConsumerState<_MergeDialog> {
  final _noController = TextEditingController();
  String? _target;

  @override
  void dispose() {
    _noController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final books = ref.watch(libraryProvider).value ?? const <LibBook>[];
    final targets = books.where((b) => b.isBook).toList();
    return AppDialog(
      title: l10n.libMergeTitle,
      actions: [
        AppButton(label: l10n.actionCancel, onTap: () => Navigator.of(context).pop()),
        AppButton(
          label: l10n.libMerge,
          variant: AppButtonVariant.primary,
          onTap: _target == null
              ? null
              : () {
                  final no = double.tryParse(_noController.text.trim());
                  if (no == null) return;
                  Navigator.of(context).pop((_target!, no));
                },
        ),
      ],
      child: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // 必须显式左对齐：Column 默认 center，而下面两行宽度不同会错位。
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 目标漫画可能很多 → 用**可搜索选择器**（下拉里塞搜索框在 M3 下点不中）。
            SizedBox(
              width: 300,
              child: AppButton(
                label: _target == null ? l10n.libMergeTargetHint : targets.firstWhere((b) => b.key == _target).name,
                onTap: () async {
                  final picked = await showAppPicker<String>(
                    context: context,
                    title: l10n.libMergeTitle,
                    searchHint: l10n.libMergeSearchHint,
                    emptyText: l10n.libMergeNoResult,
                    current: _target,
                    items: [for (final b in targets) (b.key, b.name)],
                  );
                  if (picked != null && mounted) setState(() => _target = picked);
                },
                variant: AppButtonVariant.secondary,
                height: 32,
                horizontalPadding: 10,
                fontSize: AppFont.px10,
              ),
            ),
            const SizedBox(height: 10),
            AppInput(controller: _noController, hint: l10n.libMergeNoHint),
          ],
        ),
      ),
    );
  }
}

/// 删除确认（miao-dock `DeleteComicModal`）：勾选框**默认不勾** = 隐藏。
Future<bool?> showDeleteComicDialog(BuildContext context, {required LibBook book}) {
  return showAppDialog<bool>(
    context: context,
    builder: (_) => _DeleteDialog(book: book),
  );
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.book});

  final LibBook book;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  bool _deleteFiles = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final book = widget.book;
    return AppDialog(
      title: l10n.shelfDeleteTitle(book.name),
      actions: [
        AppButton(label: l10n.actionCancel, onTap: () => Navigator.of(context).pop()),
        AppButton(
          label: l10n.shelfMenuDelete(book.isBook ? l10n.kindBook : l10n.kindChapter),
          variant: AppButtonVariant.danger,
          onTap: () => Navigator.of(context).pop(_deleteFiles),
        ),
      ],
      // 确认框收窄：内容只有一段正文 + 一个勾选项，340 宽显得空。
      child: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.shelfDeleteBody(book.chapterCount == 0 ? 1 : book.chapterCount, book.pageCount),
              style: TextStyle(fontSize: AppFont.px11_5, height: 1.5, color: palette.textSecondary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  // 勾选框走共享 AppCheckbox（tristate: false —— 确认弹窗是纯布尔切换）。
                  child: AppCheckbox(
                    value: _deleteFiles,
                    tristate: false,
                    onChanged: (v) => setState(() => _deleteFiles = v ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.shelfDeleteWithFiles,
                    style: TextStyle(fontSize: AppFont.px11_5, color: palette.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.shelfDeleteKeepHint,
              style: TextStyle(fontSize: AppFont.px10_5, height: 1.4, color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
