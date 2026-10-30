import 'package:flutter/material.dart';

import 'tokens.dart';

/// 应用主题（深色为默认，令牌取自设计稿 G 帧；浅色主题随 L 帧落地补充）。
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppTokens.accent,
    brightness: Brightness.dark,
    surface: AppTokens.pageBg,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppTokens.pageBg,
    dividerColor: AppTokens.divider,
    textTheme: ThemeData.dark(useMaterial3: true).textTheme
        .apply(bodyColor: AppTokens.textPrimary, displayColor: AppTokens.textPrimary),
  );
}
