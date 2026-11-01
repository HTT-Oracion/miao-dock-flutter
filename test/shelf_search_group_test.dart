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

  testWidgets('浏览态：不出现分组标题', (tester) async {
    await pump(tester);
    expect(find.text('未归并'), findsNothing);
    expect(find.text('《书甲》'), findsNothing);
  });

  testWidgets('搜索态：书分组 + 未归并分组，且未归并在最后', (tester) async {
    await pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(LibraryShelf)));
    container.read(shelfQueryProvider.notifier).set('书');
    await tester.pumpAndSettle();

    expect(find.text('《书甲》'), findsOneWidget);
    expect(find.text('未归并'), findsOneWidget);

    // 破坏点：未归并组排到书分组前面 → 与「单独分组显示在未归并下方」不符。
    final unmergedY = tester.getTopLeft(find.text('未归并')).dy;
    final bookY = tester.getTopLeft(find.text('《书甲》')).dy;
    expect(unmergedY, greaterThan(bookY));
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
