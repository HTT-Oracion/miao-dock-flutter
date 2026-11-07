import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/shared/widgets/buttons.dart';

/// ghost 变体对齐设计稿 `.btn.ghost`：
///   `{color:var(--ink2); border:1px solid var(--line2)}`
///   `:hover{background:var(--hi); color:var(--ink)}`
///
/// 破坏点：把常态字改回 `ink`、把 hover 底色去掉、或让 border 参数继续空转，
/// 下面的断言会直接失败。
void main() {
  const palette = AppPalette.dark;

  Widget host(Widget child) => MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
    home: Scaffold(body: Center(child: child)),
  );

  /// 按钮底色由外层 Material 承载（D-120：InkWell 的 hover 覆盖层已关）。
  Material materialOf(WidgetTester tester) =>
      tester.widget<Material>(find.descendant(of: find.byType(AppButton), matching: find.byType(Material)).first);

  RoundedRectangleBorder shapeOf(WidgetTester tester) => materialOf(tester).shape! as RoundedRectangleBorder;

  Color textColorOf(WidgetTester tester, String label) => tester.widget<Text>(find.text(label)).style!.color!;

  Future<void> hover(WidgetTester tester, String label) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text(label)));
    await tester.pumpAndSettle();
  }

  testWidgets('ghost 默认态：透明底 + line2 描边 + ink2 字', (tester) async {
    await tester.pumpWidget(host(AppButton(label: '返回书架', onTap: () {}, variant: AppButtonVariant.ghost)));

    expect(materialOf(tester).color, Colors.transparent);
    expect(shapeOf(tester).side.color, palette.line2);
    expect(shapeOf(tester).side.width, 1);
    expect(textColorOf(tester, '返回书架'), palette.ink2);
  });

  testWidgets('ghost hover：底色 hi、字提亮到 ink、描边保持 line2', (tester) async {
    await tester.pumpWidget(host(AppButton(label: '取消', onTap: () {}, variant: AppButtonVariant.ghost)));
    await hover(tester, '取消');

    expect(materialOf(tester).color, palette.hi);
    expect(textColorOf(tester, '取消'), palette.ink);
    // 设计稿 :hover 只改 background 与 color，未改 border-color。
    expect(shapeOf(tester).side.color, palette.line2);
  });

  testWidgets('非 ghost 变体默认不描边（secondary / primary）', (tester) async {
    await tester.pumpWidget(host(AppButton(label: '更多', onTap: () {})));
    expect(shapeOf(tester).side, BorderSide.none);

    await tester.pumpWidget(host(AppButton(label: '查看', onTap: () {}, variant: AppButtonVariant.primary)));
    expect(shapeOf(tester).side, BorderSide.none);
  });

  testWidgets('border: false 可关掉 ghost 描边（纯图标 ghost 用）', (tester) async {
    await tester.pumpWidget(
      host(AppButton(label: '', icon: Icons.more_horiz, onTap: () {}, variant: AppButtonVariant.ghost, border: false)),
    );
    expect(shapeOf(tester).side, BorderSide.none);
  });

  testWidgets('真禁用态：描边降一档到 line（design.html .btn.off）', (tester) async {
    await tester.pumpWidget(
      host(const AppButton(label: '不可用', onTap: null, clickable: false, variant: AppButtonVariant.ghost)),
    );
    expect(shapeOf(tester).side.color, palette.line);
  });
}
