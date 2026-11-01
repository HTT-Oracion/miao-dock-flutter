import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 骨架原子块（全项目**唯一**骨架实现）。
///
/// 用法：需要占位就拼 [SkeletonBox]，不要在各页写 `Container + palette.hi`。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 10, this.radius = 4});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: palette.hi, borderRadius: BorderRadius.circular(radius)),
    );
  }
}

/// 表格行骨架：左侧一列 + 若干列（队列页用）。
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.rows = 9, this.rowHeight = 58});

  final int rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          const SizedBox(height: 40),
          for (var i = 0; i < rows; i++)
            Container(
              height: rowHeight,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.divider)),
              ),
              child: Row(
                children: [
                  const SkeletonBox(width: 70, height: 12),
                  const SizedBox(width: 14),
                  for (final w in const [52.0, 52.0, 52.0, 64.0]) ...[
                    SkeletonBox(width: w, height: 10),
                    const SizedBox(width: 14),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 卡片行骨架：封面块 + 两行文字（书架用）。
class SkeletonCards extends StatelessWidget {
  const SkeletonCards({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      children: [
        for (var i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.panel,
              border: Border.all(color: palette.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const SkeletonBox(width: 34, height: 46),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonBox(width: 120, height: 10),
                      SizedBox(height: 8),
                      SkeletonBox(width: 72, height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
