import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';

/// 番剧屏（待定）：占位，追番周表 / 排行榜等功能随产品裁定补充。
class AnimeScreen extends StatelessWidget {
  const AnimeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        AppLocalizations.of(context).animePending,
        style: const TextStyle(fontSize: 13, color: AppTokens.textSecondary),
      ),
    );
  }
}
