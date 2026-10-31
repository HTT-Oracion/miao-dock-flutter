import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miao_dock_flutter/features/manga/domain/not_ready_state.dart';

import 'package:miao_dock_flutter/features/settings/ui/settings_screen.dart';
import 'package:miao_dock_flutter/shared/widgets/app_select.dart';
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

  testWidgets('默认进入「通用」，四项齐备', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const SettingsScreen()));
    await tester.pumpAndSettle();

    // 破坏点：默认落在翻译服务 → 与设计稿「通用」为首项不符，本条失败。
    expect(find.text('深色模式'), findsOneWidget);
    expect(find.text('关闭窗口行为'), findsOneWidget);
    expect(find.text('规格自检'), findsOneWidget);
    expect(find.text('侧栏图标标签'), findsOneWidget);
  });

  testWidgets('翻译服务组展示（含三层卡片要素）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('翻译服务'));
    await tester.pumpAndSettle();

    // 破坏点：三层缺一层 → 用户看不到「服务常驻」的关键事实，本条失败。
    expect(find.text('漫画服务'), findsOneWidget);
    // L1+L2 在卡片里是拼接文案「引擎 + 大模型 · 本地翻译」
    expect(find.textContaining('引擎 + 大模型'), findsWidgets);

    // 来源改用 `.select` 下拉（设计稿 §设置）：收起只显示当前值，展开是三选一。
    // 按类型点：来源会被持久化，上次跑的用例可能已把它改成别的值，
    // 按文案找会不稳定（实测在整包跑时红）。
    await tester.tap(find.byType(AppSelect<TranslateSource>));
    await tester.pumpAndSettle();
    // 破坏点：下拉里缺选项 → 用户改不了来源，本条失败。
    expect(find.text('大模型翻译'), findsWidgets);
    expect(find.text('远程翻译'), findsWidgets);
    await tester.tap(find.text('大模型翻译').last);
    await tester.pumpAndSettle();
    expect(find.text('大模型翻译'), findsWidgets);

    // 引擎未启动时的主操作是「启动」
    expect(find.text('启动'), findsWidgets);
  });

  testWidgets('分组导航切换后显示占位分组', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('翻译服务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通用'));
    await tester.pumpAndSettle();

    // 破坏点：切分组后内容区不换 → 导航是假的，本条失败。
    expect(find.text('翻译链路'), findsNothing);
  });
}
