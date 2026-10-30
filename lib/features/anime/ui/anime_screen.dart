import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// 番剧屏（待定）：占位，追番周表 / 排行榜等功能随产品裁定补充。
class AnimeScreen extends StatelessWidget {
  const AnimeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('番剧 · 待定', style: TextStyle(fontSize: 13, color: AppTokens.textSecondary)),
    );
  }
}
