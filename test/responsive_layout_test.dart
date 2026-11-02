import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_screen.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_grid.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_shelf.dart';
import 'package:miao_dock_flutter/features/settings/ui/settings_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// D-137：窄屏（≤768）布局必须与宽屏不同 —— 否则手机上就是「双栏硬塞」。
void main() {
  Widget host(Widget child) => ProviderScope(
    overrides: [mangaSvcClientProvider.overrideWithValue(_EmptyClient())],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  testWidgets('漫画库窄屏：隐藏书架栏，改顶部「书架」入口', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const LibraryScreen()));
    await tester.pumpAndSettle();

    // 破坏点：窄屏仍渲染左侧书架栏 → 网格被压成碎片。
    expect(find.byType(LibraryShelf), findsNothing);
    expect(find.byType(LibraryGrid), findsOneWidget);
    // 书架入口必须还在（否则未归并单话在手机上无法到达）。
    // 复用既有 ARB 词条（`shelfTitle` = 「我的书架」），没有新增文案。
    expect(find.text('我的书架'), findsOneWidget);
  });

  testWidgets('漫画库宽屏：书架栏与网格并排', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const LibraryScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryShelf), findsOneWidget);
    expect(find.byType(LibraryGrid), findsOneWidget);
  });

  testWidgets('设置页窄屏：无左侧导航栏，改顶部横向标签', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const SettingsScreen()));
    await tester.pumpAndSettle();
    // 破坏点：窄屏还把 208 左栏画出来 → 内容区只剩 180 宽。
    // 顶部标签应包含各分区（含翻译服务）。
    expect(find.textContaining('翻译'), findsWidgets);
  });
}

class _EmptyClient extends FakeMangaSvcClient {
  @override
  Future<LibraryResponse> listLibrary() async => LibraryResponse(
    root: '/tmp',
    count: 0,
    totalImages: 0,
    totalBytes: 0,
    comics: const [],
    books: const [],
    others: const [],
    hidden: const [],
    hiddenCount: 0,
    updatedAt: DateTime(2026, 1, 1),
  );
}
