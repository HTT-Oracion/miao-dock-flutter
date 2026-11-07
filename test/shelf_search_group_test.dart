import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_shelf.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// D-103：左栏搜索分组（miao-dock `groupSearchResults`）。
///
/// - 浏览态：平铺（单本 + 未归并单话）；
/// - 搜索态：**每本书一组**，**未归并单话单独成组，排最后**。
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mangaSvcClientProvider.overrideWithValue(_C())],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox(width: 260, child: LibraryShelf())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('浏览态：未归并归入「其他 · 未归并」组', (tester) async {
    await pump(tester);
    expect(find.text('其他 · 未归并'), findsOneWidget);
  });

  testWidgets('搜索态：书架平铺过滤（设计稿 renderShelf，不再按书分组）', (tester) async {
    await pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(LibraryShelf)));
    container.read(shelfQueryProvider.notifier).set('书甲');
    await tester.pumpAndSettle();

    // 设计稿：书架搜索 = 行内过滤 + 命中高亮；分组聚合在右栏搜索结果页。
    expect(find.text('书甲'), findsOneWidget);
    // 未归并单话名不含「书甲」→ 整组不出现（组头随组走）。
    expect(find.text('其他 · 未归并'), findsNothing);
    expect(find.byKey(const ValueKey('shelf-row-未归并书乙')), findsNothing);
  });

  testWidgets('搜索态：单话命中时未归并组仍在最后', (tester) async {
    await pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(LibraryShelf)));
    container.read(shelfQueryProvider.notifier).set('未归并');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('shelf-row-未归并书乙')), findsOneWidget);
    expect(find.text('其他 · 未归并'), findsOneWidget);
  });
}

class _C extends FakeMangaSvcClient {
  @override
  Future<List<int>?> getBookCover(String n) async => null;

  @override
  Future<LibraryResponse> listLibrary() async => LibraryResponse(
    root: '/tmp',
    count: 1,
    totalImages: 3,
    totalBytes: 10,
    comics: const [],
    books: [
      const BookEntry(
        bookName: '书甲',
        dirName: '书甲',
        outputDir: '/tmp/书甲',
        title: '书甲',
        author: '',
        chapterCount: 1,
        totalPages: 1,
        byteSize: 5,
        chapters: [],
      ),
    ],
    others: const [
      ChapterEntry(
        dirName: '未归并书乙',
        absDir: '/tmp/未归并书乙',
        imageCount: 2,
        translatedCount: 0,
        seqMax: 2,
        translatedSeqs: [],
        missingSeqs: [],
        merged: false,
      ),
    ],
    hidden: const [],
    hiddenCount: 0,
    updatedAt: DateTime(2026, 1, 1),
  );
}
