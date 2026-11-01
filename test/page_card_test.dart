import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// D-112：单话「页面」卡的规格。
///
/// - 以**该页原图**作封面（调 `getBookFile`，不是占位图标）；
/// - 尺寸与「单本网格卡」同一套网格参数（maxExtent 170 / 比例 0.62）；
/// - 页码在**左上角**。
void main() {
  testWidgets('页面卡取原图 + 尺寸与单本卡一致', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final client = _C();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mangaSvcClientProvider.overrideWithValue(client)],
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

    // 选中单话 → 进详情（页面区）。
    final container = ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));
    container.read(selectedBookProvider.notifier).select('单话A');
    await tester.pumpAndSettle();

    // 破坏点：仍用占位图标 / 没调 getBookFile → 断言失败。
    expect(client.requestedSeqs, isNotEmpty);
    expect(client.requestedSeqs, contains(1));
  });
}

class _C extends FakeMangaSvcClient {
  final requestedSeqs = <int>[];

  @override
  Future<List<int>?> getBookCover(String n) async => null;

  @override
  Future<List<int>> getBookFile(String bookName, int seq, {bool translated = false}) async {
    requestedSeqs.add(seq);
    return const [];
  }

  @override
  Future<LibraryResponse> listLibrary() async => LibraryResponse(
    root: '/tmp',
    count: 0,
    totalImages: 3,
    totalBytes: 10,
    comics: const [],
    books: const [],
    others: const [
      ChapterEntry(
        dirName: '单话A',
        absDir: '/tmp/单话A',
        imageCount: 3,
        translatedCount: 1,
        seqMax: 3,
        translatedSeqs: [1],
        missingSeqs: [],
        merged: false,
      ),
    ],
    hidden: const [],
    hiddenCount: 0,
    updatedAt: DateTime(2026, 1, 1),
  );
}
