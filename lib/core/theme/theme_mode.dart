import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/shell_prefs.dart';

/// 主题模式：设计稿 §01 明示深浅双主题「切主题只换变量不换结构」。
///
/// 初值来自壳层偏好（原项目 `theme/apply.ts` 的 `localMode`），改动即落盘。
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => readPersistedThemeMode() == 'light' ? ThemeMode.light : ThemeMode.dark;

  void toggle() => set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  void set(ThemeMode mode) {
    state = mode;
    persistThemeMode(mode == ThemeMode.light ? 'light' : 'dark');
  }
}
