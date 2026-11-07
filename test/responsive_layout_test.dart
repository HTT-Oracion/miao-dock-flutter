import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_screen.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_detail.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_grid.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_shelf.dart';
import 'package:miao_dock_flutter/features/settings/ui/settings_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// D-137：窄屏（≤768）布局必须与宽屏不同 —— 否则手机上就是「双栏硬塞」。
void main() {
  Widget host(Widget child, {Object? client}) => ProviderScope(
    overrides: [mangaSvcClientProvider.overrideWithValue((client ?? _EmptyClient()) as MangaSvcClient)],
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
    // D-134：移动端网格显示全部（单本 + 单话）并带分段——书架入口按钮已移除
    // （旧断言「我的书架」入口在库里没有书时整页空白，用户裁定废除）。
    expect(find.text('全部 0'), findsOneWidget);
    expect(find.text('单本 0'), findsOneWidget);
    expect(find.text('单话 0'), findsOneWidget);
  });

  testWidgets('漫画库宽屏：书架栏与详情并排（设计稿 .lib-wrap）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const LibraryScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryShelf), findsOneWidget);
    expect(find.byType(LibraryDetail), findsOneWidget);
    // 设计稿右栏恒为详情：桌面不再有独立网格。
    expect(find.byType(LibraryGrid), findsNothing);
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

  testWidgets('移动端网格：分段（accent 选中）+ 单话卡带「单话」角标与「归并」快捷', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const LibraryScreen(), client: _OneBookClient()));
    await tester.pumpAndSettle();

    // 设计稿 `.mseg`：全部 / 单本 / 单话 三段，带计数。
    expect(find.text('全部 2'), findsOneWidget);
    expect(find.text('单本 1'), findsOneWidget);
    expect(find.text('单话 1'), findsOneWidget);
    // 设计稿 `.mlib-card.is-single`：单话角标 + 卡上快捷「归并」。
    expect(find.text('单话'), findsWidgets);
    expect(find.text('归并'), findsOneWidget);
    // 设计稿 `.mseg button.on{background:var(--acc)}`：选中段 = accent 底。
    final msegCester = find.ancestor(of: find.text('全部 2'), matching: find.byWidgetPredicate((w) => w is Container));
    final segCell = tester.widget<Container>(msegCester.first);
    expect((segCell.decoration! as BoxDecoration).color, AppPalette.dark.accent);
    // 破坏点：移动端出现详情覆盖（初始应停在网格）。
    expect(find.byType(LibraryDetail), findsNothing);
  });

  testWidgets('移动端分段「单话」过滤：只剩未归并单话卡', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const LibraryScreen(), client: _OneBookClient()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('单话 1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('grid-card-未归并单话')), findsOneWidget);
    expect(find.byKey(const ValueKey('grid-card-某书')), findsNothing);
  });
}

/// 一本 + 一单话：给分段计数与单话卡断言用。
class _OneBookClient extends FakeMangaSvcClient {
  @override
  Future<List<int>?> getBookCover(String bookName) async => null;

  @override
  Future<LibraryResponse> listLibrary() async => LibraryResponse(
    root: '/tmp',
    count: 2,
    totalImages: 3,
    totalBytes: 10,
    comics: const [],
    books: const [
      BookEntry(
        bookName: '某书',
        dirName: '某书',
        outputDir: '/tmp/某书',
        title: '某书',
        author: '作者',
        chapterCount: 1,
        totalPages: 2,
        byteSize: 5,
        chapters: [],
      ),
    ],
    others: const [
      ChapterEntry(
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
