import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/settings/ui/settings_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// P0-F5 设置页断言。
void main() {
  Widget host(Widget child) => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  testWidgets('翻译服务组默认展示（含三层卡片要素）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const SettingsScreen()));
    await tester.pumpAndSettle();

    // 破坏点：三层缺一层 → 用户看不到「服务常驻」的关键事实，本条失败。
    expect(find.text('漫画服务'), findsOneWidget);
    // L1+L2 在卡片里是拼接文案「引擎 + 大模型 · 本地翻译」
    expect(find.textContaining('引擎 + 大模型'), findsWidgets);

    // 来源三选一
    expect(find.text('本地翻译'), findsWidgets);
    expect(find.text('大模型翻译'), findsWidgets);
    expect(find.text('远程翻译'), findsWidgets);

    // 引擎未启动时的主操作是「启动」
    expect(find.text('启动'), findsWidgets);
  });

  testWidgets('分组导航切换后显示占位分组', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('通用'));
    await tester.pumpAndSettle();

    // 破坏点：切分组后内容区不换 → 导航是假的，本条失败。
    expect(find.text('翻译链路'), findsNothing);
  });
}
