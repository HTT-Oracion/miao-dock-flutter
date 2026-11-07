import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import '../../shared/responsive.dart';
import 'buttons.dart';

/// 移动端统一底部抽屉（`desgin/manga-viewer/assets/tokens.css` 的 `.sheet`）。
///
/// 位置由 [AppSheetPlacementScope] 注入：**窄屏贴底**（grabber + 顶圆角），
/// **宽屏贴右**（从右往左滑入的抽屉 + 左圆角，占满高度）。调用方无需关心。
/// 与 [AppDialog] 共用同一套 `title / subtitle / child / actions` 参数，
/// 由 `showAppDialog` 按 `context.isMobile` 自动分流，调用方无需各写一套。
enum AppSheetPlacement { bottom, right }

/// 告诉 [AppSheet] 自己在哪种容器里（由 `showAppSheet` 注入，调用方不用管）。
class AppSheetPlacementScope extends InheritedWidget {
  const AppSheetPlacementScope({super.key, required this.placement, required super.child});

  final AppSheetPlacement placement;

  static AppSheetPlacement of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSheetPlacementScope>()?.placement ?? AppSheetPlacement.bottom;

  @override
  bool updateShouldNotify(AppSheetPlacementScope oldWidget) => oldWidget.placement != placement;
}

class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.subtitle,
    this.icon,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final placement = AppSheetPlacementScope.of(context);
    return placement == AppSheetPlacement.right ? _buildSide(context) : _buildBottom(context);
  }

  /// 标题头（两种位置共用）：图标 + 标题 + 关闭。
  Widget _header(BuildContext context, {bool side = false}) {
    final palette = AppPalette.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(18, side ? 12 : 8, 18, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: palette.acc), const SizedBox(width: 8)],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 设计稿 `.sheet-head b`：14 / 700。
              style: TextStyle(fontSize: AppFont.px14, fontWeight: FontWeight.w700, color: palette.textPrimary),
            ),
          ),
          if (onClose != null)
            AppButton(
              icon: LucideIcons.x,
              width: 26,
              height: 26,
              border: false,
              variant: AppButtonVariant.ghost,
              // 只在「抽屉仍是栈顶」时才关：重复点 × / 已经被外部关掉后再点，
              // 都只当无事发生 —— 否则会 pop 掉下面的页面（go_router 断言崩溃）。
              onTap: () {
                final route = ModalRoute.of(context);
                if (route != null && !route.isCurrent) return;
                onClose!();
              },
            ),
        ],
      ),
    );
  }

  /// 宽屏：右侧抽屉（从右往左滑入），占满窗口高度。
  Widget _buildSide(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: 380,
      height: double.infinity,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(left: BorderSide(color: palette.line2)),
        boxShadow: [
          BoxShadow(color: palette.shadow.withValues(alpha: 0.45), blurRadius: 40, offset: const Offset(-12, 0)),
        ],
      ),
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, side: true),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(18, 12, 18, actions.isEmpty ? 24 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (subtitle != null) ...[
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: AppFont.px11, height: 1.7, color: palette.ink2),
                      ),
                      const SizedBox(height: 12),
                    ],
                    child,
                  ],
                ),
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: actions),
              ),
          ],
        ),
      ),
    );
  }

  /// 窄屏：底部抽屉（grabber + 顶圆角）。
  Widget _buildBottom(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: palette.panel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppMetrics.radiusSheetTop)),
          border: Border(top: BorderSide(color: palette.line2)),
          boxShadow: [
            BoxShadow(color: palette.shadow.withValues(alpha: 0.45), blurRadius: 40, offset: const Offset(0, -12)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // `.grabber`：36×4，居中。
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 2),
                decoration: BoxDecoration(color: palette.line2, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            _header(context),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(18, 12, 18, actions.isEmpty ? 24 : 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (subtitle != null) ...[
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: AppFont.px11, height: 1.7, color: palette.ink2),
                      ),
                      const SizedBox(height: 12),
                    ],
                    child,
                  ],
                ),
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: actions),
              ),
          ],
        ),
      ),
    );
  }
}

/// 抽屉里的操作菜单行（设计稿 `#mMenuSheet`：34 图标块 + 主/副两行 + 右箭头）。
class AppSheetAction extends StatelessWidget {
  const AppSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = danger ? palette.bad : palette.ink;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: danger ? palette.bad.withValues(alpha: 0.12) : palette.accSoft,
                borderRadius: BorderRadius.circular(10),
                border: danger ? Border.all(color: palette.bad.withValues(alpha: 0.4)) : null,
              ),
              child: Icon(icon, size: 16, color: danger ? palette.bad : palette.acc),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w600, color: fg),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                    ),
                  ],
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 14, color: palette.mut),
          ],
        ),
      ),
    );
  }
}

/// 抽屉统一入口：遮罩、键盘避让与上滑动画都在这里收口。
///
/// 🔴 **不要传外部 `transitionAnimationController`**：一旦由外部持有，
/// 路由的入场/退场动画就收不到 `dismissed` 状态，`pop()` 之后抽屉
/// **仍留在屏幕上**（实测：route 已 inactive，widget 还在）。用户会以为没关上
/// 再点一次 ×，那次 pop 就落到下面的页面上 —— go_router 随即断言
/// `currentConfiguration.isNotEmpty` 崩溃。时长改用 `sheetAnimationStyle` 表达。
Future<T?> showAppSheet<T>({required BuildContext context, required WidgetBuilder builder}) {
  // 宽屏：右侧抽屉（从右往左滑入）。设计稿的抽屉在桌面就是右侧面板，
  // 贴底弹层在 1440 宽的窗口里离鼠标太远，操作动线是反的。
  if (!context.isMobile) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: AppPalette.of(context).shadow.withValues(alpha: 0.45),
      transitionDuration: AppMotion.drawer,
      // 右侧抽屉没有 BottomSheet 那层 Material：Slider / InkWell / AppButton
      // 都要 Material 祖先，这里补一层透明 Material。
      pageBuilder: (ctx, _, _) => Material(
        type: MaterialType.transparency,
        child: Align(
          alignment: Alignment.centerRight,
          child: AppSheetPlacementScope(placement: AppSheetPlacement.right, child: builder(ctx)),
        ),
      ),
      transitionBuilder: (ctx, animation, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: AppMotion.morphCurve, reverseCurve: AppMotion.morphCurve)),
        child: child,
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    // 跟着当前 Navigator（壳层分支）走，不越级弹到根导航器上。
    useRootNavigator: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppPalette.of(context).shadow.withValues(alpha: 0.45),
    // 抽屉动效 380ms（tokens.css `--d-drawer`），进出对称。
    sheetAnimationStyle: const AnimationStyle(duration: AppMotion.drawer, reverseDuration: AppMotion.drawer),
    builder: (ctx) => Padding(
      // 输入框弹键盘时抽屉整体上移，不被键盘盖住。
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: AppSheetPlacementScope(placement: AppSheetPlacement.bottom, child: builder(ctx)),
    ),
  );
}
