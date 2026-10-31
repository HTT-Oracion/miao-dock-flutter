import 'dart:io';

import 'package:test/test.dart';

import 'package:mangasvc/src/engine/engine_deps.dart';

/// D-029：依赖重建（pip）—— 镜像优先、失败要看得懂。
void main() {
  late Directory tmp;
  late String engineDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('miao_deps_');
    engineDir = '${tmp.path}/engine';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// 造一个假的 python：把收到的参数打印出来，按 [exitCode] 退出。
  void makeFakePython({int exitCode = 0, String stderrText = ''}) {
    final py = File(enginePythonPathOf(engineDir));
    py.parent.createSync(recursive: true);
    final err = stderrText.isEmpty ? '' : 'echo "$stderrText" >&2\n';
    // 用 \$ 转义：Dart 字符串里 $@ 会被当成插值。
    py.writeAsStringSync(
      '#!/bin/sh\necho "ARGS: \$@"\n$err'
      'exit $exitCode\n',
    );
    Process.runSync('chmod', ['755', py.path]);
  }

  void makeRequirements() {
    final f = File('${engineSrcDirOf(engineDir)}${Platform.pathSeparator}requirements.txt');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('torch\n');
  }

  group('前置检查', () {
    test('解释器不存在 → 明确报错，不起进程', () async {
      makeRequirements();
      final r = await EngineDepsInstaller(engineDir: engineDir).rebuild();
      // 破坏点：没有解释器也往下走 → 抛一个看不懂的 ProcessException，本条失败。
      expect(r.ok, isFalse);
      expect(r.error, contains('解释器不存在'));
    });

    test('缺 requirements.txt → 明确报错并给出路径', () async {
      makeFakePython();
      final r = await EngineDepsInstaller(engineDir: engineDir).rebuild();
      // 破坏点：笼统报「安装失败」→ 用户不知道缺清单，本条失败。
      expect(r.ok, isFalse);
      expect(r.error, contains('requirements.txt'));
    });
  });

  group('镜像与参数', () {
    test('默认走国内镜像', () async {
      makeFakePython();
      makeRequirements();
      final r = await EngineDepsInstaller(engineDir: engineDir).rebuild();
      expect(r.ok, isTrue);
      final joined = r.log.join('\n');
      // 破坏点：默认走官方源 → 本网络下基本装不动，本条失败。
      expect(joined, contains(EngineDepsInstaller.defaultIndexUrl));
      expect(joined, contains('tuna.tsinghua.edu.cn'));
    });

    test('显式传镜像时用它', () async {
      makeFakePython();
      makeRequirements();
      final r = await EngineDepsInstaller(engineDir: engineDir).rebuild(indexUrl: 'https://mirror.example/simple');
      expect(r.log.join('\n'), contains('mirror.example'));
    });

    test('传空串表示不指定源（用 pip 默认）', () async {
      makeFakePython();
      makeRequirements();
      final r = await EngineDepsInstaller(engineDir: engineDir).rebuild(indexUrl: '');
      final joined = r.log.join('\n');
      // 破坏点：空串也拼 --index-url → pip 直接报参数错误，本条失败。
      expect(joined, isNot(contains('--index-url')));
      expect(joined, contains('默认源'));
    });

    test('把 -r requirements.txt 与 --progress-bar off 传给 pip', () async {
      makeFakePython();
      makeRequirements();
      final r = await EngineDepsInstaller(engineDir: engineDir).rebuild();
      final args = r.log.firstWhere((l) => l.startsWith('ARGS:'));
      // 破坏点：漏掉 -r → pip 装了个空，依赖仍然缺，本条失败。
      expect(args, contains('-r'));
      expect(args, contains('requirements.txt'));
      expect(args, contains('--progress-bar'));
    });
  });

  group('失败处理', () {
    test('pip 非零退出 → 失败并带出退出码与 stderr', () async {
      makeFakePython(exitCode: 2, stderrText: 'ERROR: No matching distribution found');
      makeRequirements();
      final r = await EngineDepsInstaller(engineDir: engineDir).rebuild();
      // 破坏点：非零也当成功 → 界面显示「依赖已就绪」，翻译时才炸，本条失败。
      expect(r.ok, isFalse);
      expect(r.error, contains('2'));
      expect(r.log.join('\n'), contains('No matching distribution'));
    });
  });
}
