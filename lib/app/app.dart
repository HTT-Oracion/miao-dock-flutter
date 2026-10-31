import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/theme.dart';
import '../core/theme/theme_mode.dart';
import '../l10n/app_localizations.dart';
import 'router/routes.dart';

/// 应用根组件：深浅双主题挂载 + go_router（设计稿 §01 / §06）。
///
/// `theme` 对应浅色（Material 的 `theme` 是默认亮色槽），`darkTheme` 对应深色；
/// `themeMode` 由 [themeModeProvider] 控制，默认深色。
class MiaoDockApp extends ConsumerWidget {
  const MiaoDockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      // 当前仅中文，不做语言切换；supportedLocales 只列 zh（见 D-006）。
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
