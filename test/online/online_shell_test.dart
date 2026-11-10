import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/app/app.dart';
import 'package:miao_dock_flutter/app/router/routes.dart';
import 'package:miao_dock_flutter/app/shell/shell_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/controller/online_reader_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_image_loader.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_repository.dart';
import 'package:miao_dock_flutter/features/manga/online/ui/widgets/online_common.dart';
import 'package:miao_dock_flutter/features/manga/ui/manga_gate.dart';

import 'fake_engine.dart';
import 'fake_image_loader.dart';
import 'test_store.dart';

Future<void> pump([int steps = 8]) async {
  for (var i = 0; i < steps; i++) {
    // ignore: invalid_use_of_visible_for_testing_member
    await TestWidgetsFlutterBinding.instance.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  test('online 是漫画第 4 视图；在线阅读器路径按阅读器处理', () {
    // 破坏点：mangaViews 漏掉 online / isReaderPath 不并列判断 online reader。
    expect(mangaViews.map((v) => v.id), contains('online'));
    expect(resolveViewId('online', mangaViews), 'online');
    expect(isReaderPath('/manga/online/reader'), isTrue);
    expect(isReaderPath('/manga/reader'), isTrue);
    expect(gateBypassedFor('/manga/online'), isTrue);
    expect(gateBypassedFor('/manga/online/detail/manhuagui/kimetsu'), isTrue);
  });

  testWidgets('移动端阅读器 3s 自动隐藏工具栏，点中央恢复', (tester) async {
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
    final reader = container.read(onlineReaderProvider);
    expect(reader, isNotNull);
    // 先确定性地把工具栏隐藏，再点击中央显示；这样 3s 自动隐藏从点击时重新计时。
    container.read(onlineReaderProvider.notifier).setControlsVisible(false);
    await pump(1);
    await tester.tapAt(const Offset(195, 420));
    await pump(3);
    expect(container.read(onlineReaderProvider)!.controlsVisible, isTrue);

    await pump(14);
    // 破坏点：去掉自动隐藏定时器后，这里仍为 true。
    expect(container.read(onlineReaderProvider)!.controlsVisible, isFalse);

    await tester.tapAt(const Offset(195, 420));
    await pump(2);
    expect(container.read(onlineReaderProvider)!.controlsVisible, isTrue);
  });
}
