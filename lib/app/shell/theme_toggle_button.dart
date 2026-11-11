import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme_mode.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';

/// 音乐模块主题三态按钮（设计稿 N07 / N31）。
///
/// 循环顺序与原型一致：跟随系统 → 深色 → 浅色 → 跟随系统；图标随档位换形。
/// 桌面顶栏与移动端页签条共用同一份控件，点击即写盘（[ThemeModeNotifier.cycle]）。
class ThemeToggleButton extends ConsumerStatefulWidget {
  const ThemeToggleButton({super.key, this.size = 30, this.iconSize = 16});

  final double size;
  final double iconSize;

  @override
  ConsumerState<ThemeToggleButton> createState() => _ThemeToggleButtonState();
}

class _ThemeToggleButtonState extends ConsumerState<ThemeToggleButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(themeModeProvider);
    final (icon, label) = switch (mode) {
      ThemeMode.system => (LucideIcons.monitor, l10n.themeModeSystem),
      ThemeMode.light => (LucideIcons.sun, l10n.settingLight),
      ThemeMode.dark => (LucideIcons.moon, l10n.settingDark),
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: l10n.themeModeTooltip(label),
        child: GestureDetector(
          onTap: () => ref.read(themeModeProvider.notifier).cycle(),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.hover,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _hover ? palette.hi : Colors.transparent,
              borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
            ),
            child: Icon(icon, size: widget.iconSize, color: palette.ink2),
          ),
        ),
      ),
    );
  }
}
