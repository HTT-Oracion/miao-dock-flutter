import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设置页当前分区（general / translate / media / resource / about）。
///
/// 为什么放在 controller 层而不是屏内私有：**壳层也要能重置它**。
/// 设置页不参与模块保活（见 `app_shell.dart` 的 `_goSettings`），每次从侧栏 /
/// 底栏进入都要回到「通用」；若 provider 藏在 UI 文件里，壳层就只能反向依赖屏。
final settingsSectionProvider = NotifierProvider<SettingsSectionNotifier, String>(SettingsSectionNotifier.new);

class SettingsSectionNotifier extends Notifier<String> {
  /// 默认分区（`settingsNavGeneral`）。
  static const initial = 'general';

  @override
  String build() => initial;

  void select(String id) => state = id;

  /// 外部跳转（如引导页「去设置远程配置」）指定分组。
  void jump(String id) {
    if (state != id) state = id;
  }

  /// 回到默认分区 —— 壳层每次以「点设置」的方式进入时调用。
  void reset() => state = initial;
}
