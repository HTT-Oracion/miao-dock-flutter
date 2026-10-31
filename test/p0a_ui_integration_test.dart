@Tags(['e2e'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/queue_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// P0-A 的分层验证。
///
/// widget 层验证：注入固定替身，只验渲染与状态接线。
///
/// 🔴 真实 HTTP 的验证在 `p0a_transport_test.dart`：`TestWidgetsFlutterBinding`
/// 会拦截所有 HttpClient 并强制返回 400，**同一文件里只要出现 `testWidgets`**
/// 就会掐断整份 suite 的真实网络。两者必须分文件。
void main() {
  // ── widget 层：注入固定替身，只验渲染与接线 ───────────────────────────────

  group('队列屏渲染（注入替身）', () {
    testWidgets('真实数据形状能渲染到屏上', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final client = _FixedClient(
        TaskListResponse(
          count: 2,
          total: 5,
          running: 1,
          queued: 1,
          tasks: [
            _row('t-1', '未来回归', TaskStatus.running, 48, 16),
            _row('t-2', '星海航路', TaskStatus.partialFailed, 40, 37),
          ],
          updatedAt: DateTime(2026),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mangaSvcClientProvider.overrideWithValue(client)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: QueueScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 破坏点：controller 不做 DTO→domain 转换 → 屏上出现的是原始字段，断言失败。
      expect(find.text('未来回归'), findsWidgets);
      expect(find.text('星海航路'), findsWidgets);
    });
  });
}

TaskRow _row(String id, String name, TaskStatus status, int total, int done) => TaskRow(
  taskId: id,
  comicName: name,
  normalizedComicName: name,
  source: TaskSource.desktop,
  status: status,
  queuePosition: 0,
  progress: TaskProgress(total: total, done: done, failed: 0, current: 0),
  outputDir: '/tmp/x/$name',
  createdAt: DateTime(2026),
);

/// 固定返回值的替身（只覆盖本测试用到的端点）。
class _FixedClient extends FakeMangaSvcClient {
  _FixedClient(this._response) : super(seedTasks: 0);

  final TaskListResponse _response;

  @override
  Future<TaskListResponse> listTasks({TaskStatus? status, String? source}) async => _response;
}
