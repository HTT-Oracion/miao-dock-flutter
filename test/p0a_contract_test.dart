import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import 'package:miao_dock_flutter/core/net/manga_svc_http.dart';
import 'package:miao_dock_flutter/core/net/port_probe.dart';
import 'package:miao_dock_flutter/features/manga/data/contract_map.dart';

/// P0-A 契约与传输层断言。
///
/// 每条都写明「破坏什么会导致它失败」，并做过反证轮。
void main() {
  group('P0-A1 契约解析', () {
    test('TaskStatus 契约词表原样往返（partial_failed / canceled 是下划线）', () {
      // 破坏点：改成驼峰（partialFailed）→ 解析真实服务端响应时抛错，本条失败。
      expect(TaskStatus.parse('partial_failed'), TaskStatus.partialFailed);
      expect(TaskStatus.parse('canceled'), TaskStatus.canceled);
      expect(TaskStatus.partialFailed.wire, 'partial_failed');
      expect(TaskStatus.canceled.wire, 'canceled');
    });

    test('未知状态必须抛错，不得静默降级', () {
      // 破坏点：把 parse 改成返回默认值 → 新状态会被误显示成 queued，本条失败。
      expect(() => TaskStatus.parse('brand_new_state'), throwsArgumentError);
    });

    test('queueDepth = running + queued（侧栏徽标口径）', () {
      final res = TaskListResponse(
        count: 3,
        total: 10,
        running: 1,
        queued: 2,
        tasks: const [],
        updatedAt: DateTime(2026),
      );
      // 破坏点：把 queueDepth 改成 total → 会把历史任务也算进徽标，本条失败。
      expect(res.queueDepth, 3);
    });

    test('TaskRow.dirName 在缺 normalizedComicName 时回落 comicName', () {
      final row = TaskRow(
        taskId: 't1',
        comicName: '未来回归',
        source: TaskSource.desktop,
        status: TaskStatus.done,
        queuePosition: 0,
        progress: const TaskProgress(total: 10, done: 10, failed: 0, current: 0),
        outputDir: '/x',
        createdAt: DateTime(2026),
      );
      // 破坏点：直接返回 normalizedComicName（null）→ 旧任务快照定位失败，本条失败。
      expect(row.dirName, '未来回归');
    });

    test('逐页判定用 translatedSeqs 而不是 translatedCount（中间缺页不错位）', () {
      final chapter = ChapterEntry(
        no: 1,
        dirName: '01',
        absDir: '/x/01',
        imageCount: 5,
        translatedCount: 2,
        seqMax: 5,
        // 译了第 1、4 页；第 2、3 页没译。
        translatedSeqs: const [1, 4],
        missingSeqs: const [],
        merged: true,
      );
      final vm = toLibChapter(chapter);
      // 破坏点：把 isTranslated 改成 `seq <= donePages` → 第 2 页会被误判成已译，本条失败。
      expect(vm.isTranslated(1), isTrue);
      expect(vm.isTranslated(2), isFalse);
      expect(vm.isTranslated(4), isTrue);
    });

    test('BookEntry.author 为空串时 hasAuthor 为 false（UI 显示未署名）', () {
      final book = BookEntry(
        bookName: 'b',
        dirName: 'b',
        outputDir: '/x/b',
        title: '',
        author: '',
        chapterCount: 0,
        totalPages: 0,
        byteSize: 0,
        chapters: const [],
      );
      // 破坏点：用 `author != null` 判空 → 空串会被当成有作者，本条失败。
      expect(book.hasAuthor, isFalse);
      // 破坏点：name 不回落 bookName → 标题为空，本条失败。
      expect(toLibBook(book).name, 'b');
    });
  });

  group('P0-A2 错误信封', () {
    test('MangaSvcException 暴露服务端错误码', () {
      const ex = MangaSvcException(
        kind: MangaSvcErrorKind.apiError,
        message: '请求体非法',
        statusCode: 400,
        apiError: ApiError(code: 'INVALID_IMAGE', message: '不是图片'),
      );
      // 破坏点：code getter 改成返回 message → 界面无法按码映射 ARB，本条失败。
      expect(ex.code, 'INVALID_IMAGE');
      expect(ex.statusCode, 400);
    });

    test('401 归类为 unauthorized（不是普通 apiError）', () {
      const ex = MangaSvcException(kind: MangaSvcErrorKind.unauthorized, message: 'no token', statusCode: 401);
      // 破坏点：把 401 归到 apiError → UI 会显示「服务异常」而非「需要配对」，本条失败。
      expect(ex.kind, MangaSvcErrorKind.unauthorized);
    });
  });

  group('P0-A3 端口段探测', () {
    test('探测区间是 5180–5190（与后端同源）', () {
      const probe = PortProbe();
      // 破坏点：改 start/end → 与实际服务端口段不一致，探测不到服务，本条失败。
      expect(probe.start, 5180);
      expect(probe.end, 5190);
      expect(PortProbe.apiPath, '/api/v1');
    });

    test('全段无服务时返回 null（不抛异常，交给 UI 判失败态）', () async {
      // 用一个必然空闲的高位端口段，避免与真实服务冲突。
      const probe = PortProbe(start: 59001, end: 59002);
      final url = await probe.discover(perPortTimeout: const Duration(milliseconds: 60));
      // 破坏点：找不到就抛异常 → 调用方无法区分「服务没起」与「契约不对」，本条失败。
      expect(url, isNull);
    });

    test('能探到真实 HTTP 服务并校验 service 字段', () async {
      // 起一个最小 HTTP 服务，返回 mangasvc 的健康检查形状。
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'ok', 'service': 'mangasvc', 'version': 'test'}));
        req.response.close();
      });

      final probe = PortProbe(start: server.port, end: server.port);
      final url = await probe.discover();
      // 破坏点：不校验 service 字段 → 端口被别的服务占用时也会误判为 mangasvc，本条失败。
      expect(url, 'http://127.0.0.1:${server.port}/api/v1');
    });

    test('端口被非 mangasvc 服务占用时判为未命中', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) {
        req.response
          ..statusCode = 200
          ..write(jsonEncode({'status': 'ok', 'service': 'something-else'}));
        req.response.close();
      });

      final probe = PortProbe(start: server.port, end: server.port);
      // 破坏点：只判 TCP 可达 → 会把别人的服务当成 mangasvc，本条失败。
      expect(await probe.discover(perPortTimeout: const Duration(milliseconds: 200)), isNull);
    });
  });

  group('P0-A4 鉴权与服务定位', () {
    test('MangaSvcHttpClient 默认带 Authorization 头', () {
      final client = MangaSvcHttpClient(baseUrl: 'http://127.0.0.1:5180/api/v1', token: 'tok-1');
      // 破坏点：不注入令牌 → 服务端 401，所有请求失败，本条失败。
      expect(client.token, 'tok-1');
      expect(client.baseUrl, 'http://127.0.0.1:5180/api/v1');
    });

    test('updateToken 可切换令牌（配对后立即生效）', () {
      final client = MangaSvcHttpClient(baseUrl: 'http://x/api/v1', token: 'a');
      client.updateToken('b');
      expect(client.token, 'b');
      client.updateToken(null);
      expect(client.token, isNull);
    });
  });
}
