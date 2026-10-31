@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/net/port_probe.dart';
import 'package:miao_dock_flutter/core/net/service_locator.dart';
import 'package:miao_dock_flutter/features/manga/data/http_manga_svc_client.dart';

/// P0-E1 端到端全链路：**投放 → 真实落盘 → 书架读回 → 续做计划**。
///
/// 前置：起服务
/// ```
/// dart run services/mangasvc/bin/mangasvc.dart --engine mock --root /tmp/e1-lib
/// ```
void main() {
  late HttpMangaSvcClient client;
  late Directory src;

  setUpAll(() async {
    client = HttpMangaSvcClient(LocalServiceLocator(probe: const PortProbe()));
    src = Directory.systemTemp.createTempSync('miao_e1_src_');
    for (var i = 1; i <= 3; i++) {
      File('${src.path}/0$i.png').writeAsBytesSync([i, i, i]);
    }
  });

  tearDownAll(() => src.deleteSync(recursive: true));

  test('E1 全链路：投放 → 落盘 → 读回', () async {
    final book = 'E1-${DateTime.now().millisecondsSinceEpoch}';
    final paths = List.generate(3, (i) => '${src.path}/0${i + 1}.png');

    final created = await client.createTask(comicName: book, imagePaths: paths);
    expect(created.taskId, isNotEmpty);

    // 等串行队列跑完（mock 每页 10ms + 调度）
    await Future<void>.delayed(const Duration(seconds: 2));

    final list = await client.listTasks();
    final row = list.tasks.firstWhere((t) => t.taskId == created.taskId);
    // 破坏点：队列不落盘 / 不推进 → 状态停在 queued，本条失败。
    expect(row.status.wire, 'done');
    expect(row.progress.done, 3);

    final lib = await client.listLibrary();
    final entry = lib.books?.where((b) => b.bookName == book).firstOrNull;
    // 破坏点：投放时不写 manifest → 本目录落进 others，书架看不到，本条失败。
    expect(entry, isNotNull, reason: '落盘后书架应能读回该本');
    expect(entry!.chapterCount, 1);
    expect(entry.totalPages, 3);

    final chapter = entry.chapters.single;
    // 破坏点：译文文件名后缀不规范 → 已译页码为空，本条失败。
    expect(chapter.translatedSeqs, [1, 2, 3]);
    expect(chapter.missingSeqs, isEmpty);
  });

  test('E1 续做计划：全译完后无待补页', () async {
    final lib = await client.listLibrary();
    final book = lib.books!.firstWhere((b) => b.bookName.startsWith('E1-'));
    final plan = await client.getChapterResumePlan(book.bookName, 1);
    // 破坏点：续做计划把已译页也算进去 → pendingCount > 0，本条失败。
    expect(plan.pendingCount, 0);
    expect(plan.translatedCount, 3);
  });
}
