import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/domain/lib_book.dart';
import 'package:miao_dock_flutter/features/manga/ui/shelf_menu.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 漫画库交互断言（D-091）。
///
/// 这些用例驱动真实交互（点右键 → 菜单项、开删除框 → 勾选框状态），
/// 不是只断言静态渲染。
void main() {
  Widget harness(Widget child) => ProviderScope(
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(builder: (context) => child)),
    ),
  );

  const book = LibBook(key: '某书', name: '某书', author: '作者', chapters: [], totalBytes: 1024);

  testWidgets('删除弹窗：勾选框**默认不勾**（不勾＝隐藏，可恢复）', (tester) async {
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDeleteComicDialog(context, book: book),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final cb = tester.widget<Checkbox>(find.byType(Checkbox));
    // 破坏点：默认 true → 用户一确认就物理删了文件，与旧项目「默认最不破坏」相反。
    expect(cb.value, isFalse);
    expect(find.text('同时删除本地图片与译文文件'), findsOneWidget);
  });

  testWidgets('删除弹窗：勾上后确认返回 true（= 物理删除）', (tester) async {
    bool? result;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDeleteComicDialog(context, book: book);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    // 确认按钮文案是「删除整本」。
    await tester.tap(find.text('删除整本'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('归并对话框：未选目标书时确认按钮禁用', (tester) async {
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showMergeDialog(context, src: '某单话'),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '归并'));
    // 破坏点：允许空目标直接提交 → 服务端 404，用户看到无意义报错。
    expect(btn.onPressed, isNull);
  });
}
