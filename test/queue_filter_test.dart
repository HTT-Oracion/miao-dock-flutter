import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/domain/manga_task.dart';
import 'package:miao_dock_flutter/features/manga/ui/queue_table.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// 队列筛选（方案 A）：来源/状态多选过滤逻辑与表格渲染。
void main() {
  MangaTask task(String id, MangaTaskSource source, MangaTaskStatus status) => MangaTask(
    id: id,
    name: '漫画-$id',
    source: source,
    status: status,
    pageCount: 10,
    donePages: 5,
    batchNo: 1,
    createdAt: DateTime(2026),
  );

  group('applyQueueFilter', () {
    final tasks = [
      task('1', MangaTaskSource.app, MangaTaskStatus.translating),
      task('2', MangaTaskSource.plugin, MangaTaskStatus.failed),
      task('3', MangaTaskSource.desktop, MangaTaskStatus.done),
    ];

    test('空筛选 = 全量透传（同一实例）', () {
      final out = applyQueueFilter(tasks, const QueueFilterState());
      expect(identical(out, tasks), isTrue);
    });

    test('来源筛选：只留插件端', () {
      final out = applyQueueFilter(tasks, const QueueFilterState(sources: {MangaTaskSource.plugin}));
      expect(out.map((t) => t.id), ['2']);
    });

    test('状态与来源组合：失败 × 插件端', () {
      final out = applyQueueFilter(
        tasks,
        const QueueFilterState(sources: {MangaTaskSource.plugin}, statuses: {MangaTaskStatus.failed}),
      );
      expect(out.map((t) => t.id), ['2']);
    });

    test('筛选后为空 → 空列表（UI 显示空态提示）', () {
      final out = applyQueueFilter(tasks, const QueueFilterState(statuses: {MangaTaskStatus.cancelled}));
      expect(out, isEmpty);
    });

    test('TaskSource 解析：服务端 wire 值 app/plugin 不再落 unknown', () {
      expect(TaskSource.parse('app'), TaskSource.app);
      expect(TaskSource.parse('plugin'), TaskSource.plugin);
      expect(TaskSource.parse('extension'), TaskSource.extension);
      expect(TaskSource.parse('desktop'), TaskSource.desktop);
    });
  });

  testWidgets('表格：来源列渲染徽标，勾选筛选后行被过滤', (tester) async {
    final tasks = [
      task('1', MangaTaskSource.app, MangaTaskStatus.translating),
      task('2', MangaTaskSource.plugin, MangaTaskStatus.failed),
    ];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // 先把筛选状态置为「只看插件端」，再挂上带两行任务的表格。
    container.read(queueFilterProvider.notifier).toggleSource(MangaTaskSource.plugin);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QueueTable(tasks: tasks)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 只剩插件端那行；本地来源的行被过滤掉。
    expect(find.text('漫画-2'), findsOneWidget);
    expect(find.text('漫画-1'), findsNothing);
    expect(find.text('插件端'), findsOneWidget);

    // 来源与状态两列的表头筛选触发器（Lucide filter 图标）都在。
    expect(find.byWidgetPredicate((w) => w is Icon && w.icon == LucideIcons.filter), findsNWidgets(2));
  });
}
