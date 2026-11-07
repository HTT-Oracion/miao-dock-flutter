import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_detail.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_grid.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/app_dialog.dart';
import 'package:miao_dock_flutter/shared/widgets/app_sheet.dart';
import 'package:miao_dock_flutter/shared/widgets/buttons.dart';
import 'package:protocol/protocol.dart';

/// D-160：移动端弹窗统一抽屉 + 漫画库顶栏/卡片动作。
/// 窄屏断言口径见 AGENTS §4 第 16 条：以 390×844 为准，断言「不该出现的东西没出现」。
void main() {
  Widget host(Widget child) => ProviderScope(
    overrides: [mangaSvcClientProvider.overrideWithValue(_BooksClient())],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('390×844：弹窗走抽屉，不出现居中 Dialog', (tester) async {
    useSize(tester, const Size(390, 844));
    await tester.pumpWidget(host(const Center(child: _OpenSurface())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开浮层'));
    await tester.pumpAndSettle();

    // 破坏点：showAppDialog 不分平台，手机上仍是居中弹窗。
    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('1440×900：弹窗保持居中 Dialog，不出现抽屉', (tester) async {
    useSize(tester, const Size(1440, 900));
    await tester.pumpWidget(host(const Center(child: _OpenSurface())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开浮层'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(AppSheet), findsNothing);
  });

  testWidgets('390×844：漫画库头部「新建漫画」为单个图标按钮，点开是抽屉', (tester) async {
    useSize(tester, const Size(390, 844));
    await tester.pumpWidget(host(const Center(child: LibraryHeaderActions())));
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.plus), findsOneWidget);
    expect(find.byType(AppButton), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('390×844：漫画库卡片「⋯」出操作抽屉，含隐藏与删除', (tester) async {
    useSize(tester, const Size(390, 844));
    await tester.pumpWidget(host(const LibraryGrid()));
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.ellipsis), findsWidgets);
    await tester.tap(find.byIcon(LucideIcons.ellipsis).first);
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.text('隐藏作品'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('390×844：卡片「⋯」压在封面右下角（20×20）', (tester) async {
    useSize(tester, const Size(390, 844));
    await tester.pumpWidget(host(const LibraryGrid()));
    await tester.pumpAndSettle();

    // 破坏点：⋯ 排在封面 Image 之前 → 被图片整块盖住（用户实测「卡片没有 ⋯」）；
    // 或挪回右上角 → 与设计稿 `.mg-more{right:4;bottom:4}` 不符。
    final card = find.byKey(const ValueKey('grid-card-某书'));
    expect(card, findsOneWidget);
    final cover = tester.getRect(find.descendant(of: card, matching: find.byType(AspectRatio)).first);
    final more = tester.getRect(find.descendant(of: card, matching: find.byIcon(LucideIcons.ellipsis)));
    // 右下角：落在封面右下象限内。
    expect(more.center.dx, greaterThan(cover.center.dx));
    expect(more.center.dy, greaterThan(cover.center.dy));
    // 设计稿：20×20 按钮距边 4；封面有 1px 描边（Stack 内缩 1）⇒ 图标框距外框 5。
    expect(more.size, const Size(20, 20));
    expect(cover.right - more.right, closeTo(5, 0.6));
    expect(cover.bottom - more.bottom, closeTo(5, 0.6));
  });

  testWidgets('抽屉菜单文案走 ARB（无中文硬编码）', (tester) async {
    useSize(tester, const Size(390, 844));
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(l10n.libSheetMenuTitle, '漫画操作');
    expect(l10n.libSheetHide, '隐藏作品');
    expect(l10n.libSheetHideSub, isNotEmpty);
  });
}

class _OpenSurface extends StatelessWidget {
  const _OpenSurface();

  @override
  Widget build(BuildContext context) => AppButton(
    label: '打开浮层',
    onTap: () => showAppDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: '测试浮层',
        actions: [AppButton(label: '关闭', onTap: () => Navigator.of(context).pop())],
        child: const Text('内容'),
      ),
    ),
  );
}

class _BooksClient extends FakeMangaSvcClient {
  @override
  Future<List<int>?> getBookCover(String bookName) async => null;

  @override
  Future<LibraryResponse> listLibrary() async => LibraryResponse(
    root: '/tmp',
    count: 1,
    totalImages: 2,
    totalBytes: 5,
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
    others: const [],
    hidden: const [],
    hiddenCount: 0,
    updatedAt: DateTime(2026, 1, 1),
  );
}
