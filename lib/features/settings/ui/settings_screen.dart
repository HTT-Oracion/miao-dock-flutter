import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';

/// 设置屏：占位，含引擎装配进度与移动端 / Web 桌面端地址配置（待落地）。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        AppLocalizations.of(context).settingsPending,
        style: const TextStyle(fontSize: 13, color: AppTokens.textSecondary),
      ),
    );
  }
}
