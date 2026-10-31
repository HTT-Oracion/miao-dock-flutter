import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/tokens.dart';
import '../../core/window/window_controller.dart';

/// 桌面自绘标题栏（design.html §03：高 56）：拖拽区 + 面包屑槽 + 右侧动作区 + 窗控。
///
/// ## 顶部让位带（`topInset`）
/// macOS 用 `TitleBarStyle.hidden` 保留原生红绿灯，而红绿灯是**叠在客户区左上角**的，
/// 恰好压在侧栏 logo 的位置上。故 macOS 下侧栏品牌行与工具条都要整体下移
/// [AppMetrics.macTrafficLightBand]，这条带子本身仍是拖拽区 —— 否则窗口没法拖动。
class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key, this.breadcrumb, this.actions, this.topInset = 0});

  /// 面包屑等左侧内容（design.html TopL），由调用方按当前路由装配。
  final Widget? breadcrumb;

  /// 右侧动作区（窗控之前），如刷新、新建书架。
  final List<Widget>? actions;

  /// 顶部让位高度（macOS 红绿灯带）；0 = 无让位。
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: AppMetrics.toolbarHeight + topInset,
      color: palette.bg,
      child: Column(
        children: [
          if (topInset > 0)
            SizedBox(
              height: topInset,
              child: isDesktopPlatform ? const DragToMoveArea(child: SizedBox.expand()) : null,
            ),
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  // 非 macOS 自绘窗控在右侧，左侧只留常规内边距；macOS 的红绿灯已由让位带避开。
                  const SizedBox(width: 22),
                  Expanded(child: breadcrumb ?? const SizedBox.shrink()),
                  ...?actions,
                  const SizedBox(width: 12),
                  if (showWindowControls) const _WindowControls(),
                  const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ControlButton(icon: LucideIcons.minus, onTap: windowManager.minimize),
        _ControlButton(icon: LucideIcons.square, onTap: windowManager.maximize),
        _ControlButton(icon: LucideIcons.x, danger: true, onTap: windowManager.close),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.onTap, this.danger = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // app.css `.winctl button`：34×26、圆角 6、hover 变 `--hi`；关闭键 hover 为 `--bad`。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
            hoverColor: danger ? palette.bad : palette.hi,
            child: SizedBox(
              width: 34,
              height: 26,
              child: Icon(icon, size: 13, color: danger ? palette.ink2 : palette.ink2),
            ),
          ),
        ),
      ),
    );
  }
}
