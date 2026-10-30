import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// 设置屏：占位，含引擎装配进度与移动端 / Web 桌面端地址配置（待落地）。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('设置 · 开发中', style: TextStyle(fontSize: 13, color: AppTokens.textSecondary)),
    );
  }
}
