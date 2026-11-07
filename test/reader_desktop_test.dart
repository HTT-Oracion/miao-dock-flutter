import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/app/app.dart';
import 'package:miao_dock_flutter/app/router/routes.dart';
import 'package:miao_dock_flutter/app/shell/app_shell.dart';
import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/core/window/window_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/reader_focus.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_prefs.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_widgets.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/app_sheet.dart';
import 'package:miao_dock_flutter/shared/widgets/nav_rail.dart';
import 'package:protocol/protocol.dart';

/// 桌面阅读器（重设计稿 desktop.html side 面板，D-173）：
/// O 键 / RTL 镜像 / 长按连发 / ? 速查卡 / G 网格角标 / 对照点侧 / 底部提示条 /
/// 未放大时把滚动交回 PageView（鼠标拖拽跟手翻页）。
void main() {
  const session = ReaderSession(key: '某书', chapterNo: 1, pages: 4, translated: {});

  test('专注模式顶部让位：只有「macOS 且未真全屏」才让红绿灯带', () {
    // 真全屏时系统标题栏 / 红绿灯都隐藏，让位必须为 0（否则顶部多一条空白）。
    expect(readerFocusTopInset(macos: true, fullscreen: true), 0);
    expect(readerFocusTopInset(macos: false, fullscreen: true), 0);
    // 全屏失败退化成普通窗口：macOS 红绿灯会压顶栏，必须让；Windows 不需要。
    expect(readerFocusTopInset(macos: true, fullscreen: false), AppMetrics.macTrafficLightBand);
    expect(readerFocusTopInset(macos: false, fullscreen: false), 0);
  });

  Future<ProviderContainer> pumpReader(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // 阅读器根节点是 autofocus 的 Focus，键盘事件直接可达（不要点屏幕：
    // 桌面单击图片 = 隐藏工具栏，会把底栏提示条一起收走）。
    return container;
  }

  testWidgets('O 键切换原图 / 译文（按钮文案跟着翻）', (tester) async {
    await pumpReader(tester);
    expect(find.text('显示原图'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.pumpAndSettle();
    // 破坏点：O 没绑 → 文案还是「显示原图」（等于只能点按钮）。
    expect(find.text('显示翻译'), findsOneWidget);
    expect(find.text('显示原图'), findsNothing);
  });

  testWidgets('RTL 时方向键镜像：右方向键 = 上一页', (tester) async {
    final container = await pumpReader(tester);
    container.read(readerPrefsProvider.notifier).toggleRtl();
    container.read(readerPageProvider.notifier).set(2);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    // 破坏点：方向键不镜像 → RTL 下按右键反而前进到第 4 页。
    expect(container.read(readerPageProvider), 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(container.read(readerPageProvider), 2);
  });

  testWidgets('按住方向键可连发（KeyRepeat 也算）', (tester) async {
    final container = await pumpReader(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(container.read(readerPageProvider), 1);

    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    // 破坏点：只处理 KeyDownEvent → 按住不放只翻一页。
    expect(container.read(readerPageProvider), 2);
  });

  testWidgets('全屏态下 Esc 只退全屏，不关阅读器', (tester) async {
    await pumpReader(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    // 破坏点：Esc 不看全屏态 → 第一次 Esc 就把阅读器关了。
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.byType(ReaderBar), findsOneWidget);
  });

  testWidgets('专注模式：F 之后壳层消失（只显示阅读器），Esc 还壳', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(overrides: [mangaSvcClientProvider.overrideWithValue(_StubClient())], child: const MiaoDockApp()),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final router = container.read(routerProvider);
    container
        .read(readerSessionProvider.notifier)
        .open(const ReaderSession(key: '某书', chapterNo: 1, pages: 3, translated: {}));
    router.go('/manga/reader');
    await tester.pump();
    await tester.pump();
    expect(find.byType(NavRail), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    // 破坏点：只调系统全屏、不隐藏壳层 → 侧栏还在，阅读器没独占窗口。
    expect(find.byType(NavRail), findsNothing);
    expect(find.byType(ReaderScreen), findsOneWidget);

    // 测试环境没有窗口管理器：`setFullScreen` 不生效 → 退化成「未全屏」，
    // 顶部按平台让位。破坏点：直接 `body: shell` → macOS 阅读器顶栏顶到 y=0，
    // 被原生红绿灯压住（Windows / Linux 让位为 0，不渲染这条带子）。
    final inset = readerFocusTopInset(macos: isMacosPlatform, fullscreen: false);
    if (inset > 0) {
      expect(find.byKey(const Key('reader-focus-inset')), findsOneWidget);
      expect(tester.getTopLeft(find.byType(ReaderBar)).dy, greaterThanOrEqualTo(inset - 0.5));
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(NavRail), findsOneWidget);
  });

  testWidgets('切到别的模块后快捷键不在后台生效（保活分支不吃按键）', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(overrides: [mangaSvcClientProvider.overrideWithValue(_StubClient())], child: const MiaoDockApp()),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final router = container.read(routerProvider);
    container.read(readerSessionProvider.notifier).open(session);
    router.go('/manga/reader');
    await tester.pump();
    await tester.pump();
    expect(find.byType(ReaderScreen), findsOneWidget);

    // 切到设置页：阅读器所在分支被 IndexedStack 保活（offstage + TickerMode 关），
    // 但它的 `ModalRoute.isCurrent` 依然是 true。
    router.go('/settings');
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    // 破坏点：只判 `isCurrent` → 在设置页敲 G 会把后台的网格打开，
    // 而设置页里的字母键（输入地址 / 令牌）也会被吃掉。
    expect(find.byType(GridCell, skipOffstage: false), findsNothing);
  });

  testWidgets('专注模式走「应用级全屏」：调 setFullScreen，不是 maximize', (tester) async {
    final calls = <String>[];
    var fullscreen = false;
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'setFullScreen':
          fullscreen = (call.arguments as Map)['isFullScreen'] as bool;
          return null;
        case 'isFullScreen':
          return fullscreen;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(overrides: [mangaSvcClientProvider.overrideWithValue(_StubClient())], child: const MiaoDockApp()),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final router = container.read(routerProvider);
    container.read(readerSessionProvider.notifier).open(session);
    router.go('/manga/reader');
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    // 破坏点：还调 maximize（macOS 的 `zoom:`）→ 只是变大、不隐藏菜单栏，
    // 用户看到的就是「没全屏」。
    expect(calls, contains('setFullScreen'));
    expect(calls, isNot(contains('maximize')));
    expect(container.read(readerFullscreenProvider), isTrue);

    // 真全屏后系统标题栏 / 红绿灯都隐藏：不能再留 28px 让位带。
    expect(find.byKey(const Key('reader-focus-inset')), findsNothing);

    // 用户从窗口标题栏 / 绿色按钮退出全屏：专注模式还在（壳层仍隐藏），
    // 但窗口不是全屏了 —— 必须重新给红绿灯让位。
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('onEvent', {'eventName': 'leave-full-screen'})),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(container.read(readerFullscreenProvider), isFalse);
    final inset = readerFocusTopInset(macos: isMacosPlatform, fullscreen: false);
    if (inset > 0) {
      expect(find.byKey(const Key('reader-focus-inset')), findsOneWidget);
      expect(tester.getTopLeft(find.byType(ReaderBar)).dy, greaterThanOrEqualTo(inset - 0.5));
    }
  });

  testWidgets('? 呼出快捷键速查卡，Esc 关掉', (tester) async {
    await pumpReader(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('键盘快捷键'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    // 破坏点：Esc 不看层级 → 直接把阅读器关了。
    expect(find.text('键盘快捷键'), findsNothing);
    expect(find.byType(ReaderBar), findsOneWidget);
  });

  testWidgets('设置抽屉在宽屏从右侧滑入（贴右、380 宽）；窄屏仍贴底', (tester) async {
    await pumpReader(tester);
    await tester.tap(find.byIcon(LucideIcons.settings));
    await tester.pumpAndSettle();
    expect(find.text('阅读设置'), findsOneWidget);
    final rect = tester.getRect(find.byType(AppSheet));
    // 破坏点：宽屏还用贴底弹层 → 底部一条 1440 宽的面板，离鼠标很远。
    expect(rect.right, closeTo(1200, 1));
    expect(rect.width, closeTo(380, 1));
    expect(rect.height, closeTo(800, 1));
  });

  testWidgets('G 网格总览给当前页打「当前」角标', (tester) async {
    await pumpReader(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    // 破坏点：网格只剩描边没有角标 → 大图里分不清哪张是当前页。
    expect(find.text('当前'), findsOneWidget);
  });

  testWidgets('对照里点图翻页，且不退出对照（右 30% 下一页 / 左 30% 上一页）', (tester) async {
    final container = await pumpReader(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.byType(ComparePane), findsNWidgets(2));

    final stage = tester.getRect(find.byType(ReaderScreen));
    // 右 30%：下一页。
    await tester.tapAt(Offset(stage.width * 0.85, stage.center.dy));
    await tester.pumpAndSettle();
    expect(container.read(readerPageProvider), 1);
    // 破坏点：点图仍按旧口径退出对照 → 两栏消失（用户想接着对比下一页就断了）。
    expect(find.byType(ComparePane), findsNWidgets(2));

    // 左 30%：上一页。
    await tester.tapAt(Offset(stage.width * 0.1, stage.center.dy));
    await tester.pumpAndSettle();
    expect(container.read(readerPageProvider), 0);
    expect(find.byType(ComparePane), findsNWidgets(2));
  });

  testWidgets('对照模式里能翻页，翻完仍在对照；退出对照停在同一页', (tester) async {
    final container = await pumpReader(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.byType(ComparePane), findsNWidgets(2));

    // 破坏点：`_go` 直接 `_controller.jumpToPage()` —— 对照模式里没有 PageView，
    // controller 没有 client，翻页直接失效（用户看到的「对照时翻不动」）。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(container.read(readerPageProvider), 1);
    // 破坏点：翻页顺手把 `_compare` 复位 → 下一页变成单页。
    expect(find.byType(ComparePane), findsNWidgets(2));

    // 连续翻：确认不是只翻得动一次。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(container.read(readerPageProvider), 2);
    expect(find.byType(ComparePane), findsNWidgets(2));

    // 退出对照：PageView 重新挂载后必须还在第 3 页，不能回到第 1 页。
    // （点图不再退出对照，退出走 C 键 / 顶栏按钮。）
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.byType(ComparePane), findsNothing);
    final page = tester.widget<PageView>(find.byType(PageView)).controller!.page;
    expect(page?.round(), 2);
  });

  testWidgets('焦点不在阅读器时快捷键照样生效（不依赖 autofocus）', (tester) async {
    await pumpReader(tester);
    // 真机上「打开/关闭抽屉」「点顶栏按钮」「切模块回来」都会把焦点带走；
    // 这里直接把焦点扔回根 scope，复现最坏情况。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    // 破坏点：只靠 Focus.onKeyEvent → 焦点一丢，G / C / O / F 全部没反应。
    expect(find.text('当前'), findsOneWidget);
  });

  testWidgets('对照里点「显示原图 / 显示翻译」= 退出对照并显示该侧', (tester) async {
    await pumpReader(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.byType(ComparePane), findsNWidgets(2));

    // 偏好可能被前面的用例写过，用按钮文案反推当前侧：
    // 文案说「显示原图」→ 点完应当只显示原图，反之亦然。
    final wantsOriginal = find.text('显示原图').evaluate().isNotEmpty;
    await tester.tap(find.text(wantsOriginal ? '显示原图' : '显示翻译'));
    await tester.pumpAndSettle();

    // 破坏点：只切原图/译文、不退对照 → 两栏还在（用户点了像没反应）。
    expect(find.byType(ComparePane), findsNothing);
    expect(find.text(wantsOriginal ? '显示翻译' : '显示原图'), findsOneWidget);
  });

  testWidgets('底部提示条常驻（工具栏可见时）', (tester) async {
    await pumpReader(tester);
    expect(find.text('←→ 翻页 · Ctrl+滚轮 缩放 · G 网格 · C 对照 · ? 快捷键'), findsOneWidget);
  });

  testWidgets('对照模式保留左右翻页热区，且触控板横扫能翻页', (tester) async {
    final container = await pumpReader(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.byType(ComparePane), findsNWidgets(2));

    // 破坏点：对照走独立 Row → 两侧 56px 热区整层丢失（用户「翻页按钮不见了」）。
    expect(find.byKey(const Key('reader-hotzone-prev')), findsOneWidget);
    expect(find.byKey(const Key('reader-hotzone-next')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-hotzone-next')));
    await tester.pumpAndSettle();
    expect(container.read(readerPageProvider), 1);
    expect(find.byType(ComparePane), findsNWidgets(2));

    // 破坏点：对照里横扫没人接（没有 PageView）→ 停在 1。
    final g = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await g.panZoomStart(const Offset(600, 400));
    for (var i = 0; i < 6; i++) {
      await g.panZoomUpdate(const Offset(600, 400), pan: Offset(-70.0 * (i + 1), 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.panZoomEnd();
    await tester.pumpAndSettle();
    expect(container.read(readerPageProvider), 2);
    expect(find.byType(ComparePane), findsNWidgets(2));
    // 翻页后的预载是 200ms 定时器，跑完再收尾，否则报 pending timer。
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('macOS 触控板横扫翻页（PointerPanZoom，不是滚轮）', (tester) async {
    final container = await pumpReader(tester);
    final g = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await g.panZoomStart(const Offset(600, 400));
    // `pan` 是**累计值**（panDelta 由框架算），要一路累加；过 1200 的一半才吸附。
    for (var i = 0; i < 14; i++) {
      await g.panZoomUpdate(const Offset(600, 400), pan: Offset(-70.0 * (i + 1), 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.panZoomEnd();
    await tester.pumpAndSettle();
    // 破坏点：页面层还挂着 onScale* → 它先吃掉 pan-zoom，PageView 收不到 → 停在 0。
    expect(container.read(readerPageProvider), 1);
  });

  testWidgets('触控板捏合缩放（scale 变化的 pan-zoom）', (tester) async {
    final container = await pumpReader(tester);
    final g = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await g.panZoomStart(const Offset(600, 400));
    await g.panZoomUpdate(const Offset(600, 400), scale: 1.3);
    await tester.pump(const Duration(milliseconds: 16));
    await g.panZoomEnd();
    await tester.pumpAndSettle();
    // 缩放器在舞台层接住了捏合：125% 起（+25% 一档的调节器不参与）。
    expect(container.read(readerPageProvider), 0);
    expect(find.textContaining('%'), findsWidgets);
    final zoomed = tester.widget<PageView>(find.byType(PageView)).physics;
    expect(zoomed, isA<NeverScrollableScrollPhysics>());
  });

  testWidgets('未放大把滚动交回 PageView（拖拽跟手）；放大态收回', (tester) async {
    final container = await pumpReader(tester);
    // 破坏点：桌面永远 NeverScrollable → 鼠标横向拖拽翻页重新失效（D-168 同款问题）。
    expect(tester.widget<PageView>(find.byType(PageView)).physics, isA<PageScrollPhysics>());

    container.read(readerPrefsProvider.notifier).setNight(ReaderNight.off); // 无关，只为触发重建
    await tester.pump();
    // 放大 25% × 2 = 150%
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pumpAndSettle();
    expect(tester.widget<PageView>(find.byType(PageView)).physics, isA<NeverScrollableScrollPhysics>());
  });
}

class _StubClient extends FakeMangaSvcClient {
  @override
  Future<List<int>> getChapterFile(String bookName, double chapterNo, int seq, {bool translated = false}) async =>
      Uint8List(0);

  @override
  Future<List<int>> getBookFile(String bookName, int seq, {bool translated = false}) async => Uint8List(0);
}
