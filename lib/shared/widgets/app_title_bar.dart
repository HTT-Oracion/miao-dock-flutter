import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/tokens.dart';
import '../../core/window/window_controller.dart';

/// 桌面自绘标题栏（设计稿 G Top，56 高）：拖拽区 + 面包屑槽 + 右侧窗控。
/// 仅桌面渲染；Web / 移动端由 AppShell 分流到移动顶栏。
/// macOS 保留原生红绿灯（左侧预留 78px），自绘窗控仅在 Windows / Linux 渲染。
class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key, this.breadcrumb, this.actions});

  /// 面包屑等左侧内容（设计稿 TopL），由调用方按当前路由装配。
  final Widget? breadcrumb;

  /// 右侧动作区（窗控之前），如刷新、新建书架。
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: AppTokens.pageBg,
      child: DragToMoveArea(
        child: Row(
          children: [
            SizedBox(width: isMacosPlatform ? 78.0 : 22.0),
            Expanded(child: breadcrumb ?? const SizedBox.shrink()),
            ...?actions,
            const SizedBox(width: 12),
            if (showWindowControls) const _WindowControls(),
            const SizedBox(width: 10),
          ],
        ),
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
    const w = 34.0;
    const h = 26.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: danger ? const Color(0xFFC75450) : AppTokens.divider,
        child: SizedBox(
          width: w,
          height: h,
          child: Icon(icon, size: 13, color: AppTokens.textSecondary),
        ),
      ),
    );
  }
}
