import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/app/app.dart';
import 'package:miao_dock_flutter/app/router/routes.dart';
import 'package:miao_dock_flutter/features/manga/online/controller/online_reader_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/controller/online_sources_controller.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_image_loader.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_repository.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_download.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_source.dart';
import 'package:miao_dock_flutter/features/manga/online/ui/widgets/online_common.dart';
import 'package:miao_dock_flutter/features/manga/online/ui/widgets/online_reader_widgets.dart';

import 'fake_engine.dart';
import 'fake_image_loader.dart';
import 'test_data.dart';
import 'test_store.dart';

Future<void> pump([int steps = 8]) async {
  for (var i = 0; i < steps; i++) {
    // ignore: invalid_use_of_visible_for_testing_member
    await TestWidgetsFlutterBinding.instance.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets('未配置源语言：隐藏翻译入口、翻译条与 T 快捷键；配置后恢复', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    final base = OnlineTestData.seedSources(DateTime.now()).first;
    final noLanguage = OnlineSource(manifest: base.manifest, capabilities: base.capabilities, consecutiveFailures: 0);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineStoreProvider.overrideWithValue(MemoryStore(sources: [noLanguage])),
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
    expect(find.text('下载并翻译'), findsNothing);
    await tester.tap(find.text('开始阅读').first);
    await pump(14);
    var reader = container.read(onlineReaderProvider)!;
    expect(reader.translationEnabled, isFalse);
    expect(find.byType(OnlineTranslationBar), findsNothing);
    expect(find.text('显示翻译'), findsNothing);
    // 设置常驻，且未配置语言时只有漫画库阅读设置，不出现翻译区块。
    await tester.tap(find.byIcon(LucideIcons.settings).last);
    await pump(3);
    expect(find.text('阅读模式'), findsOneWidget);
    expect(find.text('范围'), findsNothing);
    await tester.tap(find.byIcon(LucideIcons.x).last);
    await pump(2);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await pump(2);
    reader = container.read(onlineReaderProvider)!;
    expect(reader.translation.state, TranslationState.idle);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pump(6);
    container.read(onlineSourcesProvider.notifier).setLanguage(base.id, 'ja');
    await pump(4);
    expect(find.text('下载并翻译'), findsOneWidget);
    await tester.tap(find.text('开始阅读').first);
    await pump(14);
    reader = container.read(onlineReaderProvider)!;
    expect(reader.translationEnabled, isTrue);
    expect(find.byType(OnlineTranslationBar), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.settings).last);
    await pump(3);
    expect(find.text('阅读模式'), findsOneWidget);
    expect(find.text('范围'), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.x).last);
    await pump(2);
  });
  testWidgets('已导入源可通过菜单编辑源语言', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    final base = OnlineTestData.seedSources(DateTime.now()).first;
    final noLanguage = OnlineSource(manifest: base.manifest, capabilities: base.capabilities);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineStoreProvider.overrideWithValue(MemoryStore(sources: [noLanguage])),
          sourceEngineProvider.overrideWithValue(FakeSourceEngine()),
          onlineImageLoaderProvider.overrideWithValue(FakeImageLoader()),
        ],
        child: const MiaoDockApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final context = tester.element(find.byType(MiaoDockApp));
    final container = ProviderScope.containerOf(context, listen: false);
    container.read(routerProvider).go('/settings?section=online');
    await pump(10);
    await tester.tap(find.byIcon(LucideIcons.moreHorizontal).first);
    await pump(3);
    await tester.tap(find.text('编辑源语言'));
    await pump(3);
    expect(find.textContaining('源语言 ·'), findsOneWidget);
    await tester.tap(find.text('日文'));
    await pump(1);
    await tester.tap(find.text('保存'));
    await pump(4);
    expect(container.read(onlineSourcesProvider).value!.first.sourceLanguage, 'ja');
    await pump(12);
  });
}
