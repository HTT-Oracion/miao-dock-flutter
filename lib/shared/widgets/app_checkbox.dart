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
    return Checkbox(
      value: value,
      tristate: true,
      activeColor: AppTokens.accent,
      checkColor: AppTokens.pageBg,
      side: BorderSide(color: enabled ? AppTokens.textSecondary : AppTokens.progressTrack),
      onChanged: enabled ? onChanged : null,
    );
  }
}
