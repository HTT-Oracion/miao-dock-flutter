import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/shared/widgets/app_dropdown.dart';

/// D-114：下拉菜单定位由 **Material 3 `MenuAnchor`** 负责。
///
/// 断言：菜单展开后 **在触发按钮正下方（top ≥ 按钮底部）且左边缘对齐**
/// （`Alignment.bottomLeft` 的 M3 默认语义）。
void main() {
  Widget harness(Widget child) => MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('菜单出现在按钮正下方，左边缘对齐', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpWidget(
      harness(
        AppDropdownMenu(
          minWidth: 160,
          onSelected: (_) {},
          items: const [
            AppDropdownItem(value: 'a', label: 'AAA'),
            AppDropdownItem(value: 'b', label: 'BBB'),
          ],
          child: const SizedBox(width: 80, height: 24, child: Text('trigger')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final trigger = tester.getRect(find.text('trigger'));
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    final menu = tester.getRect(find.text('AAA'));
    // 破坏点：菜单盖住按钮 / 跑到按钮上方 → top 判定失败。
    expect(menu.top, greaterThanOrEqualTo(trigger.bottom));
    // 破坏点：菜单居中或右对齐 → left 判定失败。
    expect(menu.left, closeTo(trigger.left + 9, 12));
  });
}
