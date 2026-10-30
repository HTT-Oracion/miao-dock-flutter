import 'package:flutter/material.dart';

/// 设计令牌装配点（AGENTS.md §3）：令牌经 ThemeExtension 扩展后在此并入 ThemeData。
/// 当前为占位主题，令牌体系随首个屏落地定稿。
ThemeData buildLightTheme() {
  return ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A6CF7)));
}
