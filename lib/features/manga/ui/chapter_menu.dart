import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:protocol/protocol.dart' show jsNumStr;

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_menu.dart';
import '../../../shared/widgets/toast.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';
import '../domain/lib_book.dart';

/// 章节卡片上的「⋯」操作菜单（D-094）。
///
/// 项集对照 miao-dock `chapters.tsx`：
/// 打开目录 / 续做本话（副标：待续做 N 张）/ 重译本话 / 编辑话数 / 删除本话（恒置灰）。
class ChapterMenuButton extends ConsumerWidget {
  const ChapterMenuButton({super.key, required this.book, required this.chapter});

  final LibBook book;
  final LibChapter chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pending = chapter.pageCount - chapter.donePages;
    return _MenuTrigger(
      onSelected: (v) => _run(context, ref, v),
      items: [
        AppMenuItem(value: 'open', label: l10n.chapterMenuOpenDir, icon: LucideIcons.folderUp),
        AppMenuItem(
          value: 'resume',
          label: l10n.chapterMenuResume,
          icon: LucideIcons.play,
          sub: pending > 0 ? l10n.chapterMenuResumeSub(pending) : l10n.chapterMenuResumeNone,
          enabled: pending > 0,
        ),
        AppMenuItem(
          value: 'retranslate',
          label: l10n.chapterMenuRetranslate,
          icon: LucideIcons.rotateCcw,
          enabled: chapter.pageCount > 0,
        ),
        AppMenuItem(value: 'renumber', label: l10n.chapterMenuEditNo, icon: LucideIcons.pencil),
        // 恒置灰：归并后的章节不能单独删。
        AppMenuItem(
          value: 'delete',
          label: l10n.chapterMenuDelete,
          icon: LucideIcons.trash2,
          enabled: false,
          danger: true,
        ),
      ],
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, String action) async {
    final l10n = AppLocalizations.of(context);
    final client = ref.read(mangaSvcClientProvider);
    try {
      switch (action) {
        case 'open':
          await client.revealBook('${book.key}/${chapter.dirName}');
        case 'resume':
          await client.resumeChapter(book.key, chapter.no);
          if (context.mounted) {
            showAppToast(context, l10n.chapterResumeOk(book.name), tone: ToastTone.good);
          }
        case 'retranslate':
          await client.retranslateChapter(book.key, chapter.no);
          if (context.mounted) {
            showAppToast(context, l10n.chapterRetranslateOk(book.name), tone: ToastTone.good);
          }
        case 'renumber':
          final newNo = await _askNewNo(context);
          if (newNo == null) return;
          await client.renumberChapter(book.key, chapter.no, newNo: newNo);
          await ref.read(libraryProvider.notifier).refresh();
          if (context.mounted) {
            showAppToast(context, l10n.chapterRenumberOk(jsNumStr(newNo)), tone: ToastTone.good);
          }
      }
    } catch (e) {
      if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
    }
  }

  Future<double?> _askNewNo(BuildContext context) async {
    final ctrl = TextEditingController(text: jsNumStr(chapter.no));
    final l10n = AppLocalizations.of(context);
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTokens.card,
        title: Text(l10n.chapterEditNoTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 260,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(labelText: l10n.chapterEditNoHint, isDense: true),
            onSubmitted: (v) => Navigator.of(context).pop(double.tryParse(v.trim())),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionCancel, style: const TextStyle(fontSize: 11.5)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(double.tryParse(ctrl.text.trim())),
            child: Text(l10n.libEditInfoOk, style: const TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }
}

class _MenuTrigger extends StatefulWidget {
  const _MenuTrigger({required this.items, required this.onSelected});

  final List<AppMenuItem> items;
  final ValueChanged<String> onSelected;

  @override
  State<_MenuTrigger> createState() => _MenuTriggerState();
}

class _MenuTriggerState extends State<_MenuTrigger> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (d) async {
          final value = await showAppMenu(context, position: d.globalPosition, minWidth: 170, items: widget.items);
          if (value != null) widget.onSelected(value);
        },
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? AppTokens.navBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(LucideIcons.ellipsis, size: 13, color: _hover ? AppTokens.textPrimary : AppTokens.textSecondary),
        ),
      ),
    );
  }
}
