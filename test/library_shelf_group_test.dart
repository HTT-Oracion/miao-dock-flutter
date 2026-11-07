import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_screen.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_shelf.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// 书架【其他 · 未归并】分组断言（重设计稿 2026-11-07）：
/// 浏览态单话归入「其他 · 未归并」分组；脚注「未归并 N」= 打开右栏陈列页
/// （设计稿 `showSingles()`，书架本身不再过滤）。
/// Fixture 与 library_layout_test 同款（某书 + 某单话），断言可反证。
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
    // 重设计：进库自动选中第一本 ⇒ 先取消回到 grid+shelf 态再断言。
    final c = ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));
    c.read(selectedBookProvider.notifier).select(null);
    await tester.pumpAndSettle();
  }

  testWidgets('浏览态出现「其他 · 未归并」分组，单话行在组内', (tester) async {
    await pump(tester);
    // 破坏点：把单话塞回平铺（去掉分组标题），本条失败。
    expect(find.text('其他 · 未归并'), findsOneWidget);
    // 单话行在组内仍可见（书架行 + 网格卡 ≥2 处）。
    expect(find.text('某单话'), findsAtLeastNWidgets(1));
  });

  testWidgets('脚注「未归并 N」点击 → 右栏陈列页开关翻转（书架不过滤）', (tester) async {
    await pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(LibraryShelf)));
    expect(container.read(libSinglesViewProvider), isFalse);
    // 脚注文案 = shelfUnmergedFilter(1) = 「未归并 1」。
    await tester.tap(find.text('未归并 1'));
    await tester.pumpAndSettle();
    // 设计稿 showSingles()：翻陈列页开关；书架两组都还在（不过滤）。
    expect(container.read(libSinglesViewProvider), isTrue);
    expect(find.text('其他 · 未归并'), findsOneWidget);
    expect(find.byKey(const ValueKey('shelf-row-某单话')), findsOneWidget);
  });
}

class _Client extends FakeMangaSvcClient {
  @override
  Future<List<int>?> getBookCover(String bookName) async => null;

  @override
  Future<LibraryResponse> listLibrary() async => LibraryResponse(
    root: '/tmp',
    count: 2,
    totalImages: 4,
    totalBytes: 100,
    comics: const [],
    updatedAt: DateTime(2026, 1, 1),
    books: [
      const BookEntry(
        bookName: '某书',
        dirName: '某书',
        outputDir: '/tmp/某书',
        title: '某书',
        author: '',
        chapterCount: 1,
        totalPages: 2,
        byteSize: 50,
        chapters: [],
      ),
    ],
    others: [
      const ChapterEntry(
        dirName: '某单话',
        absDir: '/tmp/某单话',
        imageCount: 2,
        translatedCount: 2,
        seqMax: 2,
        translatedSeqs: [1, 2],
        missingSeqs: [],
        merged: false,
      ),
    ],
  );
}
