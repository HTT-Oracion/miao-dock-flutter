import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/toast.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';

/// 已隐藏作品浮层（设计稿 `openHidden()`）：
/// 隐藏 ≠ 删除 —— 文件与翻译记录都还在，每行必配「恢复」（`unhideBook`）。
Future<void> showHiddenBooksDialog(BuildContext context, List<String> hidden) => showAppDialog<void>(
  context: context,
  builder: (_) => _HiddenBooksDialog(hidden: hidden),
);

class _HiddenBooksDialog extends ConsumerWidget {
  const _HiddenBooksDialog({required this.hidden});

  final List<String> hidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return AppDialog(
      title: l10n.libHiddenTitle,
      subtitle: l10n.libHiddenBody,
      width: 420,
      actions: [
        AppButton(
          label: l10n.libHiddenDone,
          variant: AppButtonVariant.primary,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final name in hidden)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: palette.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(fontSize: AppFont.px12, color: palette.ink),
                      ),
                    ),
                    AppButton(
                      label: l10n.shelfRestore,
                      height: 26,
                      horizontalPadding: 10,
                      fontSize: AppFont.px11,
                      onTap: () async {
                        final navigator = Navigator.of(context);
                        try {
                          await ref.read(mangaSvcClientProvider).unhideBook(name);
                          await ref.read(libraryProvider.notifier).refresh();
                          navigator.pop();
                          if (context.mounted) {
                            showAppToast(context, l10n.shelfRestoredToast(name), tone: ToastTone.good);
                          }
                        } catch (e) {
                          if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
                        }
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
