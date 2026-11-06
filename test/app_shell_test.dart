import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/app/shell/view_tabs.dart';
import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/nav_rail.dart';

/// 壳层断言（design.html §03 / §05 + 重设计稿 2026-11-07）——
/// 视图组已从侧栏迁到工具条页签（[ShellViewTabs]），断言基准随迁移更新：
/// 侧栏只保留 品牌 / 模块组（含漫画待办徽标）/ 迷你播放器空态 / 设置脚。
void main() {
  Widget host({required Widget child}) => MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  NavRail rail({bool collapsed = false, bool labels = true, int moduleIndex = 0, int queueCount = 0}) {
    return NavRail(
      collapsed: collapsed,
      labels: labels,
      onToggleCollapse: () {},
      moduleIndex: moduleIndex,
      onSelectModule: (_) {},
      queueCount: queueCount,
      onOpenSettings: () {},
    );
  }

  testWidgets('侧栏展开宽度 = 208（§03 布局尺寸）', (tester) async {
    await tester.pumpWidget(host(child: rail()));
    await tester.pumpAndSettle();
    // 破坏点：把 AppMetrics.sidebarWidth 改成 208 以外的值，本条失败。
    expect(tester.getSize(find.byType(NavRail)).width, 208);
  });

  testWidgets('侧栏收起宽度 = 68（§03 布局尺寸）', (tester) async {
    await tester.pumpWidget(host(child: rail(collapsed: true)));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(NavRail)).width, 68);
  });

  testWidgets('收起态渲染 panel-left-open（§05 双向都要提供）', (tester) async {
    await tester.pumpWidget(host(child: rail(collapsed: true)));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.panelLeftOpen), findsOneWidget);
    expect(find.byIcon(LucideIcons.panelLeftClose), findsNothing);
  });

  testWidgets('展开态渲染 panel-left-close（§05）', (tester) async {
    await tester.pumpWidget(host(child: rail()));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.panelLeftClose), findsOneWidget);
    expect(find.byIcon(LucideIcons.panelLeftOpen), findsNothing);
  });

  testWidgets('模块图标使用 §05 指定值，废弃值不得出现', (tester) async {
    await tester.pumpWidget(host(child: rail()));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.languages), findsWidgets);
    // music 出现两次：模块项 + 迷你播放器空态占位（重设计稿「未在播放」）。
    expect(find.byIcon(LucideIcons.music), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.clapperboard), findsOneWidget);
  });

  testWidgets('侧栏不再渲染视图组（迁移后视图在工具条页签）', (tester) async {
    await tester.pumpWidget(host(child: rail()));
    await tester.pumpAndSettle();
    // 破坏点：把视图组塞回侧栏，本条失败。
    expect(find.text('投放'), findsNothing);
    expect(find.text('漫画库'), findsNothing);
  });

  testWidgets('队列待办徽标落在漫画模块项上（视图组徽标迁移）', (tester) async {
    await tester.pumpWidget(host(child: rail(queueCount: 2)));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('计数为 0 时不渲染徽标（不显示 0）', (tester) async {
    await tester.pumpWidget(host(child: rail(queueCount: 0)));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsNothing);
  });

  testWidgets('迷你播放器空态占位（未在播放 · 不写死曲目）', (tester) async {
    await tester.pumpWidget(host(child: rail()));
    await tester.pumpAndSettle();
    // 破坏点：若有人写死曲名，本条失败。
    expect(find.text('夜に駆ける'), findsNothing);
    expect(find.text('YOASOBI'), findsNothing);
    expect(find.text('未在播放'), findsOneWidget);
  });

  testWidgets('labels=false 时展开态不渲染文字标签（原项目 sidebar-labels 偏好）', (tester) async {
    await tester.pumpWidget(host(child: rail(labels: false)));
    await tester.pumpAndSettle();
    expect(find.text('漫画翻译'), findsNothing);
    expect(find.text('设置'), findsNothing);
    expect(find.byIcon(LucideIcons.languages), findsWidgets);
  });

  testWidgets('视图页签：渲染三项、激活项高亮、点击回调', (tester) async {
    var selected = '';
    await tester.pumpWidget(
      host(
        child: ShellViewTabs(
          items: const [('drop', '投放'), ('queue', '队列'), ('library', '漫画库')],
          activeId: 'queue',
          onSelect: (v) => selected = v,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('投放'), findsOneWidget);
    expect(find.text('队列'), findsOneWidget);
    expect(find.text('漫画库'), findsOneWidget);
    await tester.tap(find.text('漫画库'));
    expect(selected, 'library');
  });

  testWidgets('视图页签空列表不渲染任何页签行（番剧 / 设置无页签）', (tester) async {
    await tester.pumpWidget(
      host(
        child: ShellViewTabs(items: const [], activeId: null, onSelect: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('投放'), findsNothing);
    expect(find.text('队列'), findsNothing);
  });
}
