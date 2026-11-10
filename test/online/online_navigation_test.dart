import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/app/app.dart';
import 'package:miao_dock_flutter/app/router/routes.dart';
import 'package:miao_dock_flutter/app/shell/mobile_nav.dart';
import 'package:miao_dock_flutter/features/manga/online/controller/online_reader_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_image_loader.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_repository.dart';
import 'package:miao_dock_flutter/features/manga/online/ui/widgets/online_common.dart';
import 'package:miao_dock_flutter/features/manga/online/ui/widgets/online_shelf.dart';

import 'fake_engine.dart';
import 'fake_image_loader.dart';
import 'test_store.dart';

Future<ProviderContainer> pumpApp(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        onlineStoreProvider.overrideWithValue(MemoryStore()),
        sourceEngineProvider.overrideWithValue(FakeSourceEngine()),
        onlineImageLoaderProvider.overrideWithValue(FakeImageLoader()),
      ],
      child: const MiaoDockApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  final context = tester.element(find.byType(MiaoDockApp));
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(routerProvider).go('/manga/online');
  await pump(8);
  if (find.text('我已了解').evaluate().isNotEmpty) {
    await tester.tap(find.text('我已了解'));
    await pump(4);
  }
  return container;
}

Future<void> pump([int steps = 6]) async {
  for (var i = 0; i < steps; i++) {
    // ignore: invalid_use_of_visible_for_testing_member
    await TestWidgetsFlutterBinding.instance.pump(const Duration(milliseconds: 250));
  }
}

String currentPath(ProviderContainer container) =>
    container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets('桌面：在线是第 4 视图，浏览→详情→阅读器→返回详情', (tester) async {
    final container = await pumpApp(tester, const Size(1440, 900));

    // 破坏点：mangaViews 漏掉 online 时，侧栏/顶栏不会有第 4 个视图，内容也不会加载。
    expect(find.byType(OnlineShelf), findsOneWidget);
    expect(find.text('最近更新'), findsOneWidget);
    expect(find.byType(OnlineBookCard), findsWidgets);

    await tester.tap(find.byType(OnlineBookCard).first);
    await pump(10);
    expect(currentPath(container), '/manga/online/detail/manhuagui/kimetsu');
    expect(find.text('开始阅读'), findsWidgets);
    expect(find.text('下载并翻译'), findsWidgets);

    await tester.tap(find.text('第206话 决战之后').first);
    await pump(12);
    expect(currentPath(container), '/manga/online/reader');
    expect(find.text('翻译本话'), findsWidgets);
    expect(find.text('原文'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await pump(4);
    expect(find.text('2 / 26'), findsWidgets);

    await tester.tap(find.byTooltip('关闭（Esc）').first);
    await pump(8);
    // 阅读器从详情打开，关闭后回详情（设计稿 §阅读进度）。
    expect(currentPath(container), '/manga/online/detail/manhuagui/kimetsu');
    expect(find.text('开始阅读'), findsWidgets);
  });

  testWidgets('桌面：分类 / 搜索 / 最近 / 下载 / 源管理均可达', (tester) async {
    final container = await pumpApp(tester, const Size(1440, 900));

    await tester.tap(find.descendant(of: find.byType(OnlineShelf), matching: find.text('分类')));
    await pump(10);
    expect(find.textContaining('category('), findsWidgets);
    expect(find.text('热血'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, '海贼');
    await pump(10);
    expect(find.text('「海贼」· 漫画柜'), findsWidgets);
    expect(find.text('海贼王'), findsWidgets);

    await tester.tap(find.descendant(of: find.byType(OnlineShelf), matching: find.text('最近阅读')).first);
    await pump(8);
    expect(find.text('继续阅读'), findsWidgets);
    expect(find.text('鬼灭之刃'), findsWidgets);

    await tester.tap(find.descendant(of: find.byType(OnlineShelf), matching: find.text('下载')).first);
    await pump(8);
    expect(find.text('下载中'), findsWidgets);
    expect(find.text('部分成功'), findsWidgets);

    container.read(routerProvider).go('/settings?section=online');
    await pump(10);
    expect(find.text('漫画源'), findsWidgets);
    expect(find.text('已导入的源'), findsWidgets);
    expect(find.text('导入源…'), findsOneWidget);
  });

  testWidgets('移动端 390×844：无侧栏、详情滑层、阅读器整屏', (tester) async {
    final container = await pumpApp(tester, const Size(390, 844));

    // 破坏点：宽屏书架漏到窄屏 → 这条抓 RenderFlex overflow / OnlineShelf 仍然存在。
    expect(tester.takeException(), isNull);
    expect(find.byType(OnlineShelf), findsNothing);
    expect(find.text('漫画源'), findsNothing);
    expect(find.byType(OnlineBookCard), findsWidgets);

    await tester.tap(find.byType(OnlineBookCard).first);
    await pump(10);
    expect(tester.takeException(), isNull);
    expect(currentPath(container), '/manga/online/detail/manhuagui/kimetsu');
    expect(find.text('漫画详情'), findsWidgets);

    await tester.tap(find.text('开始阅读').first);
    await pump(12);
    expect(currentPath(container), '/manga/online/reader');
    expect(tester.takeException(), isNull);
    expect(find.byType(MobileBottomNav), findsNothing);
    expect(find.text('翻译本话'), findsWidgets);
    expect(find.text('章节'), findsWidgets);

    container.read(onlineReaderProvider.notifier).setControlsVisible(false);
    await pump(1);
    await tester.tapAt(const Offset(195, 420));
    // 隐式 slide 动画在测试里需要多个 pump 才落到终值；真机上约 150ms。
    await pump(6);
    await tester.tap(find.text('设置').first);
    await pump(8);
    // 移动端设置/章节/翻译入口都走同一套底部 sheet；内容标题可区分。
    expect(find.text('翻译设置'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
