import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/app/app.dart';
import 'package:miao_dock_flutter/app/router/routes.dart';
import 'package:miao_dock_flutter/app/shell/mobile_nav.dart';
import 'package:miao_dock_flutter/features/manga/online/controller/online_browse_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/controller/online_reader_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_image_loader.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_repository.dart';
import 'package:miao_dock_flutter/features/manga/online/ui/widgets/online_common.dart';
import 'package:miao_dock_flutter/features/manga/online/ui/widgets/online_shelf.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_paged_stage.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_zoom.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_widgets.dart';

import 'fake_engine.dart';
import 'fake_image_loader.dart';
import 'test_store.dart';

Future<ProviderContainer> pumpApp(WidgetTester tester, Size size, {FakeSourceEngine? engine}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        onlineStoreProvider.overrideWithValue(MemoryStore()),
        sourceEngineProvider.overrideWithValue(engine ?? FakeSourceEngine()),
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
    final refresh = find.text('换一批');
    final firstHeader = find.byType(OnlineSectionHeader).first;
    expect(refresh, findsOneWidget);
    expect(tester.getRect(refresh).right, closeTo(tester.getRect(firstHeader).right, 1));

    await tester.tap(find.byType(OnlineBookCard).first);
    await pump(10);
    expect(currentPath(container), '/manga/online/detail/manhuagui/kimetsu');
    expect(find.text('开始阅读'), findsWidgets);
    expect(find.text('下载并翻译'), findsWidgets);
    expect(find.text('吾峠呼世晴 · 235 话'), findsOneWidget);
    expect(find.text('更新 2026-11-10'), findsOneWidget);

    await tester.tap(find.text('第206话 决战之后').first);
    await pump(12);
    expect(currentPath(container), '/manga/online/reader');
    expect(find.byType(ReaderBar), findsOneWidget);
    expect(find.byType(PagedReaderStage), findsOneWidget);
    expect(find.byType(ZoomChip), findsOneWidget);
    expect(find.text('翻译本话'), findsWidgets);
    expect(find.text('显示翻译'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await pump(4);
    expect(find.text('2 / 26'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pump(8);
    // 阅读器从详情打开，关闭后回详情（设计稿 §阅读进度）。
    expect(currentPath(container), '/manga/online/detail/manhuagui/kimetsu');
    expect(find.text('开始阅读'), findsWidgets);

    // 主「开始阅读」按钮也必须进入阅读器（不能只有章节行可点）。
    await tester.tap(find.text('开始阅读').first);
    await pump(12);
    expect(currentPath(container), '/manga/online/reader');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pump(8);

    // 详情内切换「分类」应离开详情路由，而不是被详情 body 卡住。
    await tester.tap(find.descendant(of: find.byType(OnlineShelf), matching: find.text('分类')));
    await pump(10);
    expect(currentPath(container), '/manga/online');
    expect(find.text('热血'), findsWidgets);
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
    // 设置抽屉与漫画库共用；可翻译源额外带翻译区块。
    expect(find.text('阅读设置'), findsWidgets);
    expect(find.text('阅读模式'), findsWidgets);
    expect(find.text('范围'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('桌面：排行入口、日周月总 tabs 与 No 角标', (tester) async {
    final container = await pumpApp(tester, const Size(1440, 900));
    await tester.tap(find.descendant(of: find.byType(OnlineShelf), matching: find.text('排行')));
    await pump(10);
    expect(find.text('日排行'), findsOneWidget);
    expect(find.text('周排行'), findsOneWidget);
    expect(find.text('月排行'), findsOneWidget);
    expect(find.text('总排行'), findsOneWidget);
    // tabs 上方不再有「排行榜 / 漫画柜」标题栏。
    expect(find.text('排行榜'), findsNothing);
    expect(find.text('No.1'), findsOneWidget);
    expect(find.text('No.6'), findsOneWidget);
    await tester.tap(find.text('周排行'));
    await pump(8);
    expect(container.read(onlineNavProvider).view, OnlineView.ranking);
  });
  testWidgets('桌面：切换排行 tab 时 tabs 保持可见，加载态只在下方', (tester) async {
    await pumpApp(tester, const Size(1440, 900), engine: FakeSourceEngine(delay: const Duration(milliseconds: 300)));
    await tester.tap(find.descendant(of: find.byType(OnlineShelf), matching: find.text('排行')));
    await pump(8);
    expect(find.text('日排行'), findsOneWidget);

    await tester.tap(find.text('周排行'));
    await tester.pump();
    expect(find.text('日排行'), findsOneWidget);
    expect(find.text('周排行'), findsOneWidget);
    expect(find.text('月排行'), findsOneWidget);
    expect(find.text('总排行'), findsOneWidget);
    expect(find.byType(OnlineGridSkeleton), findsOneWidget);

    await pump(4);
    expect(find.byType(OnlineGridSkeleton), findsNothing);
  });
  testWidgets('桌面：首次进入排行先显示 tabs，列表区域单独加载', (tester) async {
    await pumpApp(tester, const Size(1440, 900), engine: FakeSourceEngine(rankPageDelay: const Duration(seconds: 1)));
    await tester.tap(find.descendant(of: find.byType(OnlineShelf), matching: find.text('排行')));
    await pump(2);
    expect(find.text('日排行'), findsOneWidget);
    expect(find.text('周排行'), findsOneWidget);
    expect(find.byType(OnlineGridSkeleton), findsOneWidget);
    await pump(4);
    expect(find.byType(OnlineGridSkeleton), findsNothing);
    expect(find.text('No.1'), findsOneWidget);
  });
}
