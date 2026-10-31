import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:mangasvc/src/engine/engine_facade.dart';
import 'package:mangasvc/src/engine/engine_launch.dart';

/// P0-C6 接线断言：启动规格 → 监督器 → 真实子进程 → 状态机。
///
/// 这一组是「模块拼起来还对不对」的验证 —— C6a~C6d 各自的单测都过，
/// 不代表接进状态机后还能起来。
void main() {
  late Directory tmp;
  late String rt;
  late String models;

  const fakeEngine = r'''
import 'dart:io';
void main(List<String> args) async {
  final port = int.parse(args[0]);
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('[fake] listening ${s.port}');
  await for (final req in s) {
    req.response.statusCode = 200;
    req.response.write('ok');
    await req.response.close();
  }
}
''';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('miao_launch_');
    rt = '${tmp.path}/runtimes';
    models = '${tmp.path}/state/models-state';
    Directory('$rt/src').createSync(recursive: true);
    Directory('$rt/venv').createSync(recursive: true);
    File('$rt/src/version.txt').writeAsStringSync('1.2.3');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<int> freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  void writeSpec({required String command, required int port, List<String> args = const []}) {
    File('$rt/launch.json')
        .writeAsStringSync(jsonEncode({'command': command, 'args': args, 'healthPath': '/health', 'port': port}));
  }

  group('启动规格', () {
    test('缺 launch.json → 报出确切路径', () {
      final r = EngineLaunchSpec.load(rt);
      // 破坏点：返回 null 不给原因 → 用户不知道要准备什么，本条失败。
      expect(r.ok, isFalse);
      expect(r.error, contains('launch.json'));
    });

    test('缺 port → 报错不猜端口', () {
      File('$rt/launch.json').writeAsStringSync(jsonEncode({'command': 'x', 'healthPath': '/health'}));
      final r = EngineLaunchSpec.load(rt);
      expect(r.ok, isFalse);
      expect(r.error, contains('port'));
    });

    test('端口越界被拒绝', () {
      writeSpec(command: Platform.resolvedExecutable, port: 99999);
      final r = EngineLaunchSpec.load(rt);
      expect(r.ok, isFalse);
      expect(r.error, contains('port'));
    });

    test('可执行文件不存在 → 现在就报，不等 spawn 失败', () {
      writeSpec(command: '$rt/venv/bin/python-does-not-exist', port: 5000);
      final r = EngineLaunchSpec.load(rt);
      // 破坏点：拖到 spawn 才报 → 错误变成笼统的「启动失败」，本条失败。
      expect(r.ok, isFalse);
      expect(r.error, contains('不存在'));
    });

    test('相对 command 按 runtimeRoot 解析', () {
      Directory('$rt/venv/bin').createSync(recursive: true);
      File('$rt/venv/bin/python').writeAsStringSync('#!/bin/sh\n');
      writeSpec(command: 'venv/bin/python', port: 5190);
      final r = EngineLaunchSpec.load(rt);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.spec!.command, '$rt/venv/bin/python');
    });
  });

  group('状态机接线（真实子进程）', () {
    test('装配齐全 + 规格正确 → engine.state 变 running', () async {
      final port = await freePort();
      final script = '${tmp.path}/fake.dart';
      File(script).writeAsStringSync(fakeEngine);
      writeSpec(command: Platform.resolvedExecutable, port: port, args: ['run', script, '$port']);

      final facade = EngineFacade(runtimeRoot: rt, modelsDir: models);
      addTearDown(facade.dispose);

      final s = await facade.startEngine();
      // 破坏点：接线后仍返回旧的「未实现」错误 → 本条失败。
      expect((s['engine'] as Map)['state'], 'running', reason: '${s['lastError']}');
      expect((s['engine'] as Map)['pid'], isNotNull);
      expect((s['engine'] as Map)['port'], port);
    });

    test('停止后回到 stopped 且进程真的没了', () async {
      final port = await freePort();
      final script = '${tmp.path}/fake.dart';
      File(script).writeAsStringSync(fakeEngine);
      writeSpec(command: Platform.resolvedExecutable, port: port, args: ['run', script, '$port']);

      final facade = EngineFacade(runtimeRoot: rt, modelsDir: models);
      addTearDown(facade.dispose);

      await facade.startEngine();
      final s = await facade.stopEngine();
      expect((s['engine'] as Map)['state'], 'stopped');
      // 端口能重绑，说明进程确实退出（无僵尸）
      final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await sock.close();
    });

    test('健康地址指错 → error 且带出「未能就绪」', () async {
      final port = await freePort();
      final wrongPort = await freePort();
      final script = '${tmp.path}/fake.dart';
      File(script).writeAsStringSync(fakeEngine);
      // 启动的进程监听 port，但规格声明的健康端口是 wrongPort
      File('$rt/launch.json').writeAsStringSync(
        jsonEncode({
          'command': Platform.resolvedExecutable,
          'args': ['run', script, '$port'],
          'healthPath': '/health',
          'port': wrongPort,
        }),
      );

      final facade = EngineFacade(runtimeRoot: rt, modelsDir: models, healthTimeout: const Duration(seconds: 2));
      addTearDown(facade.dispose);
      final s = await facade.startEngine();
      // 破坏点：健康探测失败仍报 running → 用户点翻译必然超时，本条失败。
      expect((s['engine'] as Map)['state'], 'error');
      expect(s['lastError'], contains('未能'));
    });
  });

  group('manifest 驱动下载（真实 HTTP）', () {
    late HttpServer server;
    late List<int> payload;

    tearDown(() async => server.close(force: true));

    test('按清单下载并校验 sha256', () async {
      payload = List<int>.generate(8192, (i) => i % 251);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.headers.contentLength = payload.length;
        req.response.add(payload);
        await req.response.close();
      });

      Directory(models).createSync(recursive: true);
      File('$models/manifest.json').writeAsStringSync(
        jsonEncode({
          'files': [
            {
              'url': 'http://127.0.0.1:${server.port}/m.bin',
              'dest': 'm.bin',
              'sha256': sha256.convert(payload).toString(),
            },
          ],
        }),
      );

      final facade = EngineFacade(runtimeRoot: rt, modelsDir: models);
      addTearDown(facade.dispose);
      await facade.startDownload();
      // 等后台下载跑完（单文件很小）
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (facade.downloader.state != DownloadState.running) break;
      }

      // 破坏点：清单解析后不真下 → 文件不存在，本条失败。
      expect(File('$models/m.bin').existsSync(), isTrue);
      expect(File('$models/m.bin').readAsBytesSync(), payload);
      expect(facade.downloader.state, DownloadState.done);
      // 进度来自真实文件数，不是编造的
      expect(facade.downloader.view()['total'], 1);
    });
  });
}
