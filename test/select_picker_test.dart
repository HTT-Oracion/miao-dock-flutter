import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/app_picker.dart';
import 'package:miao_dock_flutter/shared/widgets/app_select.dart';
import 'package:miao_dock_flutter/shared/widgets/buttons.dart';

/// D-126：下拉统一到 M3 `MenuAnchor`；选项多时用可搜索选择器。
void main() {
  Widget wrap(Widget child) => ProviderScope(
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('AppSelect：菜单在按钮下方且选择生效', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    String picked = '';
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) => AppSelect<String>(
            value: '',
            width: 200,
            items: const [('a', '苹果'), ('b', '香蕉')],
            onChanged: (v) => setState(() => picked = v),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trigger = tester.getRect(find.text('苹果'));
    await tester.tap(find.text('苹果'));
    await tester.pumpAndSettle();

    // 破坏点：菜单盖住按钮 / 回到硬编码 offset 错位。
    expect(tester.getRect(find.text('香蕉')).top, greaterThan(trigger.center.dy));

    await tester.tap(find.text('香蕉'));
    await tester.pumpAndSettle();
    expect(picked, 'b');
  });

  testWidgets('showAppPicker：搜索过滤后可选中', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    String? picked;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (ctx) => AppButton(
            label: '打开选择器',
            onTap: () async {
              picked = await showAppPicker<String>(
                context: ctx,
                title: '选择漫画',
                searchHint: '搜索',
                emptyText: '没有匹配',
                items: const [('a', '苹果'), ('b', '香蕉'), ('c', '橙子')],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开选择器'));
    await tester.pumpAndSettle();

    // 选择器已打开：三项都在。
    expect(find.text('橙子'), findsOneWidget);

    // 搜索「香」→ 只剩香蕉。
    await tester.enterText(find.byType(TextField).first, '香');
    await tester.pumpAndSettle();
    expect(find.text('香蕉'), findsOneWidget);
    expect(find.text('橙子'), findsNothing);

    await tester.tap(find.text('香蕉'));
    await tester.pumpAndSettle();
    expect(picked, 'b');
  });
}
