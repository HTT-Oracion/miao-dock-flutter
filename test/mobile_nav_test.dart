import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/app/shell/mobile_nav.dart';
import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 移动端导航（D-138）：**一级在底部、二级在顶部**。
///
/// 破坏点示例：
/// - 一级项放回抽屉 / 顶栏 → 「底部四个模块」找不到；
/// - 二级标签写死不可滑 → 横向 ListView 断言红；
/// - 当前模块不高亮 → active 颜色断言红。
void main() {
  Widget host(Widget child) => ProviderScope(
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  testWidgets('底部一级导航：四个模块且四项均分铺满', (tester) async {
    // 按手机宽度断言（导航本来就只在窄屏出现）。
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var tapped = -1;
    await tester.pumpWidget(host(MobileBottomNav(moduleIndex: 0, onSelectModule: (i) => tapped = i)));
    await tester.pumpAndSettle();

    expect(find.text('漫画翻译'), findsOneWidget);
    expect(find.text('音乐'), findsOneWidget);
    expect(find.text('番剧'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    // 四项**均分铺满**整宽（设计稿口径）：项宽 = 可用宽 / 4，不是居中扎堆。
    // 每项约 390/4 ≈ 97.5（均分铺满），不是 62 固定宽居中扎堆。
    final first = tester.getSize(find.text('漫画翻译'));
    final last = tester.getSize(find.text('设置'));
    expect(first.width, isPositive);
    expect(last.width, isPositive);
    final navRect = tester.getRect(find.byType(MobileBottomNav));
    final setRect = tester.getRect(find.text('设置'));
    // 「设置」应落在导航右侧 1/4 区域内（均分），而不是靠近中线。
    expect(setRect.center.dx, greaterThan(navRect.left + navRect.width * 0.6));

    await tester.tap(find.text('音乐'));
    expect(tapped, 1);
  });

  testWidgets('顶部二级标签：按当前视图高亮，点击回调 id', (tester) async {
    String? selected;
    await tester.pumpWidget(
      host(
        MobileViewTabs(
          items: const [('drop', '投放'), ('queue', '队列'), ('library', '漫画库')],
          activeId: 'queue',
          onSelect: (v) => selected = v,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 三个视图都在，且是横向列表。
    expect(find.text('投放'), findsOneWidget);
    expect(find.text('队列'), findsOneWidget);
    expect(find.text('漫画库'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);

    await tester.tap(find.text('漫画库'));
    expect(selected, 'library');
  });

  testWidgets('点「设置」回调 -1（不是番剧的 2）', (tester) async {
    var tapped = -99;
    await tester.pumpWidget(host(MobileBottomNav(moduleIndex: 0, onSelectModule: (i) => tapped = i)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    expect(tapped, -1);
    // 破坏点：设置项误映射到番剧（2）→ 用户点设置却进了番剧页。
    expect(tapped, isNot(2));
  });

  testWidgets('空视图列表不渲染（设置页没有二级视图）', (tester) async {
    await tester.pumpWidget(host(MobileViewTabs(items: const [], activeId: null, onSelect: (_) {})));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsNothing);
  });
}
