import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/app/shell/shell_controller.dart';
import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/nav_rail.dart';

/// 壳层断言（design.html §03 / §05）—— 每条都写明「破坏什么会让它失败」。
void main() {
  Widget host({required Widget child}) => MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  NavRail rail({
    bool collapsed = false,
    bool labels = true,
    int moduleIndex = 0,
    String? activeViewId = 'drop',
    int queueCount = 0,
    List<SidebarViewItem>? items,
  }) {
    return NavRail(
      collapsed: collapsed,
      labels: labels,
      onToggleCollapse: () {},
      moduleIndex: moduleIndex,
      onSelectModule: (_) {},
      viewGroupLabel: '漫画翻译',
      viewItems: items ?? mangaViews,
      activeViewId: activeViewId,
      onSelectView: (_) {},
      queueCount: queueCount,
      onOpenSettings: () {},
    );
  }

  testWidgets('侧栏展开宽度 = 208（§03 布局尺寸）', (tester) async {
    await tester.pumpWidget(host(child: rail()));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(NavRail));
    // 破坏点：把 AppMetrics.sidebarWidth 改成 208 以外的值，本条失败。
    expect(size.width, 208);
  });

  testWidgets('侧栏收起宽度 = 68（§03 布局尺寸）', (tester) async {
    await tester.pumpWidget(host(child: rail(collapsed: true)));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(NavRail));
    // 破坏点：把 sidebarCollapsedWidth 改回 64（旧实现值），本条失败。
    expect(size.width, 68);
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
    // 破坏点：模块图标改回 bookImage / tv（废弃值）时本条失败。
    expect(find.byIcon(LucideIcons.languages), findsWidgets);
    expect(find.byIcon(LucideIcons.music), findsOneWidget);
    expect(find.byIcon(LucideIcons.clapperboard), findsOneWidget);
  });

  testWidgets('漫画视图组图标 = folder-up / list-minus / book-text（§05）', (tester) async {
    await tester.pumpWidget(host(child: rail()));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.folderUp), findsOneWidget);
    expect(find.byIcon(LucideIcons.listMinus), findsOneWidget);
    expect(find.byIcon(LucideIcons.bookText), findsOneWidget);
  });

  testWidgets('音乐视图组渲染四视图（§03 侧栏按模块给视图组）', (tester) async {
    await tester.pumpWidget(
      host(
        child: rail(moduleIndex: 1, activeViewId: 'discover', items: musicViews),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('我的歌单'), findsOneWidget);
    expect(find.text('本地音乐'), findsOneWidget);
    expect(find.text('播放历史'), findsOneWidget);
  });

  testWidgets('队列计数徽标只在该视图显示（原项目 queueDepth 口径）', (tester) async {
    await tester.pumpWidget(host(child: rail(queueCount: 2)));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('计数为 0 时不渲染徽标（不显示 0）', (tester) async {
    await tester.pumpWidget(host(child: rail(queueCount: 0)));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsNothing);
  });

  testWidgets('收起态不渲染视图组（§03 收起仅纯图标导航）', (tester) async {
    await tester.pumpWidget(host(child: rail(collapsed: true)));
    await tester.pumpAndSettle();
    expect(find.text('投放'), findsNothing);
    expect(find.text('漫画库'), findsNothing);
  });

  testWidgets('labels=false 时展开态不渲染文字标签（原项目 sidebar-labels 偏好）', (tester) async {
    await tester.pumpWidget(host(child: rail(labels: false)));
    await tester.pumpAndSettle();
    expect(find.text('漫画翻译'), findsNothing);
    expect(find.text('设置'), findsNothing);
    // 图标仍要在：关标签只是去掉文字，不是关掉导航。
    expect(find.byIcon(LucideIcons.languages), findsWidgets);
  });

  testWidgets('MiniPlayer 无播放状态时整块不渲染（禁止假数据）', (tester) async {
    await tester.pumpWidget(host(child: rail()));
    await tester.pumpAndSettle();
    // 破坏点：若有人在 NavRail 里写死曲名，本条失败。
    expect(find.text('夜に駆ける'), findsNothing);
    expect(find.text('YOASOBI'), findsNothing);
  });
}
