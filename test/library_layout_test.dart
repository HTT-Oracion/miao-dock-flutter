import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// D-098：漫画库两态布局（ver1.0）。
///
/// - 默认：左栏 + 网格**同时**存在；
/// - 选中某本：左栏**消失**，出现「返回书架」；
/// - 进库**不自动选中第一本**。
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mangaSvcClientProvider.overrideWithValue(_Client())],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('进库不选中第一本：显示网格，无「返回书架」', (tester) async {
    await pump(tester);
    // 破坏点：兜底 books.first → 直接进详情，网格看不到。
    expect(find.text('返回书架'), findsNothing);
    // 左栏 + 网格各一处。
    expect(find.text('某书'), findsAtLeastNWidgets(2));
  });

  testWidgets('默认态：左栏与网格同时存在', (tester) async {
    await pump(tester);
    // 左栏一项 + 网格一张卡。
    expect(find.text('某书'), findsAtLeastNWidgets(2));
  });

  testWidgets('选中某本：左栏消失并出现返回书架', (tester) async {
    await pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));
    container.read(selectedBookProvider.notifier).select('某书');
    await tester.pumpAndSettle();
    expect(find.text('返回书架'), findsOneWidget);
    // 返回后回到默认态。
    container.read(selectedBookProvider.notifier).select(null);
    await tester.pumpAndSettle();
    expect(find.text('返回书架'), findsNothing);
  });
}

class _Client extends FakeMangaSvcClient {
  @override
  Future<List<int>?> getBookCover(String bookName) async => null;

  @override
  Future<LibraryResponse> listLibrary() async => LibraryResponse(
    root: '/tmp',
    count: 1,
    totalImages: 4,
    totalBytes: 100,
    comics: const [],
    books: [
      const BookEntry(
        bookName: '某书',
        dirName: '某书',
        outputDir: '/tmp/某书',
        title: '某书',
        author: '作者',
        chapterCount: 1,
        totalPages: 2,
        byteSize: 50,
        chapters: [],
      ),
    ],
    others: const [],
    hidden: const [],
    hiddenCount: 0,
    updatedAt: DateTime(2026, 1, 1),
  );
}
