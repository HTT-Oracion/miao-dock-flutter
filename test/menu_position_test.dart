import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/shared/widgets/app_menu.dart';

/// D-106：下拉菜单定位 —— **触发按钮正下方、左边缘对齐**。
void main() {
  testWidgets('菜单出现在按钮下方且左对齐', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    // 模拟一个位于 (200,100)、尺寸 80×24 的按钮。
    const anchor = Rect.fromLTWH(200, 100, 80, 24);
    showAppMenu(
      ctx,
      anchor: anchor,
      minWidth: 160,
      items: const [
        AppMenuItem(value: 'a', label: 'AAA'),
        AppMenuItem(value: 'b', label: 'BBB'),
      ],
    );
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byType(AppMenu));
    // 破坏点：用点击点或居中 → 左边不再是 200。
    expect(panel.left, closeTo(anchor.left, 1));
    // 破坏点：贴着鼠标而不是按钮下方 → top 不再约等于 128。
    expect(panel.top, closeTo(anchor.bottom + 4, 1));
  });

  testWidgets('底部空间不足时向上翻转', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    // 按钮贴近底部：菜单应翻到上方。
    const anchor = Rect.fromLTWH(200, 560, 80, 24);
    showAppMenu(
      ctx,
      anchor: anchor,
      minWidth: 160,
      items: const [
        AppMenuItem(value: 'a', label: 'AAA'),
        AppMenuItem(value: 'b', label: 'BBB'),
        AppMenuItem(value: 'c', label: 'CCC'),
      ],
    );
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byType(AppMenu));
    // 破坏点：不翻转 → 菜单被裁到屏幕外，项点不到。
    expect(panel.bottom, lessThanOrEqualTo(anchor.top));
  });
}
