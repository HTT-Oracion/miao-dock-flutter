import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:protocol/protocol.dart';

import 'package:mangasvc/src/engine/engine_install.dart';
import 'package:mangasvc/src/engine/engine_manifest_entry.dart';

/// P0-C6 / D-027：装配计划的挑选与真实落盘。
void main() {
  group('计划挑选（后端分化）', () {
    test('Windows x64 + Vulkan → vulkan 包，不是 cuda', () {
      final p = resolveInstallPlan(platformKey: 'win32-x64', backend: LlamaBackend.vulkan);
      final ids = p.entries.map((e) => e.id);
      // 破坏点：后端选了却仍下 CUDA → 无 N 卡机器上装了个跑不起来的后端，本条失败。
      expect(ids, contains('llama_cpp_win_vulkan_x64'));
      expect(ids, isNot(contains('llama_cpp_win_cuda_x64')));
    });

    test('Windows x64 + CUDA → 同时要 cudart（少一个就缺 DLL）', () {
      final p = resolveInstallPlan(platformKey: 'win32-x64', backend: LlamaBackend.cuda12);
      final ids = p.entries.map((e) => e.id);
      // 破坏点：只下 llama 不下 cudart → llama-server 启动即报缺 DLL，本条失败。
      expect(ids, containsAll(['llama_cpp_win_cuda_x64', 'cudart_win_cuda_x64']));
    });

    test('macOS arm64 不因后端选择而变', () {
      final a = resolveInstallPlan(platformKey: 'darwin-arm64', backend: LlamaBackend.auto);
      final b = resolveInstallPlan(platformKey: 'darwin-arm64', backend: LlamaBackend.vulkan);
      // 破坏点：macOS 也按后端挑 → 挑到不存在的包，本条失败。
      expect(a.entries.map((e) => e.id).toSet(), b.entries.map((e) => e.id).toSet());
      expect(a.entries.map((e) => e.id), contains('llama_cpp_macos_arm64'));
    });

    test('平台互斥：Windows 计划里不出现 darwin 条目', () {
      final p = resolveInstallPlan(platformKey: 'win32-x64', backend: LlamaBackend.cpu);
      // 破坏点：平台过滤失效 → 下一份外来二进制，装完跑不起来，本条失败。
      expect(p.entries.where((e) => e.platform == 'darwin-arm64'), isEmpty);
      expect(p.entries.where((e) => e.platform == 'linux-x64'), isEmpty);
    });

    test('nllb 默认不装，显式要求才装', () {
      final a = resolveInstallPlan(platformKey: 'darwin-arm64', backend: LlamaBackend.auto);
      final b = resolveInstallPlan(platformKey: 'darwin-arm64', backend: LlamaBackend.auto, includeNllb: true);
      // 破坏点：默认带上 nllb → 只做日译中也要多下 2.31 GB，本条失败。
      expect(a.entries.any((e) => e.set == 'translation'), isFalse);
      expect(b.entries.any((e) => e.set == 'translation'), isTrue);
    });

    test('macOS 计划体积在 4.7 GB 量级（不是 7 GB）', () {
      final p = resolveInstallPlan(platformKey: 'darwin-arm64', backend: LlamaBackend.auto);
      // 破坏点：误把 nllb 算进必装 → 体积翻倍，本条失败。
      expect(p.totalMb, greaterThan(4000));
      expect(p.totalMb, lessThan(6000));
    });
  });

  group('真实落盘', () {
    late Directory tmp;
    late HttpServer server;
    late String engineDir;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('miao_install_');
      engineDir = '${tmp.path}/engine';
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final name = req.uri.pathSegments.last;
        final f = File('${tmp.path}/serve/$name');
        if (!f.existsSync()) {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        req.response.headers.contentLength = f.lengthSync();
        req.response.add(f.readAsBytesSync());
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      tmp.deleteSync(recursive: true);
    });

    /// 造一个带顶层目录 `python/` 的 tar.gz。
    Future<File> makeArchive() async {
      final src = Directory('${tmp.path}/archive_src/python/bin')..createSync(recursive: true);
      File('${src.path}/python3').writeAsStringSync('#!/bin/sh\necho Python 3.11.10\n');
      Process.runSync('chmod', ['755', '${src.path}/python3']);
      final out = File('${tmp.path}/serve/py.tar.gz');
      Directory('${tmp.path}/serve').createSync(recursive: true);
      final r = Process.runSync('tar', ['-czf', out.path, '-C', '${tmp.path}/archive_src', 'python']);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return out;
    }

    Future<File> makeFile(String name, String content) async {
      Directory('${tmp.path}/serve').createSync(recursive: true);
      return File('${tmp.path}/serve/$name')..writeAsStringSync(content);
    }

    String urlOf(File f) => 'http://127.0.0.1:${server.port}/${f.uri.pathSegments.last}';

    test('归档条目 → 解到映射目录（python-3.11 → python）', () async {
      final arc = await makeArchive();
      final plan = EngineInstallPlan(
        platformKey: 'darwin-arm64',
        backend: LlamaBackend.auto,
        entries: [
          EngineManifestEntry(
            id: 'python',
            set: 'python',
            url: urlOf(arc),
            dest: '.download-cache/py.tar.gz',
            sha256: sha256.convert(arc.readAsBytesSync()).toString(),
            extractTo: 'python-3.11',
            extractStrip: 1,
          ),
        ],
      );

      final r = await EngineInstaller(engineDir: engineDir).install(plan);
      expect(r.ok, isTrue, reason: r.error);
      // 破坏点：解包目标没改写 → 落到 python-3.11/，部件校验找不到解释器，本条失败。
      expect(File('$engineDir/python/bin/python3').existsSync(), isTrue);
      expect(Directory('$engineDir/python-3.11').existsSync(), isFalse);
      // 归档留档（重试不重下）
      expect(File('$engineDir/.download-cache/py.tar.gz').existsSync(), isTrue);
    });

    test('普通条目 → 按前缀映射落到 src/models/ 与 llm/', () async {
      final model = await makeFile('detect.ckpt', 'MODEL');
      final gguf = await makeFile('s.gguf', 'GGUF');
      final plan = EngineInstallPlan(
        platformKey: 'darwin-arm64',
        backend: LlamaBackend.auto,
        entries: [
          EngineManifestEntry(
            id: 'detect',
            set: 'visual',
            url: urlOf(model),
            dest: 'models-store/detection/detect-20241225.ckpt',
            sha256: sha256.convert(model.readAsBytesSync()).toString(),
          ),
          EngineManifestEntry(
            id: 'sakura',
            set: 'llm',
            url: urlOf(gguf),
            dest: 'models/sakura/Sakura.gguf',
            sha256: sha256.convert(gguf.readAsBytesSync()).toString(),
          ),
        ],
      );

      final r = await EngineInstaller(engineDir: engineDir).install(plan);
      expect(r.ok, isTrue, reason: r.error);
      // 破坏点：映射写错 → 模型落到 models-store/ 或 models/sakura/，引擎读不到，本条失败。
      expect(File('$engineDir/src/models/detection/detect-20241225.ckpt').readAsStringSync(), 'MODEL');
      expect(File('$engineDir/llm/Sakura.gguf').readAsStringSync(), 'GGUF');
    });

    test('校验失败 → 不落盘并报错', () async {
      final f = await makeFile('bad.bin', 'DATA');
      final plan = EngineInstallPlan(
        platformKey: 'darwin-arm64',
        backend: LlamaBackend.auto,
        entries: [
          EngineManifestEntry(
            id: 'bad',
            set: 'visual',
            url: urlOf(f),
            dest: 'models-store/detection/x.ckpt',
            sha256: 'deadbeef',
          ),
        ],
      );

      final r = await EngineInstaller(engineDir: engineDir).install(plan);
      // 破坏点：哈希不符也接受 → 装进去一个坏模型，翻译时才炸，本条失败。
      expect(r.ok, isFalse);
      expect(r.error, contains('sha256'));
      expect(File('$engineDir/src/models/detection/x.ckpt').existsSync(), isFalse);
    });

    test('成功后写 .engine.json（含后端与条目）', () async {
      final f = await makeFile('a.bin', 'A');
      final plan = EngineInstallPlan(
        platformKey: 'win32-x64',
        backend: LlamaBackend.vulkan,
        entries: [EngineManifestEntry(id: 'a', set: 'visual', url: urlOf(f), dest: 'models-store/ocr/a.bin')],
      );

      await EngineInstaller(engineDir: engineDir).install(plan);
      final m = jsonDecode(File('$engineDir/.engine.json').readAsStringSync()) as Map;
      // 破坏点：不记录后端 → 「更换后端」时不知道当前装的是哪个，本条失败。
      expect(m['llamaBackend'], 'vulkan');
      expect(m['platformKey'], 'win32-x64');
      expect((m['entries'] as List).length, 1);
    });

    test('写 launch.json：入口是 server/main.py，健康检查用 openapi', () async {
      final f = await makeFile('a.bin', 'A');
      final plan = EngineInstallPlan(
        platformKey: 'darwin-arm64',
        backend: LlamaBackend.auto,
        entries: [EngineManifestEntry(id: 'a', set: 'visual', url: urlOf(f), dest: 'models-store/ocr/a.bin')],
      );
      await EngineInstaller(engineDir: engineDir).install(plan);

      final l = jsonDecode(File('$engineDir/launch.json').readAsStringSync()) as Map;
      final args = (l['args'] as List).cast<String>();
      // 破坏点：用 `-m manga_translator` 起 → 那是翻译子进程，HTTP API 不在那，
      // 客户端所有 /translate/* 都会 404，本条失败。
      expect(args.first.replaceAll('\\', '/'), contains('server/main.py'));
      expect(args, contains('--start-instance'));
      // 破坏点：健康检查用 /health → 上游没有该路由，探针永远失败，本条失败。
      expect(l['healthPath'], '/openapi.json');
      expect(l['port'], isA<int>());
      // 模型目录不在启动参数里（上游不支持，D-030）
      expect(args.join(' '), isNot(contains('--model-dir')));
    });
  });
}
