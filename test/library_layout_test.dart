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

  testWidgets('进库默认选中第一本：显示详情（重设计 2026-11-07 用户裁定）', (tester) async {
    await pump(tester);
    // 破坏点：不自动选中 → 网格可见而非详情，本条失败。
    expect(find.text('返回书架'), findsOneWidget);
  });

  testWidgets('进库默认选中第一本 → 详情占满（左栏隐藏 + 返回书架）', (tester) async {
    await pump(tester);
    // 重设计裁定：进库自动选中第一本 → 详情态。
    expect(find.text('返回书架'), findsOneWidget);
  });

  testWidgets('返回书架 → 左栏 + 网格同时存在', (tester) async {
    await pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));
    container.read(selectedBookProvider.notifier).select(null);
    await tester.pumpAndSettle();
    // 返回书架后：左栏行 + 网格卡（某书出现 ≥2 处）。
    expect(find.text('某书'), findsAtLeastNWidgets(2));
  });

  testWidgets('选中某本 → 左栏消失 + 返回书架出现', (tester) async {
    await pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));
    container.read(selectedBookProvider.notifier).select(null);
    await tester.pumpAndSettle();
    container.read(selectedBookProvider.notifier).select('某书');
    await tester.pumpAndSettle();
    expect(find.text('返回书架'), findsOneWidget);
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
