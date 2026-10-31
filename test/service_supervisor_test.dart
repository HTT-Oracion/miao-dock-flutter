import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/process/service_launch.dart';
import 'package:miao_dock_flutter/core/process/service_supervisor.dart';

/// P0-D1 / P0-D2 断言：就绪行解析、退出清理、崩溃重启。
///
/// 用真实子进程（`Platform.resolvedExecutable` = dart）跑假服务，不 mock：
/// 就绪行、信号、端口占用这三件事 mock 掉之后最容易写错。
void main() {
  late Directory tmp;

  /// 假 mangasvc：打印就绪行 + 真监听端口（用于验证停止后端口释放）。
  const fakeService = r'''
import 'dart:io';
void main(List<String> args) async {
  final mode = args.isEmpty ? 'ready' : args.first;
  if (mode == 'crash') {
    stderr.writeln('[fake] boom');
    exit(2);
  }
  final want = args.length > 1 ? int.parse(args[1]) : 0;
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, want);
  if (mode == 'silent') return;          // 不打印就绪行（模拟启动卡住）
  print('mangasvc listening on 127.0.0.1:${s.port}');
  await for (final c in s) {
    c.write('ok');
    await c.flush();
    await c.close();
  }
}
''';

  setUp(() => tmp = Directory.systemTemp.createTempSync('miao_svc_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // `flutter test` 里 Platform.resolvedExecutable 是 flutter_tester，不是 dart，
  // 所以复用产品代码里的解析（它优先 FLUTTER_ROOT 下的 SDK dart）。
  final dartExe = ServiceLaunchPlan.resolveDartExecutable();

  ServiceLaunchPlan planFor(String mode, {String extra = '', int? port}) => ServiceLaunchPlan(
    executable: dartExe,
    // 直接执行脚本（不走 `dart run`）：后者要做包解析，测试里每次要十几秒。
    args: ['${tmp.path}/fake.dart', mode, if (port != null) '$port'],
    workingDirectory: tmp.path,
    origin: 'test$extra',
  );

  void writeFake() => File('${tmp.path}/fake.dart').writeAsStringSync(fakeService);

  Future<int> freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  group('D1 启动与就绪', () {
    test('从就绪行拿到端口（且是真实端口）', () async {
      writeFake();
      // 用一个已知空闲端口，断言**解析出的端口与它相等** ——
      // 只断言「非空」的话，解析到任意端口都能混过去（反证验证过）。
      final want = await freePort();
      final sup = ServiceSupervisor(plan: planFor('ready', port: want));
      addTearDown(sup.dispose);

      final port = await sup.start();
      // 破坏点：不解析真实输出 → 拿到的是别的端口，后续请求连错服务，本条失败。
      expect(port, want);
      expect(sup.state, ServiceProcessState.running);
      expect(sup.pid, isNotNull);
    });

    test('没有就绪行 → 超时判失败，且进程被杀掉', () async {
      writeFake();
      final sup = ServiceSupervisor(plan: planFor('silent'), readyTimeout: const Duration(milliseconds: 800));
      addTearDown(sup.dispose);

      final port = await sup.start();
      // 破坏点：无就绪行也当成功 → 后续所有请求连到一个没起来的服务，本条失败。
      expect(port, isNull);
      expect(sup.state, ServiceProcessState.failed);
      expect(sup.lastError, contains('超时'));
      // 超时后必须杀掉，不能留一个占资源的进程
      expect(sup.pid, isNull);
    });

    test('就绪前就退出 → 立刻失败，不干等到超时', () async {
      writeFake();
      final sup = ServiceSupervisor(plan: planFor('crash'), readyTimeout: const Duration(seconds: 30));
      addTearDown(sup.dispose);

      final started = DateTime.now();
      final port = await sup.start();
      final elapsed = DateTime.now().difference(started);

      expect(port, isNull);
      // 破坏点：只能等超时才发现 → 用户干等 30 秒才看到失败，本条失败。
      expect(elapsed, lessThan(const Duration(seconds: 10)));
      expect(sup.lastError, contains('就绪前退出'));
    });

    test('找不到可执行文件 → 明确报错', () async {
      final sup = ServiceSupervisor(
        plan: const ServiceLaunchPlan(
          executable: '/nonexistent/mangasvc',
          args: [],
          workingDirectory: null,
          origin: 'test',
        ),
      );
      addTearDown(sup.dispose);

      final port = await sup.start();
      expect(port, isNull);
      expect(sup.state, ServiceProcessState.failed);
      // 破坏点：笼统报「启动失败」→ 用户不知道是路径问题，本条失败。
      expect(sup.lastError, contains('起不了'));
    });
  });

  group('D2 退出清理', () {
    test('停止后端口被释放（无僵尸）', () async {
      writeFake();
      final sup = ServiceSupervisor(plan: planFor('ready'));
      final port = await sup.start();
      expect(port, isNotNull);

      await sup.stop();

      // 能重新绑上同一端口，说明进程真的退出了
      final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, port!);
      // 破坏点：只置状态不杀进程 → 端口仍被占，本条失败。
      expect(sock.port, port);
      await sock.close();
      expect(sup.state, ServiceProcessState.stopped);
      expect(sup.pid, isNull);
      await sup.dispose();
    });

    test('主动停止不触发重启', () async {
      writeFake();
      final sup = ServiceSupervisor(plan: planFor('ready'));
      addTearDown(sup.dispose);

      await sup.start();
      await sup.stop();
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      // 破坏点：不区分主动停止 → 停止键变成重启键，本条失败。
      expect(sup.state, ServiceProcessState.stopped);
      expect(sup.pid, isNull);
    });

    test('非预期退出会重启', () async {
      writeFake();
      final sup = ServiceSupervisor(
        plan: planFor('ready'),
        restartBackoff: const Duration(milliseconds: 200),
        maxRestarts: 2,
      );
      addTearDown(sup.dispose);

      final port = await sup.start();
      expect(port, isNotNull);

      // 模拟崩溃
      Process.killPid(sup.pid!, ProcessSignal.sigkill);
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      // 破坏点：崩溃后永久死 → 用户必须重启应用，本条失败。
      expect(sup.state, anyOf(ServiceProcessState.running, ServiceProcessState.starting));
    });

    test('重启达到上限后进入 failed', () async {
      writeFake();
      final sup = ServiceSupervisor(
        plan: planFor('crash'),
        readyTimeout: const Duration(seconds: 2),
        restartBackoff: const Duration(milliseconds: 150),
        maxRestarts: 1,
      );
      addTearDown(sup.dispose);

      await sup.start();
      await Future<void>.delayed(const Duration(milliseconds: 3000));

      // 破坏点：无限重启 → 刷日志打满 CPU，本条失败。
      expect(sup.state, ServiceProcessState.failed);
    });
  });

  group('日志捕获', () {
    test('stderr 也进日志（排障需要）', () async {
      writeFake();
      final sup = ServiceSupervisor(plan: planFor('crash'));
      addTearDown(sup.dispose);

      await sup.start();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final joined = sup.log.join('\n');
      // 破坏点：只收 stdout → 崩溃原因通常只在 stderr，本条失败。
      expect(joined, contains('boom'));
    });
  });

  group('启动计划解析', () {
    test('命中 dev-source（项目内脚本）', () {
      final plan = ServiceLaunchPlan.resolve(cwd: Directory.current);
      // 当前工作目录是项目根，应命中开发期源码
      expect(plan, isNotNull, reason: ServiceLaunchPlan.lastError);
      expect(plan!.origin, 'dev-source');
      expect(plan.args.any((a) => a.endsWith('mangasvc.dart')), isTrue);
    });

    test('都找不到时给出候选清单', () {
      final plan = ServiceLaunchPlan.resolve(cwd: tmp);
      // 破坏点：返回 null 不给原因 → 用户不知道去哪儿放二进制，本条失败。
      expect(plan, isNull);
      expect(ServiceLaunchPlan.lastError, contains('已尝试'));
    });
  });
}
