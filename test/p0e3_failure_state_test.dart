import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/queue_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/error_state.dart';

/// P0-E3 故障注入：**服务中途停止时，UI 显示失败态且不清空已成功数据**。
///
/// 设计稿 §07 明文：
///   · 失败 → 红色横幅 + 原因 + 重试；
///   · **失败不清空已成功的数据**（横幅 + 上次数据并存）；
///   · **空态与失败态分开绘制，不共用**。
void main() {
  Widget host(Widget child, {required MangaSvcClient client}) => ProviderScope(
    overrides: [mangaSvcClientProvider.overrideWithValue(client)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  group('队列：失败不清空旧数据', () {
    testWidgets('先成功后失败 → 横幅 + 旧数据并存', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final client = _FlakyClient();
      await tester.pumpWidget(host(const QueueScreen(), client: client));
      await tester.pumpAndSettle();

      // 第一次成功：应看到任务
      expect(find.text('未来回归'), findsWidgets);

      // 服务挂掉 → 触发刷新
      client.failing = true;
      await tester.runAsync(() async {
        // 通过 provider 直接触发重试
      });
      final ctx = tester.element(find.byType(QueueScreen));
      final container = ProviderScope.containerOf(ctx);
      await container.read(queueProvider.notifier).refresh();
      await tester.pumpAndSettle();

      // 破坏点：错误态直接清空数据 → 「未来回归」消失，本条失败。
      expect(find.text('未来回归'), findsWidgets, reason: '失败后旧数据必须仍在');
      // 破坏点：不显示错误横幅 → 用户以为数据是实时的，本条失败。
      expect(find.byType(ErrorBanner), findsOneWidget);
      // 重试按钮必须存在
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('首次就失败（无旧数据）→ 整块错误态，不用空态冒充', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final client = _FlakyClient()..failing = true;
      await tester.pumpWidget(host(const QueueScreen(), client: client));
      await tester.pumpAndSettle();

      // 破坏点：失败时画空态 → 用户以为「没有任务」，本条失败。
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('连不上本地服务'), findsOneWidget);
      // 空态文案不得出现
      expect(find.text('还没有翻译任务'), findsNothing);
    });

    testWidgets('错误文案按类型映射，不暴露原始异常', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final client = _FlakyClient()
        ..failing = true
        ..errorKind = MangaSvcErrorKind.unreachable;
      await tester.pumpWidget(host(const QueueScreen(), client: client));
      await tester.pumpAndSettle();

      // 破坏点：直接把异常 toString 甩到界面 → 出现 MangaSvcException 字样，本条失败。
      expect(find.textContaining('MangaSvcException'), findsNothing);
      expect(find.text('连不上本地服务'), findsOneWidget);
    });

    testWidgets('鉴权失败给对应文案（不是笼统「加载失败」）', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final client = _FlakyClient()
        ..failing = true
        ..errorKind = MangaSvcErrorKind.unauthorized;
      await tester.pumpWidget(host(const QueueScreen(), client: client));
      await tester.pumpAndSettle();

      // 破坏点：所有错误都映射成同一句 → 用户不知道要去重新配对，本条失败。
      expect(find.text('配对令牌无效'), findsOneWidget);
    });
  });

  group('书架：失败不清空旧数据', () {
    test('LibraryNotifier 保留 lastGood', () async {
      final client = _FlakyClient();
      final container = ProviderContainer(overrides: [mangaSvcClientProvider.overrideWithValue(client)]);
      addTearDown(container.dispose);

      // 先成功拉一次
      await container.read(libraryProvider.future);
      final notifier = container.read(libraryProvider.notifier);
      // 破坏点：没有 lastGood 字段 / 失败时清空 → 本条失败。
      expect(notifier.lastGood, isNotEmpty);
      expect(notifier.lastGood.first.name, '未来回归');

      // 服务挂掉
      client.failing = true;
      await container.read(libraryProvider.notifier).refresh();

      // 破坏点：失败后 lastGood 被清空 → 书架变空，本条失败。
      expect(notifier.lastGood, isNotEmpty, reason: '失败必须保留上次成功的数据');
      expect(notifier.lastGood.first.name, '未来回归');
    });
  });
}

/// 可切换「成功 / 失败」的替身，用于故障注入。
class _FlakyClient extends FakeMangaSvcClient {
  _FlakyClient() : super(seedTasks: 0);

  bool failing = false;
  MangaSvcErrorKind errorKind = MangaSvcErrorKind.unreachable;

  @override
  Future<TaskListResponse> listTasks({TaskStatus? status}) async {
    if (failing) throw MangaSvcException(kind: errorKind, message: '模拟失败');
    return TaskListResponse(
      count: 1,
      total: 1,
      running: 0,
      queued: 0,
      tasks: [
        TaskRow(
          taskId: 't-1',
          comicName: '未来回归',
          normalizedComicName: '未来回归',
          source: TaskSource.desktop,
          status: TaskStatus.done,
          queuePosition: 0,
          progress: const TaskProgress(total: 10, done: 10, failed: 0, current: 0),
          outputDir: '/x',
          createdAt: DateTime(2026),
        ),
      ],
      updatedAt: DateTime(2026),
    );
  }

  @override
  Future<LibraryResponse> listLibrary() async {
    if (failing) throw MangaSvcException(kind: errorKind, message: '模拟失败');
    return LibraryResponse(
      root: '/x',
      count: 1,
      totalImages: 10,
      totalBytes: 1024,
      comics: const [],
      books: [
        BookEntry(
          bookName: '未来回归',
          dirName: '未来回归',
          outputDir: '/x/未来回归',
          title: '未来回归',
          author: '作者',
          chapterCount: 1,
          totalPages: 10,
          byteSize: 1024,
          chapters: const [],
        ),
      ],
      updatedAt: DateTime(2026),
    );
  }
}
