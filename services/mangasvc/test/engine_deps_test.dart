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
      // 现在传给 pip 的是**清洗版**清单（D-035）。
      expect(args, contains('requirements'));
      expect(args, contains('--progress-bar'));
    });
  });

  group('清单清洗', () {
    void writeReqs(String body) {
      final f = File('${engineSrcDirOf(engineDir)}${Platform.pathSeparator}requirements.txt');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(body);
    }

    test('丢弃失效索引项，其余保留', () {
      writeReqs('torch\n--extra-index-url https://dead.example/simple/\npydensecrf@https://github.com/x/y.zip\n');
      final r = sanitizeRequirements(engineDir);
      expect(r.ok, isTrue);
      // 破坏点：保留 404 索引 → pip 直接失败，本条失败。
      expect(r.droppedIndexOptions, 1);
      final out = File(r.path!).readAsStringSync();
      expect(out, contains('torch'));
      expect(out, isNot(contains('dead.example')));
      // GitHub 直连默认保留（现在可达）
      expect(out, contains('pydensecrf@https://github.com/x/y.zip'));
    });

    test('给镜像前缀时改写直连地址', () {
      writeReqs('pydensecrf@https://github.com/x/y.zip\n');
      final r = sanitizeRequirements(engineDir, githubMirror: 'https://gh-proxy.example/');
      // 破坏点：镜像没生效 → 仍然直连 GitHub，弱网环境必失败，本条失败。
      expect(r.rewrittenUrls, 1);
      expect(File(r.path!).readAsStringSync(), contains('https://gh-proxy.example/https://github.com/x/y.zip'));
    });

    test('不改上游原文件（可对照排障）', () {
      writeReqs('torch\n--extra-index-url https://dead.example/simple/\n');
      sanitizeRequirements(engineDir);
      // 破坏点：直接改上游文件 → 出问题时分不清「我们的改动」和「上游内容」，本条失败。
      expect(
        File('${engineSrcDirOf(engineDir)}${Platform.pathSeparator}requirements.txt').readAsStringSync(),
        contains('dead.example'),
      );
    });

    test('rebuild 用清洗版清单（日志可见）', () async {
      makeFakePython();
      writeReqs('torch\n--extra-index-url https://dead.example/simple/\n');
      final r = await EngineDepsInstaller(engineDir: engineDir).rebuild();
      expect(r.ok, isTrue);
      final joined = r.log.join('\n');
      expect(joined, contains('清洗清单'));
      expect(joined, contains('requirements.miaodock.txt'));
    });

    test('缺清单时清洗失败并报路径', () {
      final r = sanitizeRequirements(engineDir);
      expect(r.ok, isFalse);
      expect(r.error, contains('requirements.txt'));
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
