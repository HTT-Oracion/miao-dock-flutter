import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/domain/lib_book.dart';
import 'package:miao_dock_flutter/features/manga/ui/shelf_menu.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 书架右键菜单断言（D-092）。
///
/// 项序与项集对照 miao-dock `renderComicMenu`：
/// 打开目录 / ─ / 继续翻译 / 重新翻译整本 / (编辑信息｜归并到…) / 删除。
void main() {
  const book = LibBook(key: '某书', name: '某书', author: '', chapters: [], totalBytes: 1);
  const chapter = LibBook(key: '某单话', name: '某单话', author: '', chapters: [], totalBytes: 1, isBook: false);

  Future<void> openFor(WidgetTester tester, LibBook b) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => ShelfContextMenu.show(context, ref, b, const Offset(100, 100)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('单本菜单：含编辑信息，不含归并', (tester) async {
    await openFor(tester, book);
    expect(find.text('打开目录'), findsOneWidget);
    expect(find.text('继续翻译'), findsOneWidget);
    expect(find.text('重新翻译整本'), findsOneWidget);
    expect(find.text('编辑信息'), findsOneWidget);
    // 破坏点：单本也出现「归并到…」→ 已经是一本书还能再被归并，语义错误。
    expect(find.text('归并到…'), findsNothing);
    expect(find.text('删除整本'), findsOneWidget);
  });

  testWidgets('单话菜单：含归并，不含编辑信息', (tester) async {
    await openFor(tester, chapter);
    expect(find.text('归并到…'), findsOneWidget);
    // 破坏点：单话出现「编辑信息」→ 单话没有 manifest，编辑会失败。
    expect(find.text('编辑信息'), findsNothing);
    expect(find.text('删除本话'), findsOneWidget);
  });
}
