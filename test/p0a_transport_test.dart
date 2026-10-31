@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import 'package:miao_dock_flutter/core/net/service_locator.dart';
import 'package:miao_dock_flutter/features/manga/data/http_manga_svc_client.dart';

/// 传输层验证：真实 socket → HTTP → 契约解析。
///
/// 🔴 本文件**只 import `package:test`**，不 import `flutter_test`。
/// `flutter_test` 的 binding 会拦截所有 HttpClient 并强制返回 400，
/// 一旦本文件里出现 `testWidgets`，整份 suite 的真实网络都会被掐断。
void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      Object? body;
      if (req.uri.path.endsWith('/tasks')) {
        body = {
          'count': 2,
          'total': 5,
          'running': 1,
          'queued': 1,
          'tasks': [
            {
              'taskId': 't-1',
              'comicName': '未来回归',
              'normalizedComicName': '未来回归',
              'source': 'desktop',
              'status': 'running',
              'queuePosition': 0,
              'progress': {'total': 48, 'done': 16, 'failed': 0, 'current': 17},
              'outputDir': '/tmp/x/未来回归',
              'createdAt': '2026-10-31T10:00:00Z',
              'finishedAt': null,
            },
            {
              'taskId': 't-2',
              'comicName': '星海航路',
              'source': 'extension',
              'status': 'partial_failed',
              'queuePosition': 2,
              'progress': {'total': 40, 'done': 37, 'failed': 3, 'current': 0},
              'outputDir': '/tmp/x/星海航路',
              'createdAt': '2026-10-31T09:00:00Z',
              'finishedAt': '2026-10-31T09:30:00Z',
            },
          ],
          'updatedAt': '2026-10-31T10:05:00Z',
        };
      }
      final res = req.response;
      if (body == null) {
        res.statusCode = 404;
        res.write(
          jsonEncode({
            'error': {'code': 'NOT_FOUND', 'message': 'no', 'details': <String, dynamic>{}},
          }),
        );
      } else {
        res.statusCode = 200;
        res.write(jsonEncode(body));
      }
      res.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('真实请求 → 契约解析：queueDepth 与下划线状态词表', () async {
    final client = HttpMangaSvcClient(RemoteServiceLocator(baseUrl: 'http://127.0.0.1:${server.port}'));
    final res = await client.listTasks();

    // 破坏点：queueDepth 改成 total → 期望 2 实得 5，本条失败。
    expect(res.total, 5);
    expect(res.queueDepth, 2);
    expect(res.tasks.length, 2);

    // 破坏点：契约词表不一致（用驼峰）→ partial_failed 解析抛错，本条失败。
    expect(res.tasks[1].status, TaskStatus.partialFailed);
    expect(res.tasks[1].status.wire, 'partial_failed');
    expect(res.tasks[0].status, TaskStatus.running);
  });

  test('错误信封解析出 code / status / kind', () async {
    final client = HttpMangaSvcClient(RemoteServiceLocator(baseUrl: 'http://127.0.0.1:${server.port}'));
    try {
      await client.getTranslateOptions(); // 未实现 → 404
      fail('应当抛异常');
    } on MangaSvcException catch (e) {
      // 破坏点：不解析错误信封 → code 为 null，本条失败。
      expect(e.code, 'NOT_FOUND');
      expect(e.statusCode, 404);
      expect(e.kind, MangaSvcErrorKind.apiError);
    }
  });
}
