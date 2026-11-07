import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/app/app.dart';
import 'package:miao_dock_flutter/app/router/routes.dart';
import 'package:miao_dock_flutter/app/shell/app_shell.dart';
import 'package:miao_dock_flutter/app/shell/mobile_nav.dart';
import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_widgets.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// 阅读器保活（D-163）：
///   · 页码存在 provider 里 ⇒ 阅读器被重建后仍停在原来那一页；
///   · 只要没手动关闭，进漫画库 = 回到阅读器；
///   · 移动端阅读时全屏（不渲染顶部页签与底部一级导航）。
void main() {
  const session = ReaderSession(key: '某书', chapterNo: 1, pages: 3, translated: {});

  ProviderContainer newContainer() {
    final container = ProviderContainer(overrides: [mangaSvcClientProvider.overrideWithValue(_StubClient())]);
    container.read(readerSessionProvider.notifier).open(session);
    return container;
  }

  Widget wrap(Widget child, ProviderContainer container) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );

  group('阅读器页码跨重建保留', () {
    testWidgets('翻到第 2 页 → 卸载再挂载 → 仍是第 2 页', (tester) async {
      final container = newContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(wrap(const _Remountable(), container));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);

      // 点右侧 56px 热区翻页。
      final size = tester.getSize(find.byType(ReaderScreen));
      await tester.tapAt(Offset(size.width - 20, size.height / 2));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      // 卸载 = 切走页面 / 切走模块时 page 被销毁。
      await tester.tap(find.text('卸载阅读器'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);

      await tester.tap(find.text('挂载阅读器'));
      await tester.pumpAndSettle();
      // 破坏点：页码留在 State 里 → 这里会回到 1 / 3（用户实测的「回到第一页」）。
      expect(find.text('2 / 3'), findsOneWidget);
      // 顶栏文案来自 provider，可能是「假通过」：必须再核实 PageView 真的停在第 2 页。
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller!.page!.round(), 1);
    });

    testWidgets('手动关闭 → 会话与页码一起归零，下次从头读', (tester) async {
      final container = newContainer();
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/manga/reader',
        routes: [
          GoRoute(
            path: '/manga/reader',
            builder: (_, _) => const Scaffold(body: ReaderScreen()),
          ),
          // 关掉阅读器后 _close() 会 go 到漫画库（这里用占位替代）。
          GoRoute(path: '/manga/library', builder: (_, _) => const Text('library-view')),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(ReaderScreen));
      await tester.tapAt(Offset(size.width - 20, size.height / 2));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      // 顶栏 × = 手动关闭（与 Esc / 系统返回同一条路径）。
      await tester.tap(find.descendant(of: find.byType(ReaderBar), matching: find.byIcon(LucideIcons.chevronLeft)));
      await tester.pumpAndSettle();
      expect(find.text('library-view'), findsOneWidget);
      expect(container.read(readerSessionProvider), isNull);
      // 破坏点：close 只清会话不清页码 → 下次打开停在第 2 页。
      expect(container.read(readerPageProvider), 0);
    });
  });

  group('漫画库入口 = 回到阅读器（除非手动关闭）', () {
    test('会话开着 → 进漫画库重定向到阅读器', () {
      expect(readerResumeRedirect(session), '/manga/reader');
    });

    test('手动关闭后 → 不再重定向，正常进漫画库', () {
      // 破坏点：无条件重定向 → 关掉阅读器后点漫画库又被弹回阅读器，出不去。
      expect(readerResumeRedirect(null), isNull);
    });

    testWidgets('真实路由：开着会话点漫画库回阅读器；关闭后回漫画库', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const ProviderScope(child: MiaoDockApp()));
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
      final router = container.read(routerProvider);

      // pages: 0 ⇒ 阅读器渲染空态、不去取图（本用例只验证路由规则）。
      container.read(readerSessionProvider.notifier).open(const ReaderSession(key: '某书', pages: 0, translated: {}));
      router.go('/manga/library');
      await tester.pump();
      await tester.pump();
      expect(router.state.uri.path, '/manga/reader');

      container.read(readerSessionProvider.notifier).close();
      router.go('/manga/library');
      await tester.pump();
      await tester.pump();
      expect(router.state.uri.path, '/manga/library');
    });
  });

  group('移动端阅读器全屏', () {
    testWidgets('390×844：阅读器不渲染顶部页签与底部导航，其余页仍保留', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const ProviderScope(child: MiaoDockApp()));
      await tester.pump();

      final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
      final router = container.read(routerProvider);

      router.go('/manga/reader');
      await tester.pump();
      await tester.pump();
      // 破坏点：阅读器仍套在壳里 → 上下各一条导航，画布被压扁。
      expect(find.byType(MobileBottomNav), findsNothing);
      expect(find.byType(MobileViewTabs), findsNothing);

      router.go('/manga/library');
      await tester.pump();
      await tester.pump();
      expect(find.byType(MobileBottomNav), findsOneWidget);
      expect(find.byType(MobileViewTabs), findsOneWidget);
    });
  });
}

/// 阅读器宿主：可把 ReaderScreen 从树上摘掉再装回去（模拟切走页面）。
class _Remountable extends StatefulWidget {
  const _Remountable();

  @override
  State<_Remountable> createState() => _RemountableState();
}

class _RemountableState extends State<_Remountable> {
  bool _mounted = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: _mounted ? const ReaderScreen() : const SizedBox.shrink()),
          Row(
            children: [
              TextButton(onPressed: () => setState(() => _mounted = false), child: const Text('卸载阅读器')),
              TextButton(onPressed: () => setState(() => _mounted = true), child: const Text('挂载阅读器')),
            ],
          ),
        ],
      ),
    );
  }
}

/// 取图恒失败 → 阅读器显示占位而不是崩溃（与 reader_test 同口径）。
class _StubClient extends FakeMangaSvcClient {
  @override
  Future<List<int>> getChapterFile(String bookName, double chapterNo, int seq, {bool translated = false}) async =>
      Uint8List(0);

  @override
  Future<List<int>> getBookFile(String bookName, int seq, {bool translated = false}) async => Uint8List(0);
}
