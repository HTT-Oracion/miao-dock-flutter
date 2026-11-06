import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/shared/widgets/buttons.dart';
import 'package:miao_dock_flutter/features/manga/domain/manga_task.dart';
import 'package:miao_dock_flutter/features/manga/ui/queue_table.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 队列行主按钮断言（D-091）。
///
/// 规则（miao-dock `PrimaryAction`）：排队/进行中 → 取消；失败/部分失败 → 重试；终态 → 查看。
void main() {
  Widget harness(MangaTask task) => ProviderScope(
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: QueueRowActions(task: task)),
    ),
  );

  MangaTask make(MangaTaskStatus status) => MangaTask(
    id: 't1',
    name: '某漫画',
    source: MangaTaskSource.desktop,
    status: status,
    pageCount: 10,
    donePages: status == MangaTaskStatus.done ? 10 : 3,
    batchNo: 1,
    createdAt: DateTime(2026, 1, 1),
  );

  testWidgets('排队中 → 取消', (tester) async {
    await tester.pumpWidget(harness(make(MangaTaskStatus.queued)));
    await tester.pumpAndSettle();
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('查看'), findsNothing);
  });

  testWidgets('失败 → 重试（且高亮为主操作）', (tester) async {
    await tester.pumpWidget(harness(make(MangaTaskStatus.failed)));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    // 破坏点：失败行不给重试 → 用户只能干看着失败任务。
    expect(find.text('取消'), findsNothing);
  });

  testWidgets('部分失败 → 重试', (tester) async {
    await tester.pumpWidget(harness(make(MangaTaskStatus.partialFailed)));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('已完成 → 查看', (tester) async {
    await tester.pumpWidget(harness(make(MangaTaskStatus.done)));
    await tester.pumpAndSettle();
    expect(find.text('查看'), findsOneWidget);
  });

  testWidgets('已取消 → 继续（不是「打开」）', (tester) async {
    await tester.pumpWidget(harness(make(MangaTaskStatus.cancelled)));
    await tester.pumpAndSettle();
    // 破坏点：取消后给「打开」→ 用户没法续跑。
    expect(find.text('继续'), findsOneWidget);
    expect(find.text('打开'), findsNothing);
  });

  testWidgets('主按钮与「更多」**尺寸完全一致**（只允许颜色不同）', (tester) async {
    await tester.pumpWidget(harness(make(MangaTaskStatus.done)));
    await tester.pumpAndSettle();
    // 重设计稿：主按钮 24 高；⋯ 触发器 24×24（图标 14）—— 两者同高（同行不错位）。
    expect(tester.widget<AppButton>(find.widgetWithText(AppButton, '查看')).height, 24);
    final more = tester.getSize(
      find.ancestor(of: find.byIcon(LucideIcons.ellipsis), matching: find.byType(SizedBox)).first,
    );
    expect(more.height, 24);
    expect(more.width, 24);
  });

  testWidgets('更多菜单含打开目录与删除', (tester) async {
    await tester.pumpWidget(harness(make(MangaTaskStatus.done)));
    await tester.pumpAndSettle();
    // 「更多」用 M3 MenuAnchor：点开后菜单在 Overlay 里，需多 pump 一帧。
    await tester.tap(find.byIcon(LucideIcons.ellipsis));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('打开目录'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });
}
