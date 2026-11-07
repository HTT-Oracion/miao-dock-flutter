import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// 漫画库布局（设计稿 `.lib-wrap`）：
///
/// - 宽屏：左栏书架**常驻 250**，右栏恒为详情；**没有**「返回书架」按钮；
/// - 进库自动选中第一本（右栏不留白）；
/// - 取消选中（`select(null)`）→ 右栏给引导文案，书架仍在。
void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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

  testWidgets('进库自动选中第一本 → 右栏详情，书架常驻', (tester) async {
    await pump(tester);
    // 破坏点：不自动选中 → 右栏只有引导文案，本条失败。
    expect(find.text('某书'), findsWidgets); // 书架行 + 详情标题
    // 设计稿：书架不消失，「返回书架」按钮不存在。
    expect(find.text('返回书架'), findsNothing);
  });

  testWidgets('选中态下书架行仍在（设计稿点行只换右栏）', (tester) async {
    await pump(tester);
    // 书架行 + 详情标题同时可见。
    expect(find.byKey(const ValueKey('shelf-row-某书')), findsOneWidget);
    expect(find.text('某书'), findsWidgets);
  });

  testWidgets('select(null) → 右栏引导文案，书架不消失', (tester) async {
    await pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));
    container.read(selectedBookProvider.notifier).select(null);
    await tester.pumpAndSettle();
    expect(find.text('某书'), findsOneWidget); // 只剩书架行
    expect(find.text('从左侧书架选一本漫画'), findsOneWidget);
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
