import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_screen.dart';
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
  }

  testWidgets('左栏固定 260 宽（ver1.0 .lib-shelf）', (tester) async {
    await pump(tester);
    final shelf = tester.getSize(find.byType(LibraryShelf));
    expect(shelf.width, 260);
  });

  testWidgets('左侧列表行高 34、右侧网格卡片存在', (tester) async {
    await pump(tester);
    // 破坏点：行高被改成 40+ → 与 .nav-item 不一致。
    expect(find.byKey(const ValueKey('shelf-row-测试书')), findsOneWidget);
    // 行本体 34 + 底部 4 间距 = 38（Padding 在 _BookRow 内部）。
    final row = tester.getSize(find.byKey(const ValueKey('shelf-row-测试书')));
    expect(row.height, 38);
    expect(find.byKey(const ValueKey('grid-card-测试书')), findsOneWidget);
  });

  testWidgets('网格只显示单本；单话只在左栏', (tester) async {
    await pump(tester);
    // 破坏点：网格把未归并单话也画出来 → 与「右侧只显示单本」不符。
    expect(find.byKey(const ValueKey('grid-card-未归并单话')), findsNothing);
    expect(find.byKey(const ValueKey('shelf-row-未归并单话')), findsOneWidget);
  });
}

/// 探针：用 RepaintBoundary 标记左栏，便于读取尺寸。
class LibraryShelfProbe extends StatelessWidget {
  const LibraryShelfProbe({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
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
