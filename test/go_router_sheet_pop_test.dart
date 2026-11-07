import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/app_dialog.dart';
import 'package:miao_dock_flutter/shared/widgets/app_sheet.dart';
import 'package:miao_dock_flutter/shared/widgets/buttons.dart';

/// D-161：壳层分支里弹抽屉后「关闭」必须真的关掉，且不能把下面的页面 pop 掉。
///
/// 曾经的两个连锁问题（用户实测崩溃）：
/// 1. `showAppSheet` 传了外部 `AnimationController` —— 路由收不到 `dismissed`，
///    `pop()` 之后抽屉仍留在屏幕上；
/// 2. 用户以为没关上再点一次 × —— 那次 pop 落到下面的页面上，go_router 断言
///    `currentConfiguration.isNotEmpty` 直接崩（`_handlePopPage` 拿到的是 Page 而非浮层）。
void main() {
  Widget host() {
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => Scaffold(body: shell),
          branches: [
            StatefulShellBranch(
              routes: [GoRoute(path: '/a', builder: (_, _) => const _BranchScreen())],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/b', builder: (_, _) => const _OtherScreen())],
            ),
          ],
        ),
      ],
    );
    return MaterialApp.router(
      routerConfig: router,
      theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsOneWidget);
  }

  testWidgets('点 × 关闭：抽屉真的消失，且不触发 go_router 断言', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();

    // 破坏点 1：抽屉「关不掉」—— route 已 inactive，widget 还挂在 overlay 上。
    expect(find.byType(AppSheet), findsNothing);
    expect(find.text('归并到另一本'), findsNothing);
    // 下面的分支页面必须还在（否则第二次 pop 会把它 pop 掉）。
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('连点两次 ×：第二次是空操作，不 pop 掉页面', (tester) async {
    await openSheet(tester);

    // 第一次就关掉了；第二次点击不许再往下 pop（曾经在这里崩 go_router）。
    final close = tester.widget<AppButton>(find.byType(AppButton)).onTap;
    close!();
    close();
    await tester.pumpAndSettle();

    expect(find.byType(AppSheet), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _BranchScreen extends StatelessWidget {
  const _BranchScreen();

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => showAppDialog<void>(
        context: context,
        builder: (_) => const AppDialog(title: '归并到另一本', child: SizedBox(width: 300, height: 100)),
      ),
      child: const Text('open'),
    ),
  );
}

class _OtherScreen extends StatelessWidget {
  const _OtherScreen();

  @override
  Widget build(BuildContext context) => const Center(child: Text('other'));
}
