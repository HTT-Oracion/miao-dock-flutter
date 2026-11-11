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

/// 系统「减少动态效果」判据（设计稿 N34 / M06）。
///
/// Flutter 把该无障碍偏好转成 `MediaQuery.disableAnimations`；动效实现应读它，
/// 不要自己去读平台通道。降级口径与设计稿一致：位移 / 旋转 / 条纹动画归零，
/// 只保留透明度与颜色变化。
extension AppMotionPreference on BuildContext {
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}
