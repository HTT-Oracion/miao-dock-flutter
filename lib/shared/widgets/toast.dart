import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 应用吐司：轻提示统一入口（设计稿 H Note 06 的文案由调用方逐字给出）。
void showAppToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 12.5, color: AppTokens.textPrimary)),
      backgroundColor: AppTokens.navBg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
