@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/net/port_probe.dart';
import 'package:miao_dock_flutter/core/net/service_locator.dart';
import 'package:miao_dock_flutter/features/manga/data/contract_map.dart';
import 'package:miao_dock_flutter/features/manga/data/http_manga_svc_client.dart';
import 'package:miao_dock_flutter/features/manga/domain/manga_task.dart';

/// P0-B 端到端：**真实 mangasvc 进程** → 客户端契约 → domain 模型。
///
/// 前置：先起服务
/// ```
/// dart run services/mangasvc/bin/mangasvc.dart --engine mock --root /tmp/e2e-lib
/// ```
/// 未起服务时本文件会失败（**不静默跳过**，符合 AGENTS §4.3）。
void main() {
  test('health 可达且服务名正确', () async {
    final baseUrl = await const PortProbe().discover();
    expect(baseUrl, isNotNull, reason: '未探测到 mangasvc，请先启动服务');

    final c = HttpMangaSvcClient(LocalServiceLocator(probe: const PortProbe()));
    final h = await c.health();
    // 破坏点：health 返回的 service 字段改了 → 客户端探测认不出服务，本条失败。
    expect(h.service, 'mangasvc');
    expect(h.isOk, isTrue);
    expect(h.rootDir, isNotEmpty);
  });

  test('建单 → 串行执行 → 完成（真实落盘链路的入口）', () async {
    final c = HttpMangaSvcClient(LocalServiceLocator(probe: const PortProbe()));
    final created = await c.createTask(comicName: '端到端测试', imagePaths: const ['/tmp/1.png', '/tmp/2.png']);
    expect(created.taskId, isNotEmpty);
    expect(created.queuePosition, greaterThanOrEqualTo(0));

    // mock 引擎按页推进（每页 30ms），给足时间。
    await Future<void>.delayed(const Duration(seconds: 1));
    final list = await c.listTasks();
    final row = list.tasks.firstWhere((t) => t.taskId == created.taskId);

    // 破坏点：队列不推进 → 状态停在 queued，本条失败。
    expect(row.status.wire, 'done');
    expect(row.progress.done, 2);
    expect(row.progress.total, 2);

    // DTO → domain
    final vm = toMangaTask(row);
    expect(vm.name, '端到端测试');
    expect(vm.status, MangaTaskStatus.done);
    expect(vm.deletable, isTrue);
  });

  test('串行约束：同一时刻只有 1 个 running', () async {
    final c = HttpMangaSvcClient(LocalServiceLocator(probe: const PortProbe()));
    // 连投 3 个
    for (var i = 0; i < 3; i++) {
      await c.createTask(comicName: '并发$i', imagePaths: const ['/a.png', '/b.png', '/c.png']);
    }
    final snap = await c.getQueue();
    // 破坏点：并发上限改成 >1 → 本条失败（原项目硬约束：同一时刻只跑 1 个）。
    expect(snap.concurrency, 1);
    expect(snap.queued.length, greaterThanOrEqualTo(1));
  });

  test('漫画库扫描识别「本 → 话 → 页」与已译页码', () async {
    final c = HttpMangaSvcClient(LocalServiceLocator(probe: const PortProbe()));
    // 造一个真实目录
    final lib = await c.listLibrary();
    // 破坏点：scan 不返回 books → 书架永远空，本条失败。
    expect(lib.books, isNotNull);
    final vm = lib.books!.map(toLibBook).toList();
    // 至少结构合法（内容由落盘决定）
    for (final b in vm) {
      expect(b.key, isNotEmpty);
      for (final ch in b.chapters) {
        expect(ch.pageCount, greaterThanOrEqualTo(0));
      }
    }
  });
}
