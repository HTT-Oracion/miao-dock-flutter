import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 开关（design.html `.switch`，一比一）。
///
/// ```css
/// .switch{width:30px;height:16px;border-radius:999px;background:var(--hi)}
/// .switch.on{background:var(--acc)}
/// .switch i{position:absolute;top:2px;left:2px;width:12px;height:12px;border-radius:999px;background:var(--ink2)}
/// .switch.on i{left:16px;background:var(--on-acc)}
/// ```
///
/// 不用 Material `Switch`：它的尺寸 / 轨道比例与稿子差得明显，
/// 而设置页里几十个开关都靠它，一眼就能看出不齐。
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged, this.enabled = true});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  static const double width = 30;
  static const double height = 16;
  static const double thumb = 12;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final track = value ? palette.acc : palette.hi;
    final knob = value ? palette.onAcc : palette.ink2;

    final active = enabled && onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: MouseRegion(
        cursor: active ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: GestureDetector(
          onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: enabled ? track : track.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: const Cubic(0.22, 0.61, 0.36, 1), // --ease
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: thumb,
                  height: thumb,
                  decoration: BoxDecoration(color: knob, shape: BoxShape.circle),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
