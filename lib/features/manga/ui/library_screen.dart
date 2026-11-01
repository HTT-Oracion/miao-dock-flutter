import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
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
    // 默认态：左栏 + 网格。
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
