import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import 'buttons.dart' show kButtonRadius;

/// 全项目**唯一**输入框实现（单行文本）。
///
/// 规范（对齐 buttons 的圆角基准）：
/// - 高度默认 36（比 26 的按钮更高，便于点击与阅读，可传 [height] 覆盖）；
/// - 圆角恒为 [kButtonRadius]；
/// - **必须有 placeholder**（[hint] 必填）—— 空输入框没有提示会让用户不知道填什么；
/// - 错误态用 [errorText]，描边转 `bad`；
/// - 前后缀图标可选。
class AppInput extends StatelessWidget {
  const AppInput({
    super.key,
    required this.hint,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.enabled = true,
    this.obscure = false,
    this.prefixIcon,
    this.suffix,
    this.height = 36,
    this.fontSize = 12,
    this.keyboardType,
    this.inputFormatters,
    this.autofocus = false,
    this.maxLines = 1,
  });

  /// 占位文案（**必填**，规范要求）。
  final String hint;
  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final bool enabled;
  final bool obscure;
  final IconData? prefixIcon;
  final Widget? suffix;
  final double height;
  final double fontSize;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final borderColor = errorText != null ? palette.bad : palette.divider;
    final radius = BorderRadius.circular(kButtonRadius);

    return SizedBox(
      height: maxLines > 1 ? null : height,
      child: TextField(
        controller: controller,
        // initialValue 与 controller 不能同时给（TextField 的限制）。
        decoration: _decoration(palette, borderColor, radius),
        enabled: enabled,
        obscureText: obscure,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        autofocus: autofocus,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        style: TextStyle(fontSize: fontSize, color: palette.textPrimary),
        cursorColor: palette.accent,
      ),
    );
  }

  InputDecoration _decoration(AppPalette palette, Color borderColor, BorderRadius radius) {
    final border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: borderColor),
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: palette.navBg,
      hintText: hint,
      hintStyle: TextStyle(fontSize: fontSize, color: palette.textSecondary),
      errorText: errorText,
      errorStyle: TextStyle(fontSize: 10, color: palette.bad),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      enabledBorder: border,
      disabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: palette.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: borderColor == palette.bad ? palette.bad : palette.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: palette.bad),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: palette.bad),
      ),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 14, color: palette.textSecondary) : null,
      prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }
}
