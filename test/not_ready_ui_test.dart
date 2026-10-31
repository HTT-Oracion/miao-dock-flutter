import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/manga/domain/not_ready_state.dart';
import 'package:miao_dock_flutter/features/manga/ui/notready/not_ready_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/log_box.dart';

/// 启动引导 UI 断言（D-012 / D-013）。
void main() {
  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  NotReadyView viewOf(NotReadyState state, {List<String> logs = const []}) => NotReadyView(
    state: state,
    engine: switch (state) {
      NotReadyState.starting => EngineRuntimeState.starting,
      NotReadyState.failed => EngineRuntimeState.failed,
      NotReadyState.installed => EngineRuntimeState.off,
      _ => EngineRuntimeState.off,
    },
    source: TranslateSource.local,
    logs: logs,
  );

  Widget screen(NotReadyState state, {List<String> logs = const []}) => NotReadyScreen(
    view: viewOf(state, logs: logs),
    onPrimary: () {},
    onSecondary: () {},
    onRetryService: () {},
  );

  testWidgets('未装配态显示下载主操作', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(screen(NotReadyState.uninstalled)));
    await tester.pumpAndSettle();

    // 破坏点：未装配态给了「启动引擎」→ 用户点了必然失败，本条失败。
    expect(find.text('下载引擎与模型'), findsOneWidget);
    expect(find.text('翻译引擎还没有装配'), findsOneWidget);
  });

  testWidgets('引导卡不出现「先去设置看看 / 设置」次级按钮', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 破坏点：卡片里多出设置类按钮 → 与设计稿不符且分散主操作，本条失败。
    // （这条是补的：此前删除只改了代码，没有断言拦住，回归过一次。）
    for (final st in [NotReadyState.uninstalled, NotReadyState.installed, NotReadyState.failed]) {
      await tester.pumpWidget(host(screen(st)));
      await tester.pumpAndSettle();
      expect(find.text('先去设置看看'), findsNothing, reason: '$st 不应有「先去设置看看」');
      expect(find.text('设置'), findsNothing, reason: '$st 不应有「设置」');
    }
  });

  testWidgets('已装未启动态显示启动主操作', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(screen(NotReadyState.installed)));
    await tester.pumpAndSettle();

    expect(find.text('引擎已就绪，尚未启动'), findsOneWidget);
    expect(find.text('启动引擎'), findsWidgets);
  });

  testWidgets('失败态给「重新下载模型」而不是「重启」', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(screen(NotReadyState.failed, logs: const ['[engine] exited 1'])));
    await tester.pumpAndSettle();

    // 破坏点：失败态只给「重试启动」→ 引擎运行时坏了重启无用，本条失败。
    expect(find.text('重试启动'), findsOneWidget);
    expect(find.text('重新下载模型'), findsOneWidget);
  });

  testWidgets('三层状态条始终存在（服务 / 引擎+大模型 / 来源）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(screen(NotReadyState.installed)));
    await tester.pumpAndSettle();

    // 破坏点：漏掉任一层 → 用户看不到「服务常驻」这个关键事实，本条失败。
    expect(find.text('漫画服务'), findsOneWidget);
    expect(find.text('引擎 + 大模型'), findsOneWidget);
    expect(find.text('翻译来源'), findsOneWidget);
    expect(find.text('本地翻译'), findsOneWidget);
  });

  testWidgets('移除「稍后再说」（会造成死循环）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    for (final st in NotReadyState.values) {
      await tester.pumpWidget(host(screen(st)));
      await tester.pumpAndSettle();
      // 破坏点：加回「稍后再说」→ 点它会跳向同样需要引擎的队列，本条失败。
      expect(find.text('稍后再说'), findsNothing, reason: '$st 不应有稍后再说');
    }
  });

  group('LogBox', () {
    testWidgets('hover 才显示复制 / 导出按钮', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const LogBox(lines: ['a', 'b'])));
      await tester.pumpAndSettle();

      // 破坏点：常驻按钮 → 会抢内容区注意力（D-013 明确要 hover 浮出）。
      final opacityWidget = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
      expect(opacityWidget.opacity, 0);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(LogBox)));
      await tester.pumpAndSettle();

      final after = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
      expect(after.opacity, 1);
    });

    testWidgets('空态单独绘制，不留空框', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const LogBox(lines: [])));
      await tester.pumpAndSettle();

      // 破坏点：空日志画成空黑框 → 用户以为组件坏了，本条失败。
      expect(find.text('还没有日志输出'), findsOneWidget);
      expect(find.byType(AnimatedOpacity), findsNothing);
    });

    testWidgets('错误行被高亮（只染色不删行）', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const LogBox(lines: ['[engine] loading', '[engine] exited with code 1'])));
      await tester.pumpAndSettle();

      // 两行都在（不删行）
      expect(find.byType(SelectableText), findsOneWidget);
      final rich = tester.widget<SelectableText>(find.byType(SelectableText));
      final spans = rich.textSpan!.children!.cast<TextSpan>();
      expect(spans.length, 2);
      // 破坏点：错误行不染色 → 排障时扫不到重点，本条失败。
      expect(spans[1].style!.color, isNot(spans[0].style!.color));
    });
  });
}
