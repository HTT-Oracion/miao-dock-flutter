import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/domain/lib_book.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_mobile_stage.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_widgets.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// 章末衔接卡（D-169）：
///   · 必须能关掉（× 或点遮罩），关掉后还停在阅读器；
///   · 「回目录」要回**这本书的章节列表**（不是空书架）；
///   · 未归并单话没有目录层级，文案与去向都是「回书架」。
void main() {
  const bookKey = '某书';

  ProviderContainer newContainer(ReaderSession session) {
    final container = ProviderContainer(
      overrides: [
        mangaSvcClientProvider.overrideWithValue(_StubClient()),
        libraryProvider.overrideWith(_FakeLibrary.new),
      ],
    );
    container.read(readerSessionProvider.notifier).open(session);
    return container;
  }

  Future<(ProviderContainer, GoRouter)> pump(WidgetTester tester, ReaderSession session) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = newContainer(session);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/manga/reader',
      routes: [
        GoRoute(
          path: '/manga/reader',
          builder: (_, _) => const Scaffold(body: ReaderScreen()),
        ),
        GoRoute(path: '/manga/library', builder: (_, _) => const Text('library-view')),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 250));
    return (container, router);
  }

  /// 末页继续往外拖 → 出章末卡。
  Future<void> pullEndCard(WidgetTester tester) async {
    await tester.drag(find.byType(MobileReaderStage), const Offset(-160, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('点 × 关掉章末卡，仍停在阅读器', (tester) async {
    final (container, router) = await pump(
      tester,
      const ReaderSession(key: bookKey, chapterNo: 2, pages: 1, translated: {}),
    );
    await pullEndCard(tester);
    expect(find.byType(ReaderEndCard), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(ReaderEndCard), matching: find.byIcon(LucideIcons.x)));
    await tester.pumpAndSettle();
    // 破坏点：卡上没 × → 除了「回目录」没有别的出路，用户被卡在末页。
    expect(find.byType(ReaderEndCard), findsNothing);
    expect(router.state.uri.path, '/manga/reader');
    expect(container.read(readerSessionProvider), isNotNull);
  });

  testWidgets('点遮罩也关得掉', (tester) async {
    await pump(tester, const ReaderSession(key: bookKey, chapterNo: 2, pages: 1, translated: {}));
    await pullEndCard(tester);
    expect(find.byType(ReaderEndCard), findsOneWidget);

    // 卡片最大宽 280、居中：左侧 20px 处一定是遮罩。
    await tester.tapAt(const Offset(20, 420));
    await tester.pumpAndSettle();
    // 破坏点：遮罩不可点 → 只能点按钮。
    expect(find.byType(ReaderEndCard), findsNothing);
  });

  testWidgets('回目录 = 回这本书的章节列表（选中该书）', (tester) async {
    final (container, router) = await pump(
      tester,
      const ReaderSession(key: bookKey, chapterNo: 2, pages: 1, translated: {}),
    );
    await pullEndCard(tester);
    expect(find.text('回目录'), findsOneWidget);

    await tester.tap(find.text('回目录'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/manga/library');
    // 破坏点：只 go 到漫画库不选中书 → 落在空态/别的书上，不是「目录」。
    expect(container.read(selectedBookProvider), bookKey);
    expect(container.read(readerSessionProvider), isNull);
  });

  testWidgets('单本最后一话：主按钮回书架、副按钮回目录（两颗不同文案）', (tester) async {
    await pump(tester, const ReaderSession(key: bookKey, chapterNo: 2, pages: 1, translated: {}));
    await pullEndCard(tester);
    // 没有下一话 → 主按钮「回书架」；这本书有目录 → 副按钮「回目录」。
    expect(find.text('回书架'), findsOneWidget);
    expect(find.text('回目录'), findsOneWidget);
    expect(find.text('本话已读完'), findsOneWidget);
  });

  testWidgets('未归并单话：文案是回书架，点完清掉选中落在书架', (tester) async {
    final (container, router) = await pump(tester, const ReaderSession(key: '单话', pages: 1, translated: {}));
    // 先制造一个「之前选中过别的书」的状态。
    container.read(selectedBookProvider.notifier).select(bookKey);
    await pullEndCard(tester);

    expect(find.text('本话已读完'), findsOneWidget);
    // 破坏点：单话也显示「回目录」→ 点进去是单话自己的详情，不是目录。
    expect(find.text('回目录'), findsNothing);
    // 破坏点：主/副按钮都算出「回书架」→ 同屏两个一模一样的按钮。
    expect(find.text('回书架'), findsOneWidget);

    await tester.tap(find.text('回书架'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/manga/library');
    expect(container.read(selectedBookProvider), isNull);
    expect(container.read(readerSessionProvider), isNull);
  });
}

class _FakeLibrary extends LibraryNotifier {
  @override
  Future<List<LibBook>> build() async => [
    LibBook(
      key: '某书',
      name: '某书',
      author: '',
      totalBytes: 1,
      chapters: const [
        LibChapter(no: 1, pageCount: 1, donePages: 0, dirName: 'c1', translatedSeqs: {}),
        LibChapter(no: 2, pageCount: 1, donePages: 0, dirName: 'c2', translatedSeqs: {}),
      ],
    ),
    LibBook(key: '单话', name: '单话', author: '', totalBytes: 1, isBook: false, directPages: 1, chapters: const []),
  ];
}

class _StubClient extends FakeMangaSvcClient {
  @override
  Future<List<int>> getChapterFile(String bookName, double chapterNo, int seq, {bool translated = false}) async =>
      Uint8List(0);

  @override
  Future<List<int>> getBookFile(String bookName, int seq, {bool translated = false}) async => Uint8List(0);
}
