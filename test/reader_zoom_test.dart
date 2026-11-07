import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_widgets.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_zoom.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// D-164：桌面阅读器缩放（调节器 / 触控板捏合 / 翻页归位）+ 触摸板横滑翻页
/// + 去掉「点图直接放大」。
void main() {
  group('ReaderZoom 纯逻辑', () {
    test('调节器 25% 一档，50–200% 夹紧', () {
      final zoom = ReaderZoom()..viewport = const Size(400, 400);
      expect(zoom.percent, 100);
      zoom.step(-1);
      expect(zoom.percent, 75);
      for (var i = 0; i < 5; i++) {
        zoom.step(-1);
      }
      // 破坏点：不夹紧 → 会掉到 25%/0%（设计稿 50% 下限）。
      expect(zoom.percent, 50);
      expect(zoom.atMin, isTrue);
      for (var i = 0; i < 10; i++) {
        zoom.step(1);
      }
      expect(zoom.percent, 200);
      expect(zoom.atMax, isTrue);
    });

    test('翻页归位：reset 回 100% 且位移清零', () {
      final zoom = ReaderZoom()..viewport = const Size(400, 400);
      zoom.step(2); // 150%
      zoom.panBy(const Offset(30, 20));
      zoom.reset();
      // 破坏点：只清 scale 不清 offset → 下一页仍带着上一页的偏移。
      expect(zoom.percent, 100);
      expect(zoom.offset, Offset.zero);
    });

    test('锚点缩放：光标下的点不动（o′ = a − (a − o)·k）', () {
      final zoom = ReaderZoom()..viewport = const Size(400, 400);
      // 舞台中心 (200,200)；光标在 (300,200) ⇒ a = (100,0)。
      zoom.scaleAt(const Offset(300, 200), 2);
      expect(zoom.percent, 200);
      // 该点缩放前后屏幕位置一致：off + a·s == a ⇒ off = a − a·s = (100,0) − (200,0)。
      expect(zoom.offset, const Offset(-100, 0));
    });

    test('放大态平移被舞台尺寸夹住', () {
      final zoom = ReaderZoom()..viewport = const Size(400, 400);
      zoom.scaleAt(const Offset(200, 200), 2);
      zoom.panBy(const Offset(1000, 1000));
      // 2 倍时最多溢出半屏（200）。
      expect(zoom.offset, const Offset(200, 200));
    });

    test('缩到 100% 以下时位移归零（不留黑边外的偏移）', () {
      final zoom = ReaderZoom()..viewport = const Size(400, 400);
      zoom.scaleAt(const Offset(120, 160), 2);
      zoom.scaleAt(const Offset(120, 160), 0.5);
      expect(zoom.percent, 100);
      expect(zoom.offset, Offset.zero);
    });
  });

  group('桌面阅读器', () {
    const session = ReaderSession(key: '某书', chapterNo: 1, pages: 3, translated: {});

    /// 只认顶栏调节器里的百分比：缩放 OSD 也写同一串字，全局 find.text 会匹配到两个。
    Finder chipText(String percent) => find.descendant(of: find.byType(ReaderBar), matching: find.text(percent));

    Future<void> pumpReader(WidgetTester tester, {Size size = const Size(1200, 800)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [mangaSvcClientProvider.overrideWithValue(_StubClient())]);
      addTearDown(container.dispose);
      container.read(readerSessionProvider.notifier).open(session);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ReaderScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('顶栏调节器：点＋到 125%，翻页后归位 100%', (tester) async {
      await pumpReader(tester);
      expect(chipText('100%'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      expect(chipText('125%'), findsOneWidget);

      // 点右侧 56px 热区翻页 —— 破坏点：翻页不归位 → 第 2 页仍显示 125%。
      final size = tester.getSize(find.byType(ReaderScreen));
      await tester.tapAt(Offset(size.width - 20, size.height / 2));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(chipText('100%'), findsOneWidget);
    });

    testWidgets('触控板捏合放大（两指张开）改百分比', (tester) async {
      await pumpReader(tester);
      final center = tester.getCenter(find.byType(PageView));

      final a = await tester.startGesture(center - const Offset(40, 0), pointer: 1);
      final b = await tester.startGesture(center + const Offset(40, 0), pointer: 2);
      await a.moveBy(const Offset(-70, 0));
      await b.moveBy(const Offset(70, 0));
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      // 破坏点：舞台不接 scale 手势 → 捏合毫无反应，永远 100%。
      expect(chipText('100%'), findsNothing);
    });

    testWidgets('触摸板横滑（无 ctrl）翻页', (tester) async {
      await pumpReader(tester);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(tester.getCenter(find.byType(PageView))));
      await tester.sendEventToBinding(pointer.scroll(const Offset(40, 0)));
      await tester.pumpAndSettle();

      // 破坏点：不接 PointerSignal → 触摸板横滑什么也不发生（用户报的就是这条）。
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('Ctrl+滚轮缩放，且不翻页', (tester) async {
      await pumpReader(tester);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(tester.getCenter(find.byType(PageView))));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(chipText('100%'), findsNothing);
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('点图不再放大（双击仍是 100%）', (tester) async {
      await pumpReader(tester);
      final center = tester.getCenter(find.byType(PageView));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 90));
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      // 破坏点：恢复「双击 100%⇄200%」→ 这里读到 200%。
      expect(chipText('100%'), findsOneWidget);
    });
  });
}

class _StubClient extends FakeMangaSvcClient {
  @override
  Future<List<int>> getChapterFile(String bookName, double chapterNo, int seq, {bool translated = false}) async =>
      Uint8List(0);

  @override
  Future<List<int>> getBookFile(String bookName, int seq, {bool translated = false}) async => Uint8List(0);
}
