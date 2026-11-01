import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_menu.dart';
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
    final selected = await showAppMenu(
      context,
      position: globalPosition,
      minWidth: 180,
      items: [
        AppMenuItem(value: 'open', label: l10n.shelfMenuOpenDir, icon: LucideIcons.folderUp),
        const AppMenuItem.separator(),
        AppMenuItem(value: 'resume', label: l10n.shelfMenuContinue, icon: LucideIcons.play),
        AppMenuItem(value: 'retranslate', label: l10n.shelfMenuRetranslate, icon: LucideIcons.rotateCcw),
        if (book.isBook)
          AppMenuItem(value: 'edit', label: l10n.shelfMenuEdit, icon: LucideIcons.pencil)
        else
          AppMenuItem(value: 'merge', label: l10n.shelfMenuMerge, icon: LucideIcons.gitMerge),
        AppMenuItem(
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
Future<(String, double)?> showMergeDialog(BuildContext context, {required String src}) => showDialog<(String, double)>(
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
    return AlertDialog(
      backgroundColor: AppTokens.card,
      title: Text(l10n.libMergeTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _target,
              isDense: true,
              style: const TextStyle(fontSize: 12),
              hint: Text(l10n.libMergeTargetHint, style: const TextStyle(fontSize: 12)),
              items: [
                for (final b in targets)
                  DropdownMenuItem(
                    value: b.key,
                    child: Text(b.name, style: const TextStyle(fontSize: 12)),
                  ),
              ],
              onChanged: (v) => setState(() => _target = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noController,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(labelText: l10n.libMergeNoHint, isDense: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel, style: const TextStyle(fontSize: 11.5)),
        ),
        FilledButton(
          onPressed: _target == null
              ? null
              : () {
                  final no = double.tryParse(_noController.text.trim());
                  if (no == null) return;
                  Navigator.of(context).pop((_target!, no));
                },
          child: Text(l10n.libMerge, style: const TextStyle(fontSize: 11.5)),
        ),
      ],
    );
  }
}

/// 删除确认（miao-dock `DeleteComicModal`）：勾选框**默认不勾** = 隐藏。
Future<bool?> showDeleteComicDialog(BuildContext context, {required LibBook book}) {
  return showDialog<bool>(
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
    final l10n = AppLocalizations.of(context);
    final book = widget.book;
    return AlertDialog(
      backgroundColor: AppTokens.card,
      title: Text(l10n.shelfDeleteTitle(book.name), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.shelfDeleteBody(book.chapterCount == 0 ? 1 : book.chapterCount, book.pageCount),
              style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: _deleteFiles,
                    onChanged: (v) => setState(() => _deleteFiles = v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.shelfDeleteWithFiles,
                    style: const TextStyle(fontSize: 11.5, color: AppTokens.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(l10n.shelfDeleteKeepHint, style: const TextStyle(fontSize: 10.5, color: AppTokens.textSecondary)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel, style: const TextStyle(fontSize: 11.5)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTokens.bad),
          onPressed: () => Navigator.of(context).pop(_deleteFiles),
          child: Text(
            l10n.shelfMenuDelete(book.isBook ? l10n.kindBook : l10n.kindChapter),
            style: const TextStyle(fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}
