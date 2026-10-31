import 'dart:io';

import 'package:test/test.dart';

import 'package:mangasvc/src/engine/engine_facade.dart';
import 'package:mangasvc/src/server/http.dart';

/// P0-C1~C5 断言：引擎状态 / 选项 / 校验 / 下载暂停 / 卸载。
void main() {
  late Directory tmp;
  late String rt;
  late String models;
  late EngineFacade facade;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('miao_engine_');
    rt = '${tmp.path}/runtimes';
    models = '${tmp.path}/state/models-state';
    facade = EngineFacade(runtimeRoot: rt, modelsDir: models);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void assemble() {
    Directory('$rt/src').createSync(recursive: true);
    Directory('$rt/venv').createSync(recursive: true);
    File('$rt/src/version.txt').writeAsStringSync('0.9.1');
  }

  group('C1 引擎状态', () {
    test('初始为 stopped，且不假装 warmed', () {
      final s = facade.status();
      // 破坏点：初始就报 running → 界面显示「就绪」但根本没有进程，本条失败。
      expect((s['engine'] as Map)['state'], 'stopped');
      expect(s['warmed'], isFalse);
    });

    test('未装配时启动 → error 且给出缺失原因', () async {
      await facade.startEngine();
      final s = facade.status();
      // 破坏点：未装配也报 running → 用户以为能翻译，本条失败。
      expect((s['engine'] as Map)['state'], 'error');
      expect(s['lastError'], contains('未装配'));
    });

    test('装配齐全后版本可读（没装就是 null，不猜）', () {
      expect(facade.status()['engine']['version'], isNull);
      assemble();
      // 破坏点：版本写死 → 与真实安装不符，本条失败。
      expect(facade.status()['engine']['version'], '0.9.1');
    });

    test('runtime 探针逐项独立报真伪', () {
      final probe = facade.runtimeProbe();
      final checks = (probe["checks"] as List).cast<Map<String, dynamic>>();
      expect(checks.length, 3);
      // 破坏点：把三项合成一个布尔 → 用户不知道缺哪一项，本条失败。
      expect(checks.every((c) => c.containsKey('name')), isTrue);
      expect(checks.every((c) => c.containsKey('ok')), isTrue);
      expect(probe['ready'], isFalse);
      assemble();
      Directory(models).createSync(recursive: true);
      expect(facade.runtimeProbe()['ready'], isTrue);
    });
  });

  group('C2 引擎选项与设置', () {
    test('选项含方向 / 档位 / 加速后端', () {
      final o = facade.options();
      expect(o['translateDirections'], isNotEmpty);
      expect(o['tiers'], contains('auto'));
      expect(o['accels'], contains('cpu'));
    });

    test('未知设置项被拒绝（白名单）', () async {
      // 破坏点：接受任意键 → 用户配错的值写盘后下次启动崩，本条失败。
      expect(() => facade.applySettings({'bogusKey': 1}), throwsA(isA<ServiceError>()));
    });

    test('改 tier / accel 需要重启引擎', () async {
      final r = await facade.applySettings({'tier': 'high'});
      // 破坏点：needsRestart 恒 false → 用户改了设置但没生效也无提示，本条失败。
      expect(r['needsRestart'], isTrue);
      final r2 = await facade.applySettings({'idleUnloadMinutes': 10});
      expect(r2['needsRestart'], isFalse);
    });
  });

  group('C3 模型校验', () {
    test('目录不存在时如实报告路径', () async {
      final r = await facade.verifyModels();
      expect(r['ready'], isFalse);
      expect((r['missing'] as List).first.toString(), contains('models-state'));
    });

    test('目录为空时未就绪', () async {
      Directory(models).createSync(recursive: true);
      final r = await facade.verifyModels();
      expect(r['ready'], isFalse);
    });
  });

  group('C4 下载与暂停', () {
    test('下载可从 idle → running → interrupted', () async {
      final started = await facade.startDownload();
      expect(started['state'], 'running');
      final paused = await facade.pauseDownload();
      // 破坏点：暂停后状态回到 idle → 用户不知道下次能不能续传，本条失败。
      expect(paused['state'], 'interrupted');
    });

    test('无真实进度时 percent 为 null（不编造）', () async {
      final v = await facade.startDownload();
      // 破坏点：假造 0 或 100 → 与设计稿 §07「不编造进度数字」冲突，本条失败。
      expect(v['percent'], isNull);
    });

    test('下载会建 models 目录（支持后续续传）', () async {
      await facade.startDownload();
      expect(Directory(models).existsSync(), isTrue);
    });
  });

  group('C5 卸载', () {
    test('卸载只清 warmed，不停进程', () async {
      await facade.unload();
      // 破坏点：卸载把状态改成 stopped → 用户以为进程没了，本条失败。
      expect(facade.status()['engine']['state'], 'stopped');
      expect(facade.status()['warmed'], isFalse);
    });
  });
}
