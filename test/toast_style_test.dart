import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/shared/widgets/toast.dart';

/// D-107：Toast 文字不能带下划线。
///
/// 背景：Toast 画在 Overlay 里，若没有 Material 祖先，Flutter 会渲染
/// 「黄色双下划线」提示缺少文本样式（用户截图实锤）。
void main() {
  testWidgets('toast 文字无 TextDecoration，且包在 Material 里', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => showAppToast(context, '测试提示'), child: const Text('show')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pump(const Duration(milliseconds: 400));

    final text = tester.widget<Text>(find.text('测试提示'));
    // 破坏点：去掉 Material → decoration 变成 underline（黄双线）。
    expect(text.style?.decoration, isNot(TextDecoration.underline));
    // 菜单/浮层里的文字必须有 Material 祖先。
    expect(find.ancestor(of: find.text('测试提示'), matching: find.byType(Material)), findsWidgets);

    // 让 toast 的自动关闭定时器跑完，避免 "Timer still pending"。
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
