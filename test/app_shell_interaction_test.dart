import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/app/shell/shell_controller.dart';
import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/shared/widgets/nav_rail.dart';

/// 侧栏折叠交互断言（design.html §03 / §05 / §06）。
///
/// 这些用例驱动**真实交互**（点折叠钮 → 状态翻转 → 宽度与图标跟着变），
/// 而不是只断言静态渲染，避免"组件写对了但接错线"的假绿。
void main() {
  /// 把 NavRail 接到真实的 navCollapsedProvider 上，模拟 AppShell 的接线方式。
  Widget harness() => ProviderScope(
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
      home: Consumer(
        builder: (context, ref, _) {
          final collapsed = ref.watch(navCollapsedProvider);
          return Scaffold(
            body: Row(
              children: [
                NavRail(
                  collapsed: collapsed,
                  labels: true,
                  onToggleCollapse: () => ref.read(navCollapsedProvider.notifier).toggle(),
                  moduleIndex: 0,
                  onSelectModule: (_) {},
                  viewGroupLabel: '漫画翻译',
                  viewItems: mangaViews,
                  activeViewId: 'drop',
                  onSelectView: (_) {},
                  queueCount: 0,
                  onOpenSettings: () {},
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  testWidgets('点收起 → 宽度 68，且出现展开钮（§05 双向都要提供）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(NavRail)).width, 208);

    await tester.tap(find.byIcon(LucideIcons.panelLeftClose));
    await tester.pumpAndSettle();

    // 破坏点：toggle 没接线 / 宽度没绑到状态，本条失败。
    expect(tester.getSize(find.byType(NavRail)).width, 68);
    expect(find.byIcon(LucideIcons.panelLeftOpen), findsOneWidget);
  });

  testWidgets('再点展开 → 回到 208（往返可逆）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.panelLeftClose));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(NavRail)).width, 68);

    await tester.tap(find.byIcon(LucideIcons.panelLeftOpen));
    await tester.pumpAndSettle();
    // 破坏点：展开钮没接 toggle，本条失败。
    expect(tester.getSize(find.byType(NavRail)).width, 208);
  });

  testWidgets('折叠动画期间不产生 RenderFlex 溢出（§06 形变 320ms）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.panelLeftClose));
    // 逐帧推进 320ms 动画，任何一帧溢出都会被 flutter_test 记为异常。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    // 破坏点：把内容按动画中的瞬时宽度布局（而非目标宽度），中间帧会溢出并被捕获。
    expect(tester.takeException(), isNull);
  });
}
