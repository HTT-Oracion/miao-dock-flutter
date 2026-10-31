@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import 'package:miao_dock_flutter/core/net/port_probe.dart';
import 'package:miao_dock_flutter/core/net/service_locator.dart';
import 'package:miao_dock_flutter/features/manga/data/http_manga_svc_client.dart';

/// P0-E3 真实故障注入：**服务停止后必须报错，不能返回空数据**。
///
/// 为什么这条必须真跑：如果连不上时返回空列表，UI 会画「书架是空的」——
/// 用户以为书没了，而实际只是服务没起。这比报错更糟（design.html §07）。
///
/// 前置：**服务未启动**（本文件断言的就是这个状态）。
/// 本文件的断言前提是「服务**未**启动」——与服务在线时跑的 e2e 互斥。
///
/// 服务在线时 **skip**（不是失败）：这条用例验的是「没服务时的行为」，
/// 有服务时它不适用。跳过会被测试框架显式报告。
bool _serviceUp = true;

void main() {
  setUpAll(() async {
    _serviceUp = (await const PortProbe().discover()) != null;
    if (_serviceUp) {
      // ignore: avoid_print
      print('⚠ 跳过 E3 离线用例：mangasvc 正在运行（本用例验的是「服务停止后」的行为）。');
    }
  });

  test('服务未启动 → 探测为 null，客户端抛 unreachable', skip: _serviceUp ? '服务正在运行' : null, () async {
    final baseUrl = await const PortProbe().discover();
    // 破坏点：探测在无服务时返回一个默认地址 → 后续请求变成 connection refused，
    // 错误类型丢失，UI 无法区分「没起」与「网络故障」，本条失败。
    expect(baseUrl, isNull, reason: '本测试要求 mangasvc 未运行');

    final c = HttpMangaSvcClient(LocalServiceLocator(probe: const PortProbe()));
    try {
      await c.listLibrary();
      fail('服务未启动时不得成功返回');
    } on MangaSvcException catch (e) {
      // 破坏点：抛 apiError / 返回空列表 → UI 会显示空态而非失败态，本条失败。
      expect(e.kind, MangaSvcErrorKind.unreachable);
    }
  });

  test('队列同样受影响（不是只有书架正确）', skip: _serviceUp ? '服务正在运行' : null, () async {
    final c = HttpMangaSvcClient(LocalServiceLocator(probe: const PortProbe()));
    try {
      await c.listTasks();
      fail('服务未启动时不得成功返回');
    } on MangaSvcException catch (e) {
      expect(e.kind, MangaSvcErrorKind.unreachable);
    }
  });
}
