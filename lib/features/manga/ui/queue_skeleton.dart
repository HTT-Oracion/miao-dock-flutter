import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';

/// 队列加载骨架（设计稿 H 加载态）：SumBar 骨架 + 表格骨架行。
class QueueSkeleton extends StatelessWidget {
  const QueueSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              _Skel(w: 70, h: 12),
              const SizedBox(width: 14),
              for (final w in const [52.0, 52.0, 52.0, 64.0]) ...[_Skel(w: w, h: 10), const SizedBox(width: 14)],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                Container(height: 40),
                for (var i = 0; i < 9; i++)
                  Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppTokens.divider)),
                    ),
                    child: Row(
                      children: [
                        _Skel(w: 180, h: 12),
                        const Spacer(),
                        _Skel(w: 120, h: 4),
                        const SizedBox(width: 60),
                        _Skel(w: 60, h: 12),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Skel extends StatelessWidget {
  const _Skel({required this.w, required this.h});

  final double w;
  final double h;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: AppTokens.progressTrack, borderRadius: BorderRadius.circular(4)),
    );
  }
}
