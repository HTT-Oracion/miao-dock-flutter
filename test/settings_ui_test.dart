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
    // 文案改为「侧栏展开」：与侧栏的收起/展开按钮是同一状态。
    expect(find.text('侧栏展开'), findsOneWidget);
  });

  testWidgets('翻译服务组展示（含三层卡片要素）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('翻译服务'));
    await tester.pumpAndSettle();

    // 三层状态条已按要求移除（用户要求删掉 _LayerRow 那段）；
    // 现在「模型」区在首部，含启动按钮与引擎目录。
    expect(find.text('模型'), findsWidgets);
    expect(find.text('启动'), findsWidgets);

    // 来源改用 `.select` 下拉（设计稿 §设置）：收起只显示当前值，展开是三选一。
    // 按类型点：来源会被持久化，上次跑的用例可能已把它改成别的值，
    // 按文案找会不稳定（实测在整包跑时红）。
    await tester.tap(find.byType(AppSelect<TranslateSource>));
    await tester.pumpAndSettle();
    // 【大模型翻译】暂时隐藏（llmSourceEnabled = false），只剩本地 / 远程。
    // 破坏点：仍在列表里 → 用户会选到一个未开放的能力。
    expect(find.text('大模型翻译'), findsNothing);
    expect(find.text('远程翻译'), findsWidgets);
    expect(find.text('本地翻译'), findsWidgets);
    await tester.tap(find.text('远程翻译').last);
    await tester.pumpAndSettle();
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

    await tester.tap(find.text('翻译服务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通用'));
    await tester.pumpAndSettle();

    // 破坏点：切分组后内容区不换 → 导航是假的，本条失败。
    expect(find.text('翻译链路'), findsNothing);
  });
}
