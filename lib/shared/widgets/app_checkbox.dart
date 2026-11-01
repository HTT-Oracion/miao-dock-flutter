import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 主题化三态勾选框：表头半选 / 行勾选（设计稿 H Note 03）；
/// 禁用置灰（翻译中 / 排队中不可勾），不弹错误。
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({super.key, required this.value, this.onChanged, this.enabled = true});

  /// null = 半选（表头本页部分勾选）。
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final active = enabled && onChanged != null;
    return MouseRegion(
      // 启用 = 手型；禁用 = 禁止光标。
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: Checkbox(
        value: value,
        tristate: true,
        activeColor: palette.accent,
        checkColor: palette.pageBg,
        side: BorderSide(color: enabled ? palette.textSecondary : palette.progressTrack),
        onChanged: active ? onChanged : null,
      ),
    );
  }
}
