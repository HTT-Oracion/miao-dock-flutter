import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/shared/widgets/app_checkbox.dart';
import 'package:miao_dock_flutter/shared/widgets/app_switch.dart';
import 'package:miao_dock_flutter/shared/widgets/buttons.dart';

/// D-110：**可交互组件的 cursor 规范**。
///
/// 启用 → `SystemMouseCursors.click`（可点）；
/// 禁用 → `SystemMouseCursors.forbidden`（不可点，而不是普通箭头）。
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
    home: Scaffold(body: Center(child: child)),
  );

  /// 取**最外层**的 MouseRegion（内层 InkWell 自带一个 basic，不能误取）。
  MouseCursor cursorOf(WidgetTester tester, Finder inner) {
    final regions = find.ancestor(of: inner, matching: find.byType(MouseRegion)).evaluate().toList();
    expect(regions, isNotEmpty);
    return (regions.last.widget as MouseRegion).cursor;
  }

  testWidgets('AppGhostButton：启用手型 / 禁用禁止', (tester) async {
    await tester.pumpWidget(wrap(AppGhostButton(label: 'ok', onTap: () {})));
    expect(cursorOf(tester, find.text('ok')), SystemMouseCursors.click);

    await tester.pumpWidget(wrap(const AppGhostButton(label: 'off', onTap: null)));
    // 破坏点：禁用时用普通箭头 → 用户不知道不可点。
    expect(cursorOf(tester, find.text('off')), SystemMouseCursors.forbidden);
  });

  testWidgets('AppCheckbox：启用手型 / 禁用禁止', (tester) async {
    await tester.pumpWidget(wrap(AppCheckbox(value: true, onChanged: (_) {})));
    expect(cursorOf(tester, find.byType(Checkbox)), SystemMouseCursors.click);

    await tester.pumpWidget(wrap(AppCheckbox(value: true, enabled: false, onChanged: (_) {})));
    expect(cursorOf(tester, find.byType(Checkbox)), SystemMouseCursors.forbidden);
  });

  testWidgets('AppSwitch：启用手型 / 禁用禁止', (tester) async {
    // AppSwitch 的 MouseRegion 在组件**内部**（不是祖先），直接取内部第一个。
    MouseCursor inner() => tester
        .widget<MouseRegion>(find.descendant(of: find.byType(AppSwitch), matching: find.byType(MouseRegion)).first)
        .cursor;

    await tester.pumpWidget(wrap(AppSwitch(value: true, onChanged: (_) {})));
    expect(inner(), SystemMouseCursors.click);

    await tester.pumpWidget(wrap(AppSwitch(value: true, enabled: false, onChanged: (_) {})));
    // 破坏点：禁用时不改光标 → 用户会以为能点。
    expect(inner(), SystemMouseCursors.forbidden);
  });
}
