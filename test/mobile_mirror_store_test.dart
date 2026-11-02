import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import 'package:miao_dock_flutter/core/net/manga_svc_http.dart';
import 'package:miao_dock_flutter/core/net/service_locator.dart';
import 'package:miao_dock_flutter/features/manga/data/http_manga_svc_client.dart';
import 'package:miao_dock_flutter/features/manga/data/mobile_mirror_store.dart';

class _OfflineLocator implements ServiceLocator {
  @override
  Future<MangaSvcHttpClient> client() =>
      throw const MangaSvcException(kind: MangaSvcErrorKind.unreachable, message: 'offline');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('miao_dock/test_mobile_mirror');
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('miao_mobile_mirror_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'appDataPath' ? root.path : null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    root.deleteSync(recursive: true);
  });

  test('队列、漫画索引与完整原/译图写入应用私有目录', () async {
    final store = MobileMirrorStore(channel: channel, forceEnabled: true);
    await store.saveQueue({'tasks': <dynamic>[]});
    await store.saveLibrary({'books': <dynamic>[]});
    final response = TaskListResponse(
      count: 1,
      total: 1,
      running: 0,
      queued: 0,
      updatedAt: DateTime(2026, 11, 2),
      tasks: [
        TaskRow(
          taskId: 'mobile-1',
          comicName: '手机漫画',
          normalizedComicName: '手机漫画',
          source: TaskSource.desktop,
          status: TaskStatus.done,
          queuePosition: 0,
          progress: const TaskProgress(total: 2, done: 2, failed: 0, current: 0),
          outputDir: '手机漫画',
          createdAt: DateTime(2026, 11, 2),
        ),
      ],
    );
    await store.syncCompletedTasks(response, (name, seq, translated) async => [seq, if (translated) 1 else 0]);

    expect(await store.loadQueue(), {'tasks': <dynamic>[]});
    expect(await store.loadLibrary(), {'books': <dynamic>[]});
    expect(await store.loadPage('手机漫画', 1, translated: false), [1, 0]);
    expect(await store.loadPage('手机漫画', 2, translated: true), [2, 1]);
    expect(Directory('${root.path}/synced').listSync(), isNotEmpty);
  });

  test('桌面端离线时队列、书架与页面回退手机镜像', () async {
    final store = MobileMirrorStore(channel: channel, forceEnabled: true);
    await store.saveQueue({
      'count': 1,
      'total': 1,
      'running': 0,
      'queued': 0,
      'updatedAt': '2026-11-02T00:00:00Z',
      'tasks': [
        {
          'taskId': 'cached-1',
          'comicName': '离线漫画',
          'normalizedComicName': '离线漫画',
          'source': 'desktop',
          'status': 'done',
          'queuePosition': 0,
          'progress': {'total': 1, 'done': 1, 'failed': 0, 'current': 0},
          'outputDir': '离线漫画',
          'createdAt': '2026-11-02T00:00:00Z',
        },
      ],
    });
    await store.saveLibrary({
      'root': root.path,
      'count': 0,
      'totalImages': 0,
      'totalBytes': 0,
      'comics': <dynamic>[],
      'books': <dynamic>[],
      'others': <dynamic>[],
      'updatedAt': '2026-11-02T00:00:00Z',
    });
    await store.savePage('离线漫画', 1, translated: true, bytes: const [9, 8, 7]);
    final client = HttpMangaSvcClient(_OfflineLocator(), mirror: store);

    expect((await client.listTasks()).tasks.single.comicName, '离线漫画');
    expect((await client.listLibrary()).count, 0);
    expect(await client.getBookFile('离线漫画', 1, translated: true), [9, 8, 7]);
  });
}
