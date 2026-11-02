import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/responsive.dart';
import '../../../shared/widgets/buttons.dart';
import '../controller/library_controller.dart';
import 'library_detail.dart';
import 'library_grid.dart';
import 'library_shelf.dart';

/// 漫画库屏（ver1.0 `VIEWS['manga/library']`）：
///
/// - **默认**：左侧书架列表 + 右侧「全部漫画」网格（`.lib-body` = shelf + main）；
/// - **点击某本后**：**左侧列表消失**，详情占满右侧（`.libDetail` 分支），顶部有「返回书架」。
///
/// 进库时 `selectedBookProvider` 为 null ⇒ 停在默认态，**不自动选中第一本**。
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final selected = ref.watch(selectedBookProvider);
    final books = ref.watch(libraryProvider).value ?? ref.read(libraryProvider.notifier).lastGood;
    final hasSelection = selected != null && books.any((b) => b.key == selected);

    if (hasSelection) {
      // 详情态：左栏隐藏，详情占满（含「返回书架」）。
      return const LibraryDetail();
    }
    // 默认态：宽屏 = 左书架 + 右网格；**窄屏只留网格**（手机放不下双栏）。
    // 书架入口改到顶部按钮（否则「未归并的单话」在手机上无处可达）。
    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _MobileShelfEntry(),
          Expanded(child: LibraryGrid()),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LibraryShelf(),
        VerticalDivider(width: 1, color: palette.divider),
        const Expanded(child: LibraryGrid()),
      ],
    );
  }
}

/// 窄屏的「书架」入口：点开弹出底部抽屉列出书架内容（含未归并单话）。
class _MobileShelfEntry extends ConsumerWidget {
  const _MobileShelfEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: AppButton(
              label: l10n.shelfTitle,
              icon: LucideIcons.library,
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: AppPalette.of(context).panel,
                builder: (_) => const SizedBox(height: 420, child: LibraryShelf()),
              ),
              variant: AppButtonVariant.secondary,
              height: 32,
              horizontalPadding: 12,
              fontSize: AppFont.px10_5,
            ),
          ),
        ],
      ),
    );
  }
}
