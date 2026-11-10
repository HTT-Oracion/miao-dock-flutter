import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miao_dock_flutter/app/app.dart';
import 'package:miao_dock_flutter/app/router/routes.dart';
import 'package:miao_dock_flutter/features/manga/online/controller/online_reader_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_image_loader.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_repository.dart';
import 'package:miao_dock_flutter/features/manga/online/ui/widgets/online_common.dart';
import 'package:miao_dock_flutter/features/manga/online/ui/widgets/online_page_image.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_mobile.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_stage.dart';

import 'fake_engine.dart';
import 'fake_image_loader.dart';
import 'test_store.dart';

Future<void> pump([int steps = 6]) async {
  for (var i = 0; i < steps; i++) {
    // ignore: invalid_use_of_visible_for_testing_member
    await TestWidgetsFlutterBinding.instance.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets('移动端阅读器：隐藏工具栏时点击/滑动直接翻页且页面尽量铺满', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
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
    await tester.tap(find.byType(OnlineBookCard).first);
    await pump(8);
    await tester.tap(find.text('开始阅读').first);
    await pump(14);
    expect(container.read(onlineReaderProvider), isNotNull);
    expect(find.byType(ReaderStage), findsOneWidget);
    final notifier = container.read(onlineReaderProvider.notifier);
    notifier.setControlsVisible(true);
    await pump(1);
    // 在线阅读器必须使用漫画库同一套移动端工具栏。
    expect(find.byType(ReaderTopBar), findsOneWidget);
    expect(find.byType(ReaderBottomBar), findsOneWidget);
    notifier.setControlsVisible(false);
    await pump(2);
    final beforeTap = container.read(onlineReaderProvider)!.page;
    await tester.tapAt(const Offset(350, 430));
    await pump(6);
    final afterTap = container.read(onlineReaderProvider)!;
    expect(afterTap.page, beforeTap + 1);
    expect(afterTap.controlsVisible, isFalse);

    final beforeSwipe = afterTap.page;
    await tester.dragFrom(const Offset(320, 430), const Offset(-220, 0));
    await pump(8);
    final afterSwipe = container.read(onlineReaderProvider)!;
    expect(afterSwipe.page, beforeSwipe + 1);
    expect(afterSwipe.controlsVisible, isFalse);

    final pageFinder = find.byType(OnlinePageImage);
    expect(pageFinder, findsOneWidget);
    expect(find.descendant(of: pageFinder, matching: find.text('原文')), findsNothing);
    expect(find.descendant(of: pageFinder, matching: find.text('译文')), findsNothing);
    final size = tester.getSize(pageFinder);
    expect(size.width, closeTo(390, 1));
    expect(size.height, greaterThan(700));
    expect(tester.takeException(), isNull);
  });
}
