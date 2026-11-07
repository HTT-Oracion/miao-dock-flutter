import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/domain/lib_book.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_detail.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// 点「第 N 页」进阅读器必须落在第 N 页（D-172）。
///
/// 这类断言的坑：`open()` 的语义是「换话 = 从头读」，会把页码归零，
/// 所以入口必须 **先 open 再设页码**；顺序反了或干脆没设，就会回到第 1 页。
void main() {
  LibBook bookWithChapter({required int pages}) => LibBook(
    key: '某书',
    name: '某书',
    author: '',
    totalBytes: 1,
    chapters: [LibChapter(no: 1, pageCount: pages, donePages: 0, dirName: 'c1', translatedSeqs: const {})],
  );

  LibBook single({required int pages}) =>
      LibBook(key: '单话', name: '单话', author: '', totalBytes: 1, isBook: false, directPages: pages, chapters: const []);

  Future<(ProviderContainer, GoRouter)> pumpDetail(WidgetTester tester, {required LibBook book}) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        mangaSvcClientProvider.overrideWithValue(_StubClient()),
        libraryProvider.overrideWith(_FakeLibrary.new),
      ],
    );
    addTearDown(container.dispose);
    // 选中这本书（等价于点书架行），详情/页网格才会渲染。
    container.read(selectedBookProvider.notifier).select(book.key);

    final router = GoRouter(
      initialLocation: '/manga/library',
      routes: [
        GoRoute(
          path: '/manga/library',
          builder: (_, _) => const Scaffold(body: LibraryDetail()),
        ),
        GoRoute(
          path: '/manga/reader',
          builder: (_, _) => const Scaffold(body: Text('reader-view')),
        ),
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
    return (container, router);
  }

  testWidgets('单本某话：点第 3 页 → 阅读器停在第 3 页', (tester) async {
    final book = bookWithChapter(pages: 4);
    final (container, router) = await pumpDetail(tester, book: book);
    // 打开该话的页网格（桌面：话卡点进去就是这一层）。
    container.read(libChapterOpenProvider.notifier).open(1);
    await tester.pumpAndSettle();

    await tester.tap(find.text('第 3 页'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/manga/reader');
    // 破坏点：入口只 open 不设页码 → 这里读到 0（第 1 页）。
    expect(container.read(readerPageProvider), 2);
    expect(container.read(readerSessionProvider)!.chapterNo, 1);
  });

  testWidgets('未归并单话：点第 2 页 → 阅读器停在第 2 页', (tester) async {
    final (container, router) = await pumpDetail(tester, book: single(pages: 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第 2 页'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/manga/reader');
    expect(container.read(readerPageProvider), 1);
    expect(container.read(readerSessionProvider)!.pages, 4);
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
      chapters: [LibChapter(no: 1, pageCount: 4, donePages: 0, dirName: 'c1', translatedSeqs: const {})],
    ),
    LibBook(key: '单话', name: '单话', author: '', totalBytes: 1, isBook: false, directPages: 4, chapters: const []),
  ];
}

class _StubClient extends FakeMangaSvcClient {
  @override
  Future<List<int>> getChapterFile(String bookName, double chapterNo, int seq, {bool translated = false}) async =>
      Uint8List(0);

  @override
  Future<List<int>> getBookFile(String bookName, int seq, {bool translated = false}) async => Uint8List(0);

  @override
  Future<List<int>?> getBookCover(String bookName) async => null;
}
