import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/ui/drop_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/buttons.dart';

void main() {
  testWidgets('桌面投放提交与清空同一行，尺寸对齐远程校验按钮', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: DropScreen()),
        ),
      ),
    );
    await tester.pump();

    final submitFinder = find.widgetWithText(AppButton, '提交');
    final clearFinder = find.widgetWithText(AppButton, '清空');
    final submit = tester.widget<AppButton>(submitFinder);
    final clear = tester.widget<AppButton>(clearFinder);

    // 重设计稿双栏布局：提交/清空在右列同一行（高度 36 对齐门禁主按钮）。
    expect(tester.getCenter(submitFinder).dy, tester.getCenter(clearFinder).dy);
    for (final button in [submit, clear]) {
      expect(button.height, 36);
      expect(button.fontSize, AppFont.px12_5);
    }
  });
}
