import 'dart:io';

import 'package:test/test.dart';

import 'package:mangasvc/src/engine/supervisor.dart';

/// P0-C6c 断言：spawn + 健康探针 + 崩溃退避重启。
///
/// 用真实的子进程跑（`Platform.resolvedExecutable` = dart），不 mock：
/// 健康探针走真 HTTP，退出与重启走真信号/真 exitCode ——
/// 这三件事恰恰是 mock 掉之后最容易写错的部分。
void main() {
  late Directory tmp;
  late String script;

  /// 假引擎脚本：三种模式（healthy / crash / slow）。
  const fakeEngine = r'''
import 'dart:io';
void main(List<String> args) async {
  final mode = args.isEmpty ? 'healthy' : args.first;
  if (mode == 'crash') {
    stderr.writeln('[fake] crashing now');
    exit(1);
  }
  if (mode == 'slow') {
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
  final port = int.parse(args.length > 1 ? args[1] : '0');
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
    tmp = Directory.systemTemp.createTempSync('miao_sup_');
    script = '${tmp.path}/fake_engine.dart';
    File(script).writeAsStringSync(fakeEngine);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  EngineSupervisor make(String mode, {int port = 0, int maxRestarts = 2}) => EngineSupervisor(
    processPath: Platform.resolvedExecutable,
    processArgs: ['run', script, mode, '$port'],
    healthUrl: 'http://127.0.0.1:$port/health',
    workingDirectory: tmp.path,
    healthTimeout: const Duration(seconds: 20),
    healthInterval: const Duration(milliseconds: 100),
    maxRestarts: maxRestarts,
    backoffBase: const Duration(milliseconds: 150),
  );

  /// 找一个空闲端口（避免与其他用例撞车）。
  Future<int> freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  group('健康探测', () {
    test('进程起来且能应答 /health 才算就绪', () async {
      final port = await freePort();
      final sup = make('healthy', port: port);
      addTearDown(sup.dispose);

      final ok = await sup.start();
      // 破坏点：只看 pid 不看 /health → 引擎没起来也被判就绪，本条失败。
      expect(ok, isTrue);
      expect(sup.state, SupervisorState.running);
      expect(sup.pid, isNotNull);
    });

    test('进程活着但不应答 /health → 超时判失败', () async {
      final port = await freePort();
      // 用 crash 模式但把健康地址指向一个没人监听的端口
      final sup = EngineSupervisor(
        processPath: Platform.resolvedExecutable,
        processArgs: ['run', script, 'slow', '$port'],
        healthUrl: 'http://127.0.0.1:${await freePort()}/health',
        workingDirectory: tmp.path,
        healthTimeout: const Duration(seconds: 2),
        healthInterval: const Duration(milliseconds: 100),
        maxRestarts: 0,
      );
      addTearDown(sup.dispose);

      final ok = await sup.start();
      // 破坏点：健康探测恒返回 true（或跳过）→ 超时也报就绪，本条失败。
      expect(ok, isFalse);
      expect(sup.state, SupervisorState.failed);
    });
  });

  group('崩溃重启', () {
    test('非预期退出会重启，且次数递增', () async {
      final sup = make('crash', maxRestarts: 2);
      addTearDown(sup.dispose);

      // crash 模式永远起不来；等退避重试跑完
      await sup.start();
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      // 破坏点：退出后不重启 → 引擎一崩就永久死，本条失败。
      expect(sup.restartCount, greaterThan(0));
    });

    test('超过上限后进入 failed，不再无限重试', () async {
      final sup = make('crash', maxRestarts: 2);
      addTearDown(sup.dispose);

      await sup.start();
      await Future<void>.delayed(const Duration(milliseconds: 3000));

      // 破坏点：无上限重启 → CPU 打满、日志刷爆，本条失败。
      expect(sup.restartCount, lessThanOrEqualTo(2));
      expect(sup.state, SupervisorState.failed);
    });

    test('退避时长随次数递增（不恒定立刻重试）', () async {
      final sup = make('crash', maxRestarts: 3);
      addTearDown(sup.dispose);

      await sup.start();
      await Future<void>.delayed(const Duration(milliseconds: 4000));

      final backoffLines = sup.log.where((l) => l.contains('后第')).toList();
      // 破坏点：固定间隔重试 → 确定性故障会在短时间内刷满日志，本条失败。
      expect(backoffLines.length, greaterThanOrEqualTo(2));
      final delays = backoffLines.map((l) => int.parse(RegExp(r'(\d+)ms').firstMatch(l)!.group(1)!)).toList();
      expect(delays.last, greaterThan(delays.first));
    });
  });

  group('主动停止', () {
    test('停止后不触发重启（停止键不能变重启键）', () async {
      final port = await freePort();
      final sup = make('healthy', port: port);
      addTearDown(sup.dispose);

      expect(await sup.start(), isTrue);
      await sup.stop();
      await Future<void>.delayed(const Duration(milliseconds: 800));

      // 破坏点：不区分主动停止 → 监督器立刻把进程拉回来，本条失败。
      expect(sup.restartCount, 0);
      expect(sup.state, SupervisorState.stopped);
      expect(sup.pid, isNull);
    });

    test('停止会真正结束子进程（端口可复用）', () async {
      final port = await freePort();
      final sup = make('healthy', port: port);
      await sup.start();
      await sup.stop();

      // 端口能再绑上，说明进程确实退出了（没留僵尸）
      final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      // 破坏点：只置状态不杀进程 → 端口仍被占用，本条失败。
      expect(sock.port, port);
      await sock.close();
    });
  });
}
