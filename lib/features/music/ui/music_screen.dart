import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// 音乐屏（四平台 + 本地）：占位，随音乐域落地替换。
class MusicScreen extends StatelessWidget {
  const MusicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('音乐 · 开发中', style: TextStyle(fontSize: 13, color: AppTokens.textSecondary)),
    );
  }
}
