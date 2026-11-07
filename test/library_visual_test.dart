import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_screen.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_detail.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_grid.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_shelf.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// D-102：漫画库视觉度量断言（把设计稿数值钉在测试里）。
///
/// 这些断言直接读 widget 的尺寸/颜色，改动样式若偏离设计稿会立刻失败。
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
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

  testWidgets('左栏固定 250 宽（设计稿 .lib-wrap 250px + 1fr）', (tester) async {
    await pump(tester);
    final shelf = tester.getSize(find.byType(LibraryShelf));
    expect(shelf.width, 250);
  });

  testWidgets('书架行：38×50 封面 + 两行文字；右侧详情 hero 常驻', (tester) async {
    await pump(tester);
    // 破坏点：行被改回 34 高的图标行 → 与设计稿 .srow（38×50 封面）不符。
    expect(find.byKey(const ValueKey('shelf-row-测试书')), findsOneWidget);
    expect(find.byKey(const ValueKey('shelf-cov-测试书')), findsOneWidget);
    final cov = tester.getSize(find.byKey(const ValueKey('shelf-cov-测试书')));
    expect(cov.width, 38);
    expect(cov.height, 50);
    // 设计稿右栏恒为详情（自动选中第一本）。
    expect(find.byType(LibraryDetail), findsOneWidget);
  });

  testWidgets('未归并单话在左栏「其他 · 未归并」分组，右栏无网格', (tester) async {
    await pump(tester);
    // 破坏点：桌面又把网格画出来 → 与「右栏恒为详情」不符。
    expect(find.text('其他 · 未归并'), findsOneWidget);
    expect(find.byKey(const ValueKey('shelf-row-未归并单话')), findsOneWidget);
    expect(find.byType(LibraryGrid), findsNothing);
  });
}

class _Client extends FakeMangaSvcClient {
  @override
  Future<List<int>?> getBookCover(String bookName) async => null;

  @override
  Future<LibraryResponse> listLibrary() async => LibraryResponse(
    root: '/tmp',
    count: 1,
    totalImages: 3,
    totalBytes: 100,
    comics: const [],
    books: [
      const BookEntry(
        bookName: '测试书',
        dirName: '测试书',
        outputDir: '/tmp/测试书',
        title: '测试书',
        author: '某作者',
        chapterCount: 1,
        totalPages: 2,
        byteSize: 50,
        chapters: [],
      ),
    ],
    others: [
      const ChapterEntry(
        dirName: '未归并单话',
        absDir: '/tmp/未归并单话',
        imageCount: 1,
        translatedCount: 0,
        seqMax: 1,
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
