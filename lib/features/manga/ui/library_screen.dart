import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../controller/library_controller.dart';
import 'library_detail.dart';
import 'library_grid.dart';
import 'library_shelf.dart';

/// 漫画库屏（ver1.0 `VIEWS['manga/library']`）。
///
/// 两种态，与设计稿一致：
/// - **未选中**：只显示「全部漫画」网格（`lib-grid`），**没有左栏**；
/// - **已选中**：左栏书架（260）+ 右侧详情（`detail-hero` + 章节区）。
///
/// 注意：进库**不自动选中第一本** —— 未选中时就是网格态。
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedBookProvider);
    final books = ref.watch(libraryProvider).value ?? ref.read(libraryProvider.notifier).lastGood;
    final hasSelection = selected != null && books.any((b) => b.key == selected);

    if (!hasSelection) {
      return const LibraryGrid();
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LibraryShelf(),
        const VerticalDivider(width: 1, color: AppTokens.divider),
        const Expanded(child: LibraryDetail()),
      ],
    );
  }
}
