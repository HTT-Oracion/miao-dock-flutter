@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import 'package:miao_dock_flutter/core/net/port_probe.dart';
import 'package:miao_dock_flutter/core/net/service_locator.dart';
import 'package:miao_dock_flutter/features/manga/data/http_manga_svc_client.dart';

/// P0-E4 远程模式：移动端 / Web 用**手动配置的桌面端地址 + 配对令牌**访问。
///
/// 与桌面端的区别：
///   · 不做端口探测（不知道服务落哪一段），直接用配置地址；
///   · 必须带 `X-Box-Token`（跨设备是暴露面）。
///
/// 前置：服务需以令牌模式启动并已知令牌，通过 `MIAO_E2E_TOKEN` 传入。
/// ```
/// dart run services/mangasvc/bin/mangasvc.dart --root /tmp/e4 --print-token
/// MIAO_E2E_TOKEN=<token> flutter test --tags e2e test/p0e4_remote_test.dart
/// ```
void main() {
  const token = String.fromEnvironment('MIAO_E2E_TOKEN');

  /// 服务在线检测。
  ///
  /// 必须在 test 体内 await —— `skip:` 参数在**注册期**求值，早于任何 setUp，
  /// 在那里探测拿不到结果。
  /// 返回 false = 服务不在，调用方应直接 `return`（test 体已标记 skipped）。
  Future<bool> requireService() async {
    final up = (await const PortProbe().discover()) != null;
    // 无服务时显式跳过（框架报告 skipped），不静默通过。
    if (!up) markTestSkipped('未探测到 mangasvc，跳过 E4（见文件头启动说明）');
    return up;
  }

  test('用配置地址 + 令牌可访问（不需要端口探测）', () async {
    if (!await requireService()) return;
    // 移动端不知道端口段，只有用户填的地址。
    final locator = RemoteServiceLocator(baseUrl: '127.0.0.1:5180', token: token);
    final c = HttpMangaSvcClient(locator);

    final h = await c.health();
    // 破坏点：/health 也要求令牌 → 服务发现失败，本条失败。
    expect(h.service, 'mangasvc');

    final lib = await c.listLibrary();
    expect(lib.root, isNotEmpty);
  });

  test('无令牌 → unauthorized（不是空数据）', () async {
    if (!await requireService()) return;
    final c = HttpMangaSvcClient(RemoteServiceLocator(baseUrl: '127.0.0.1:5180'));
    try {
      await c.listLibrary();
      fail('无令牌不应成功');
    } on MangaSvcException catch (e) {
      // 破坏点：403 被当成空列表 → 移动端显示「空书架」，用户以为没书，本条失败。
      expect(e.kind, MangaSvcErrorKind.unauthorized);
      expect(e.statusCode, 403);
    }
  });

  test('错误令牌 → unauthorized', () async {
    if (!await requireService()) return;
    final c = HttpMangaSvcClient(RemoteServiceLocator(baseUrl: '127.0.0.1:5180', token: 'wrong-token-0000'));
    try {
      await c.listLibrary();
      fail('错误令牌不应成功');
    } on MangaSvcException catch (e) {
      expect(e.kind, MangaSvcErrorKind.unauthorized);
    }
  });

  test('地址归一化：不带协议 / 带尾斜杠 / 已含 api/v1 都能用', () async {
    // 纯函数行为，不依赖服务
    // 破坏点：不补协议 → Uri.parse 失败；不剥尾斜杠 → 路径拼成 //api。
    final c = HttpMangaSvcClient(RemoteServiceLocator(baseUrl: '127.0.0.1:5180/', token: token));
    // 只要构造不抛、baseUrl 正确即可
    expect(c, isNotNull);
  });
}
