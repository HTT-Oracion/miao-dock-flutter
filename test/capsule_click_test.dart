import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:protocol/protocol.dart';

/// 简易模式（胶囊）行为（设计稿 `renderMain` / `renderPages`）：
///
/// - 桌面：切简易 → 点「第 1 话」胶囊 → 打开**页网格**（`openChapter(i)`）；
/// - 页网格里点页卡 → 进入阅读器会话。
void main() {
  testWidgets('简易模式点胶囊 → 打开该话页网格；点页卡 → 阅读器会话', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final container = ProviderContainer(overrides: [mangaSvcClientProvider.overrideWithValue(_C())]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(body: LibraryScreen()),
              ),
              GoRoute(
                path: '/manga/reader',
                builder: (_, _) => const Scaffold(body: Text('READER')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 进某本书 → 切到简易模式。
    container.read(selectedBookProvider.notifier).select('书甲');
    await tester.pumpAndSettle();
    // 视图切换已改**图标式**（设计稿 .vseg）：点列表图标 = 简易。
    await tester.tap(find.byIcon(LucideIcons.list));
    await tester.pumpAndSettle();

    // 胶囊上显示「第 1 话」。
    final capsule = find.text('第 1 话');
    expect(capsule, findsOneWidget);

    await tester.tap(capsule);
    await tester.pumpAndSettle();

    // 设计稿：桌面胶囊点击进该话「页网格」（openChapter）。
    expect(container.read(libChapterOpenProvider), 1);

    // 页网格里点页卡 → 阅读器会话（第 1 话）。
    await tester.tap(find.text('001.png').first);
    await tester.pumpAndSettle();
    final session = container.read(readerSessionProvider);
    expect(session, isNotNull);
    expect(session!.key, '书甲');
    expect(session.chapterNo, 1);
  });
}

class _C extends FakeMangaSvcClient {
  @override
  Future<List<int>?> getBookCover(String n) async => null;

  @override
  Future<LibraryResponse> listLibrary() async => LibraryResponse(
    root: '/tmp',
    count: 1,
    totalImages: 2,
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
        totalPages: 2,
        byteSize: 5,
        chapters: [
          ChapterEntry(
            no: 1,
            dirName: '01_第1话',
            absDir: '/tmp/书甲/01_第1话',
            imageCount: 2,
            translatedCount: 1,
            seqMax: 2,
            translatedSeqs: [1],
            missingSeqs: [],
            merged: true,
          ),
        ],
      ),
    ],
    others: const [],
    hidden: const [],
    hiddenCount: 0,
    updatedAt: DateTime(2026, 1, 1),
  );
}
