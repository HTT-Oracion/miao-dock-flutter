import 'package:flutter/material.dart';

import 'tokens.dart';

/// 应用主题：深浅双主题共用一套语义令牌，切主题只换值不换结构（design.html §01）。
///
/// 说明：Material 的 `ColorScheme` 只承载"内置控件兜底色"，业务 UI 一律读
/// [AppPalette]，避免同一语义出现两套真值。
ThemeData buildAppTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  final scheme = ColorScheme.fromSeed(seedColor: palette.acc, brightness: brightness).copyWith(
    surface: palette.bg,
    primary: palette.acc,
    onPrimary: palette.onAcc,
    error: palette.bad,
    outline: palette.line2,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.bg,
    canvasColor: palette.bg,
    dividerColor: palette.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: palette.card,
    fontFamily: _fontFamily,
    textTheme: _textTheme(palette, brightness),
    extensions: [palette],
  );
}

/// 设计稿标注用字：Noto Sans SC，回退 PingFang SC / Microsoft YaHei（§02）。
/// 未打包字体文件，交给系统按平台就近回落；`fontFamilyFallback` 兜住非中文平台。
const String _fontFamily = 'Noto Sans SC';
const List<String> _kFallback = ['PingFang SC', 'Microsoft YaHei', 'Noto Sans CJK SC'];

TextTheme _textTheme(AppPalette palette, Brightness brightness) {
  final base = brightness == Brightness.dark ? Typography.material2021().white : Typography.material2021().black;
  return base.copyWith(
    // 页标题 15 / 700（§02）
    titleMedium: TextStyle(
      fontSize: AppType.pageTitle,
      fontWeight: AppType.pageTitleWeight,
      color: palette.ink,
      fontFamilyFallback: _kFallback,
    ),
    // 分区标题 12.5 / 700
    titleSmall: TextStyle(
      fontSize: AppType.sectionTitle,
      fontWeight: AppType.sectionTitleWeight,
      color: palette.ink,
      fontFamilyFallback: _kFallback,
    ),
    // 条目标题 11 / 600
    labelLarge: TextStyle(
      fontSize: AppType.itemTitle,
      fontWeight: AppType.itemTitleWeight,
      color: palette.ink,
      fontFamilyFallback: _kFallback,
    ),
    // 正文 / 说明 9.5 / 400
    bodySmall: TextStyle(
      fontSize: AppType.body,
      fontWeight: AppType.bodyWeight,
      color: palette.mut,
      fontFamilyFallback: _kFallback,
    ),
    bodyMedium: TextStyle(fontSize: AppType.itemTitle, color: palette.ink2, fontFamilyFallback: _kFallback),
  );
}
