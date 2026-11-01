import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 主题化三态勾选框：表头半选 / 行勾选（设计稿 H Note 03）；
/// 禁用置灰（翻译中 / 排队中不可勾），不弹错误。
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({super.key, required this.value, this.onChanged, this.enabled = true, this.tristate = true});

  /// null = 半选（表头本页部分勾选）。
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool enabled;

  /// 三态开关（表头/行选择用 true）；**纯布尔切换的确认弹窗传 false** ——
  /// tristate 下点击已勾项会先出 null，把「删除」变成「不删」再变「隐藏」，语义错乱。
  final bool tristate;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final active = enabled && onChanged != null;
    return MouseRegion(
      // 启用 = 手型；禁用 = 禁止光标。
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: Checkbox(
        value: value,
        tristate: tristate,
        activeColor: palette.accent,
        checkColor: palette.pageBg,
        side: BorderSide(color: enabled ? palette.textSecondary : palette.progressTrack),
        onChanged: active ? onChanged : null,
      ),
    );
  }
}
