import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/responsive.dart';
import '../controller/library_controller.dart';
import 'library_detail.dart';
import 'library_grid.dart';
import 'library_shelf.dart';

/// 漫画库屏（逐帧对齐 `desgin/modules/library.html`）：
///
/// - **宽屏**：左栏书架**常驻 250**（`.lib-wrap` = 250px + 1fr）+ 右栏详情。
///   设计稿里点书架行只换右栏内容，书架**从不消失**，也没有「返回书架」按钮。
/// - **窄屏**：只有 `.mlib` 网格；点卡片后详情从右侧滑入覆盖（`.mdetail`）。
///
/// 进库默认选中第一本：设计稿右栏恒有内容（`active = 「星轨邮差」`），
/// 空右栏与稿子不符。
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _autoSelected = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final books = ref.watch(libraryProvider).value ?? ref.read(libraryProvider.notifier).lastGood;

    // 设计稿右栏恒有内容（`active = 「星轨邮差」`）——仅**宽屏**自动选中第一本；
    // 移动端初始停在网格（`.mlib`），点卡片才滑入详情。
    if (!_autoSelected && books.isNotEmpty && !context.isMobile) {
      _autoSelected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(selectedBookProvider) == null) {
          ref.read(selectedBookProvider.notifier).select(books.first.key);
        }
      });
    }

    if (context.isMobile) {
      // 窄屏：网格（全部 = 单本 + 未归并单话）铺底；选中即 `.mdetail` 滑入覆盖。
      final selected = ref.watch(selectedBookProvider);
      final hasSelection = books.any((b) => b.key == selected);
      return Stack(
        children: [
          const LibraryGrid(),
          if (hasSelection) const Positioned.fill(child: LibraryDetail()),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LibraryShelf(),
        VerticalDivider(width: 1, color: palette.divider),
        const Expanded(child: LibraryDetail()),
      ],
    );
  }
}
