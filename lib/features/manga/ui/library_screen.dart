import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import 'library_detail.dart';
import 'library_shelf.dart';

/// 漫画库屏（设计稿 G 漫画库）：书架左栏 260 + 详情主区。
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
