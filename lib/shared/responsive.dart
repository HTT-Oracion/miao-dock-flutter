import 'package:flutter/widgets.dart';

import '../core/theme/tokens.dart';

/// 全项目**唯一**的窄/宽屏判据（AGENTS §4 第 16 条）。
///
/// 断点取设计稿 `@media (max-width:768px)`，与外壳 (`AppShell`) 一致。
/// 不要再在页面里写 `720` / `900` 之类的魔数 —— 三处各写一个断点，
/// 结果就是「外壳已经切成抽屉、页面还是双栏」这种半截适配。
extension AppResponsive on BuildContext {
  /// 当前是否窄屏（手机 / 小窗口）。
  bool get isMobile => MediaQuery.sizeOf(this).width <= AppMetrics.breakpoint;

  /// 页面可用宽度（`LayoutBuilder` 之外的快捷方式）。
  double get viewportWidth => MediaQuery.sizeOf(this).width;
}
