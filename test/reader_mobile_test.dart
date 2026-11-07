import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/domain/lib_book.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_image_cache.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_mobile.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_widgets.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_mobile_stage.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_prefs.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// 移动端阅读器（重设计稿 mobile.html，D-166）：
/// 双击 2.5× / 长按放大镜 / 放大态不翻页 / 跟手拖拽翻页 / 底栏滑条 /
/// 章末衔接卡 / 未翻译角标 / 亮度边缘 / 点按分区提示。
void main() {
  const session = ReaderSession(key: '某书', chapterNo: 1, pages: 3, translated: {});

  // 页图缓存是进程级的：用例之间必须清，否则「上一条用例的字节」会让断言假通过。
  setUp(ReaderImageCache.clear);
  tearDown(ReaderImageCache.clear);

  ProviderContainer newContainer({List<LibBook>? books, MangaSvcClient? client}) {
    final container = ProviderContainer(
      overrides: [
        mangaSvcClientProvider.overrideWithValue(client ?? _StubClient()),
        if (books != null) libraryProvider.overrideWith(_FakeLibrary.new),
      ],
    );
    container.read(readerSessionProvider.notifier).open(session);
    return container;
  }

  Future<ProviderContainer> pumpReader(WidgetTester tester, {List<LibBook>? books, MangaSvcClient? client}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = newContainer(books: books, client: client);
    addTearDown(container.dispose);
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
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    // 首帧预热排了一个 200ms 定时器：这里放它跑完，免得用例收尾报 pending timer。
    await tester.pump(const Duration(milliseconds: 250));
    return container;
  }

  /// 分步滑动：真机一次滑动是「几十帧、每帧几像素」，
  /// `tester.drag` 一次吐整段位移会把「没累加」的 bug 藏起来。
  Future<void> swipe(WidgetTester tester, {required double dx, int steps = 12}) async {
    final g = await tester.startGesture(const Offset(195, 420));
    for (var i = 0; i < steps; i++) {
      await g.moveBy(Offset(dx / steps, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  /// 推几帧：`AnimationController` 的第一帧只用来定起点，value 还是 0。
  Future<void> pumpFrames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
  }

  /// 双击（两次点按间隔 60ms，落在 230ms 的双击窗口内）。
  ///
  /// 之后要连推三帧：ticker 的第一帧只用来定起点，值还是 0。
  Future<void> doubleTap(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 160));
  }

  double zoomScale(WidgetTester tester) {
    final t = tester.widget<Transform>(find.byKey(const Key('reader-zoom')));
    return t.transform.getMaxScaleOnAxis();
  }

  Finder barPageText(String text) => find.descendant(of: find.byType(ReaderBottomBar), matching: find.text(text));

  testWidgets('双击放大到 250%，再双击还原 100%', (tester) async {
    await pumpReader(tester);
    expect(zoomScale(tester), closeTo(1, 0.01));

    await doubleTap(tester, const Offset(195, 420));
    // 破坏点：双击不接 → 仍是 100%。
    expect(zoomScale(tester), closeTo(2.5, 0.01));

    await doubleTap(tester, const Offset(195, 420));
    expect(zoomScale(tester), closeTo(1, 0.01));
  });

  testWidgets('长按 250ms 出放大镜，抬手消失', (tester) async {
    await pumpReader(tester);
    final g = await tester.startGesture(const Offset(195, 420));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const Key('reader-loupe')), findsNothing);
    await tester.pump(const Duration(milliseconds: 180));
    // 破坏点：长按不判定 → 放大镜永不出现。
    expect(find.byKey(const Key('reader-loupe')), findsOneWidget);
    await g.up();
    await tester.pump();
    expect(find.byKey(const Key('reader-loupe')), findsNothing);
  });

  testWidgets('放大态点按不翻页；还原后点按才翻页', (tester) async {
    final container = await pumpReader(tester);
    await doubleTap(tester, const Offset(195, 420));
    expect(zoomScale(tester), closeTo(2.5, 0.01));

    // 右侧 30% 点按：放大态下只呼出工具栏，不翻页。
    await tester.tapAt(const Offset(350, 420));
    await tester.pump(const Duration(milliseconds: 300));
    // 破坏点：放大态仍按点按翻页 → 平移时会连翻页。
    expect(container.read(readerPageProvider), 0);

    await doubleTap(tester, const Offset(195, 420));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(350, 420));
    // 点按翻页有 240ms 收尾动画（默认「推挤」），推够帧才提交。
    await pumpFrames(tester);
    expect(container.read(readerPageProvider), 1);
    // 预载的 200ms 定时器要跑完，否则用例收尾时报 pending timer。
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('左滑翻下一页、右滑回上一页（分步滑动，跟真手指一致）', (tester) async {
    final container = await pumpReader(tester);
    // 破坏点：位移不累加（每帧只有 18px）→ 松手回弹，停在 1 / 3。
    await swipe(tester, dx: -220);
    expect(barPageText('2 / 3'), findsOneWidget);
    expect(container.read(readerPageProvider), 1);

    await swipe(tester, dx: 220);
    // 破坏点：只有左滑接、右滑不接 → 停在 2 / 3。
    expect(barPageText('1 / 3'), findsOneWidget);
    expect(container.read(readerPageProvider), 0);
  });

  testWidgets('滑一点点（不足 28%）回弹不翻页', (tester) async {
    final container = await pumpReader(tester);
    await swipe(tester, dx: -60, steps: 6);
    expect(container.read(readerPageProvider), 0);
    expect(barPageText('1 / 3'), findsOneWidget);
  });

  testWidgets('末页继续往后拖 → 章末衔接卡', (tester) async {
    final container = ProviderContainer(overrides: [mangaSvcClientProvider.overrideWithValue(_StubClient())]);
    addTearDown(container.dispose);
    container
        .read(readerSessionProvider.notifier)
        .open(const ReaderSession(key: '某书', chapterNo: 1, pages: 1, translated: {}));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    await tester.pump(const Duration(milliseconds: 250));
    await tester.drag(find.byType(MobileReaderStage), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(find.text('本话已读完'), findsOneWidget);
  });

  testWidgets('点按翻页有动画：中途两页并存，落位后才改页码', (tester) async {
    final container = await pumpReader(tester);
    await tester.tapAt(const Offset(350, 420));
    // 单击要等 230ms 双击窗口过去才执行，然后才是 240ms 收尾动画。
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 破坏点：默认「无动画」直接换页 → 这里只有一页，页码也已经变了。
    expect(find.byType(ReaderPage), findsNWidgets(2));
    expect(container.read(readerPageProvider), 0);
    await pumpFrames(tester);
    expect(container.read(readerPageProvider), 1);
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('回到看过的页不再闪加载圈（页图缓存）', (tester) async {
    // 故意让接口慢 200ms：没有缓存的话，新页挂载那一帧必然只有加载圈。
    final container = await pumpReader(tester, client: _SlowClient());
    await pumpFrames(tester, 3);
    // 第 1 页取过就把字节留在缓存里（预载同理）。
    expect(ReaderImageCache.length, greaterThan(0));

    await tester.tapAt(const Offset(350, 420));
    await pumpFrames(tester, 8);
    expect(container.read(readerPageProvider), 1);

    // 翻回第 1 页：缓存命中，新页挂载的那一帧就该出图。
    await tester.tapAt(const Offset(40, 420));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(container.read(readerPageProvider), 0);
    // 破坏点：ReaderPage 不查缓存 → 这一帧只有 ReaderSpinner（用户看到的「闪一下」）。
    expect(find.byType(ReaderSpinner), findsNothing);
    expect(find.byType(ReaderPageImage), findsWidgets);
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('未翻译页显示角标（缺译文回退原图）', (tester) async {
    await pumpReader(tester);
    // 破坏点：把回退当错误态 → 角标文案消失或变红字。
    expect(find.text('未翻译 · 正在显示原图'), findsOneWidget);
  });

  testWidgets('底栏滑条跳页', (tester) async {
    final container = await pumpReader(tester);
    final rect = tester.getRect(find.byType(PageSlider));
    await tester.tapAt(Offset(rect.right - 4, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 50));
    // 破坏点：滑条只画不接 → 页码不动。
    expect(container.read(readerPageProvider), 2);
    expect(barPageText('3 / 3'), findsOneWidget);
  });

  testWidgets('底栏上一话/下一话：按书架章节可点，单话直读时禁用', (tester) async {
    final books = [
      _book(chapters: const [1, 2, 3]),
    ];
    final container = await pumpReader(tester, books: books);
    expect(find.text('下一话'), findsOneWidget);
    await tester.tap(find.text('下一话'));
    await tester.pump(const Duration(milliseconds: 50));
    // 换话 = 新会话（第 2 话）。
    expect(container.read(readerSessionProvider)!.chapterNo, 2);
  });

  testWidgets('章节抽屉：当前话高亮，点选换话', (tester) async {
    final books = [
      _book(chapters: const [1, 2, 3]),
    ];
    final container = await pumpReader(tester, books: books);
    await tester.tap(find.text('章节'));
    await tester.pumpAndSettle();
    expect(find.text('章节目录'), findsOneWidget);
    // 破坏点：抽屉不接库数据 → 只剩标题。
    expect(find.text('第 3 话'), findsOneWidget);
    await tester.tap(find.text('第 3 话'));
    await tester.pumpAndSettle();
    expect(container.read(readerSessionProvider)!.chapterNo, 3);
  });

  testWidgets('左缘竖滑调亮度（并出 OSD）', (tester) async {
    final container = await pumpReader(tester);
    final before = container.read(readerPrefsProvider).brightness;
    final g = await tester.startGesture(const Offset(10, 400));
    await g.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 50));
    await g.up();
    await tester.pump(const Duration(milliseconds: 50));
    // 破坏点：边缘手势不接 → 亮度不变。
    expect(container.read(readerPrefsProvider).brightness, lessThan(before));
    expect(find.byType(BrightOsd), findsOneWidget);
  });

  testWidgets('首次进入展示点按分区 2s', (tester) async {
    resetReaderTapHint();
    await pumpReader(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('呼出工具栏'), findsOneWidget);
    // 破坏点：提示不自动消失 → 永远糊在画面上。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('呼出工具栏'), findsNothing);
  });

  testWidgets('关掉「显示页码」后翻页不再弹页码气泡', (tester) async {
    final container = await pumpReader(tester);
    container.read(readerPrefsProvider.notifier).togglePageNum();
    await tester.tapAt(const Offset(350, 420));
    await pumpFrames(tester);
    // 页码照常前进，但 OSD 里不该冒出页码。
    expect(container.read(readerPageProvider), 1);
    expect(find.descendant(of: find.byType(ReaderOsd), matching: find.text('2 / 3')), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('夜间三档真的上滤镜（强度可调），关掉就没有', (tester) async {
    final container = await pumpReader(tester);
    expect(find.byType(NightTint), findsNothing);

    container.read(readerPrefsProvider.notifier).setNight(ReaderNight.warm);
    await tester.pump();
    // 破坏点：设置改了但舞台没包滤镜 → 这里找不到 NightTint（用户看到「切了没反应」）。
    var tint = tester.widget<NightTint>(find.byType(NightTint));
    expect(tint.desaturate, isFalse);
    expect(tint.color.a, closeTo(0.25 * 0.4, 0.02));

    // 强度拉满 → 同一档更浓。
    container.read(readerPrefsProvider.notifier).setNightIntensity(1);
    await tester.pump();
    tint = tester.widget<NightTint>(find.byType(NightTint));
    expect(tint.color.a, greaterThan(0.2));

    // 纯黑档要降饱和。
    container.read(readerPrefsProvider.notifier).setNight(ReaderNight.black);
    await tester.pump();
    expect(tester.widget<NightTint>(find.byType(NightTint)).desaturate, isTrue);

    container.read(readerPrefsProvider.notifier).setNight(ReaderNight.off);
    await tester.pump();
    expect(find.byType(NightTint), findsNothing);
  });

  testWidgets('没有目录时章节动作置灰（点不出抽屉）', (tester) async {
    // 未归并单话：chapterNo == null，书架里也没有话层级。
    final container = ProviderContainer(overrides: [mangaSvcClientProvider.overrideWithValue(_StubClient())]);
    addTearDown(container.dispose);
    container.read(readerSessionProvider.notifier).open(const ReaderSession(key: '单话', pages: 3, translated: {}));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    await tester.pump(const Duration(milliseconds: 250));
    // 破坏点：动作仍然挂 onTap 却静默 return → 用户以为按钮坏了；
    // 这里直接钉住「没有目录 = onTap 为 null（置灰）」。
    final action = tester.widget<InkWell>(find.ancestor(of: find.text('章节'), matching: find.byType(InkWell)).first);
    expect(action.onTap, isNull);

    await tester.tap(find.text('章节'));
    await tester.pumpAndSettle();
    expect(find.text('章节目录'), findsNothing);
  });

  testWidgets('设置抽屉：点按翻页 / 翻页动画等新行都在', (tester) async {
    await pumpReader(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('阅读设置'), findsOneWidget);
    expect(find.text('翻页动画'), findsOneWidget);
    expect(find.text('点按翻页'), findsOneWidget);
    expect(find.text('夜间强度'), findsOneWidget);
    expect(find.text('舞台背景'), findsOneWidget);
    expect(find.text('预载页数'), findsOneWidget);
  });
}

LibBook _book({required List<double> chapters}) => LibBook(
  key: '某书',
  name: '某书',
  author: '',
  totalBytes: 1,
  chapters: [
    for (final no in chapters)
      LibChapter(no: no, pageCount: 3, donePages: 0, dirName: 'c$no', translatedSeqs: const {}),
  ],
);

class _FakeLibrary extends LibraryNotifier {
  @override
  Future<List<LibBook>> build() async => [
    _book(chapters: const [1, 2, 3]),
  ];
}

/// 1×1 透明 PNG：缓存用例要真字节，空字节不会进缓存。
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// 慢 200ms 的取图客户端：缓存用例靠它把「没缓存 = 一定有加载圈」变成确定事实。
class _SlowClient extends _PngClient {
  @override
  Future<List<int>> getChapterFile(String bookName, double chapterNo, int seq, {bool translated = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return _pngBytes;
  }

  @override
  Future<List<int>> getBookFile(String bookName, int seq, {bool translated = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return _pngBytes;
  }
}

class _PngClient extends _StubClient {
  @override
  Future<List<int>> getChapterFile(String bookName, double chapterNo, int seq, {bool translated = false}) async =>
      _pngBytes;

  @override
  Future<List<int>> getBookFile(String bookName, int seq, {bool translated = false}) async => _pngBytes;
}

class _StubClient extends FakeMangaSvcClient {
  @override
  Future<List<int>> getChapterFile(String bookName, double chapterNo, int seq, {bool translated = false}) async =>
      Uint8List(0);

  @override
  Future<List<int>> getBookFile(String bookName, int seq, {bool translated = false}) async => Uint8List(0);
}
