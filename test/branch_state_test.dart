import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:miao_dock_flutter/app/shell/module_nav.dart';
import 'package:miao_dock_flutter/app/shell/shell_controller.dart';
import 'package:miao_dock_flutter/features/settings/controller/section_controller.dart';

/// 模块保活断言（用户诉求：切换模块后回到「当时那个页面」）。
///
/// 用真实的 [switchModule] 驱动一个与生产同构的 `StatefulShellRoute.indexedStack`，
/// 分支页用带计数器的 `StatefulWidget` 模拟「阅读器翻到第 N 页」——
/// 只要切换经过重建，计数器就会归零。
///
/// 破坏点：把 `switchModule` 里的 `shell.goBranch(index)` 改回 `context.go(首屏)`
/// （这正是用户实测「看漫画 → 切设置 → 点漫画回到投放页」的那个写法），
/// 第 1、2 条会失败。
void main() {
  GoRouter buildRouter() {
    GoRoute branchRoute(String path, Widget child) => GoRoute(path: path, builder: (_, _) => child);
    return GoRouter(
      // 漫画分支首屏是「投放」，与生产一致 —— 旧实现切模块就是 go('/manga/drop')。
      initialLocation: '/manga/drop',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => _Shell(shell: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                branchRoute('/manga/drop', const _DropPage()),
                branchRoute('/manga/reader', const _ReaderPage()),
              ],
            ),
            StatefulShellBranch(routes: [branchRoute('/music/discover', const Text('music-view'))]),
            StatefulShellBranch(routes: [branchRoute('/anime', const Text('anime-view'))]),
            StatefulShellBranch(routes: [branchRoute('/settings', const Text('settings-view'))]),
          ],
        ),
      ],
    );
  }

  late GoRouter router;

  Future<void> pumpApp(WidgetTester tester) async {
    router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// 从漫画库（投放占位）点「阅读」进阅读器 —— 模拟真实进入路径。
  Future<void> openReaderAndRead(WidgetTester tester, {int pages = 2}) async {
    await tap(tester, 'open-reader');
    for (var i = 0; i < pages; i++) {
      await tap(tester, 'turn-page');
    }
  }

  testWidgets('切到其他模块再回来，停在同一页（阅读器页码不归零）', (tester) async {
    await pumpApp(tester);
    expect(find.text('drop-view'), findsOneWidget);

    await openReaderAndRead(tester);
    expect(find.text('reader-page-6'), findsOneWidget);

    await tap(tester, 'nav-music');
    expect(find.text('music-view'), findsOneWidget);
    // 非当前分支是 offstage：默认 finder 跳过，说明确实切走了。
    expect(find.text('reader-page-6'), findsNothing);

    await tap(tester, 'nav-manga');
    // 破坏点：切模块改成 `context.go('/manga/drop')`（跳首屏）→ 这里会回到 drop-view。
    expect(find.text('reader-page-6'), findsOneWidget);
    expect(find.text('drop-view'), findsNothing);
  });

  testWidgets('点当前已激活的模块：无操作，不从当前页面踢走', (tester) async {
    await pumpApp(tester);
    await openReaderAndRead(tester, pages: 1);
    expect(find.text('reader-page-3'), findsOneWidget);

    await tap(tester, 'nav-manga');
    // 破坏点：改成「点当前模块回首屏」→ 回到 drop-view。
    expect(find.text('reader-page-3'), findsOneWidget);
    expect(find.text('drop-view'), findsNothing);
  });

  testWidgets('设置页不保活：每次进入都回到「通用」分区', (tester) async {
    await pumpApp(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(_Shell)));

    // 先假装上次停在「翻译」分区。
    container.read(settingsSectionProvider.notifier).select('translate');
    expect(container.read(settingsSectionProvider), 'translate');

    await tap(tester, 'nav-settings');
    expect(find.text('settings-view'), findsOneWidget);
    // 破坏点：进设置不重置分区 → 仍是 translate。
    expect(container.read(settingsSectionProvider), 'general');

    // 切走再进一次，仍然干净。
    container.read(settingsSectionProvider.notifier).select('media');
    await tap(tester, 'nav-manga');
    await tap(tester, 'nav-settings');
    expect(container.read(settingsSectionProvider), 'general');
  });

  group('resolveViewId：子页归属视图（页签高亮 / 面包屑）', () {
    test('阅读器归到漫画库', () {
      // 破坏点：不加别名 → 会回落到首个视图 'drop'，页签错跳到「投放」。
      expect(resolveViewId('reader', mangaViews), 'library');
    });

    test('引导页归到投放', () {
      expect(resolveViewId('notready', mangaViews), 'drop');
      expect(resolveViewId('degraded', mangaViews), 'drop');
    });

    test('清单内的段原样返回', () {
      expect(resolveViewId('queue', mangaViews), 'queue');
      expect(resolveViewId('playlist', musicViews), 'playlist');
    });

    test('未知段回落到首个视图', () {
      expect(resolveViewId('whatever', mangaViews), 'drop');
      expect(resolveViewId(null, mangaViews), 'drop');
    });

    test('模块没有视图清单时返回 null', () {
      expect(resolveViewId('any', const []), isNull);
    });
  });
}

/// 壳层：三个模块 + 设置入口，全部走生产代码的 [switchModule]。
class _Shell extends ConsumerWidget {
  const _Shell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(int index) => switchModule(context, ref, shell, index);
    return Scaffold(
      body: Column(
        children: [
          Row(
            children: [
              TextButton(onPressed: () => go(0), child: const Text('nav-manga')),
              TextButton(onPressed: () => go(1), child: const Text('nav-music')),
              TextButton(onPressed: () => go(-1), child: const Text('nav-settings')),
            ],
          ),
          Expanded(child: shell),
        ],
      ),
    );
  }
}

/// 假「投放 / 漫画库」页：从这里点进阅读器（模拟漫画库的「阅读」按钮）。
class _DropPage extends StatelessWidget {
  const _DropPage();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('drop-view'),
        TextButton(onPressed: () => context.go('/manga/reader'), child: const Text('open-reader')),
      ],
    );
  }
}

/// 假阅读器：页码存在 State 里 —— 页面被重建即归零。
class _ReaderPage extends StatefulWidget {
  const _ReaderPage();

  @override
  State<_ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<_ReaderPage> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('reader-page-$_page'),
        TextButton(onPressed: () => setState(() => _page += 3), child: const Text('turn-page')),
      ],
    );
  }
}
