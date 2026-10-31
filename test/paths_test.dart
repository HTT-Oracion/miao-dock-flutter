import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import 'package:miao_dock_flutter/core/storage/engine_inspect.dart';
import 'package:miao_dock_flutter/core/storage/paths.dart';

/// 目录约定与部件校验断言（D-027）。
///
/// 这些路径错一个，后果不是「界面难看」而是**用户数据找不到 / 引擎搬走就废**，
/// 所以每条都写清破坏点。
void main() {
  group('两棵树必须分开', () {
    test('漫画库不在数据根下（用户成果不得藏进 appData）', () {
      // 破坏点：把库放进 dataRoot → 卸载器会连用户译文一起删，本条失败。
      expect(mangaLibraryDir().startsWith(dataRoot()), isFalse);
    });

    test('漫画库默认在 Pictures 下', () {
      if (Platform.environment['MIAO_MANGA_LIBRARY_DIR'] == null) {
        // 破坏点：改回 `~/MiaoDock/library` → 主目录凭空多一个文件夹，本条失败。
        expect(mangaLibraryDir(), contains('Pictures'));
        expect(mangaLibraryDir(), endsWith('MiaoDock Mangas'));
      }
    });
  });

  group('引擎目录：一个可搬的根', () {
    test('engine 在数据根的 manga 下，且名为 engine', () {
      final e = mangaEngineDir();
      // 破坏点：仍叫 runtimes → 语义错（现在装的不只是 runtime），本条失败。
      expect(e.startsWith(dataRoot()), isTrue);
      expect(e, contains('manga'));
      expect(e, endsWith('engine'));
    });

    test('所有部件路径都在 engine 内（整体可搬的前提）', () {
      final e = mangaEngineDir();
      for (final p in [
        enginePythonDir(e),
        engineSrcDir(e),
        engineLlamaDir(e),
        engineModelsDir(e),
        engineLlmDir(e),
        engineManifestPath(e),
      ]) {
        // 破坏点：任一路径写到 engine 外 → 搬家时漏文件，本条失败。
        expect(p.startsWith(e), isTrue, reason: '$p 应在 $e 内');
      }
    });

    test('模型跟着 engine 走，不再挂 state（废止 D-016）', () {
      final models = engineModelsDir();
      // 破坏点：模型仍放 state/models-state → 导入别人的 engine 目录后模型仍缺，本条失败。
      expect(models.startsWith(mangaEngineDir()), isTrue);
      expect(models, endsWith('models'));
      expect(models.startsWith(mangaStateDir()), isFalse);
    });

    test('llm 与 models 平级，不混进 MIT 的 model_dir', () {
      // 破坏点：Sakura 放进 models/ → 与上游 model_dir 结构混在一起，升级引擎易踩坑，本条失败。
      expect(engineLlmDir().startsWith(engineModelsDir()), isFalse);
      expect(engineLlmDir(), endsWith('${Platform.pathSeparator}llm'));
    });

    test('解释器路径按平台分叉（pbs 在 Windows 是完整安装而非 venv）', () {
      final py = enginePythonPath('/tmp/e');
      if (Platform.isWindows) {
        // 破坏点：Windows 用 Scripts/python.exe → 那是 venv 布局，pbs 里不存在，本条失败。
        expect(py, endsWith('python${Platform.pathSeparator}python.exe'));
      } else {
        expect(py, endsWith('python${Platform.pathSeparator}bin${Platform.pathSeparator}python3'));
      }
    });
  });

  group('manifest 前缀映射', () {
    test('python-<版本> → python/', () {
      // 破坏点：保留版本号 → 升级 Python 后路径变，旧目录读不到，本条失败。
      expect(mapManifestDest('python-3.11/a/b'), 'python/a/b');
    });

    test('models-store → models/（MIT 的 model_dir）', () {
      expect(mapManifestDest('models-store/detection/d.ckpt'), 'models/detection/d.ckpt');
      expect(mapManifestDest('models-store/translators/nllb/x'), 'models/translators/nllb/x');
    });

    test('models/sakura → llm/（Sakura 归 llama-server）', () {
      // 破坏点：仍落 models/sakura → 与上游 model_dir 混放，本条失败。
      expect(mapManifestDest('models/sakura/s.gguf'), 'llm/s.gguf');
    });

    test('bin/llama/<版本> → bin/llama/（换后端路径不变）', () {
      // 破坏点：保留版本层 → 换后端后路径变，启动参数失效，本条失败。
      expect(mapManifestDest('bin/llama/llama-b11417/llama-server'), 'bin/llama/llama-server');
    });

    test('部件归属判定', () {
      expect(partOfManifestDest('models-store/detection/a.ckpt'), EnginePart.modelsVisual);
      expect(partOfManifestDest('models-store/translators/nllb/a.bin'), EnginePart.modelsNllb);
      expect(partOfManifestDest('models/sakura/s.gguf'), EnginePart.llm);
      expect(partOfManifestDest('bin/llama/llama-b11417/x'), EnginePart.llama);
      expect(partOfManifestDest('src/a.py'), EnginePart.source);
    });
  });

  group('长路径（Windows）', () {
    test('非 Windows 原样返回', () {
      if (!Platform.isWindows) {
        // 破坏点：在 macOS 上加 \\?\ → 部分系统调用会拒绝，本条失败。
        expect(longPath('/tmp/a/b'), '/tmp/a/b');
      }
    });
  });

  group('部件校验（结构级）', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('miao_eng_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    /// 造一个「齐全」的引擎目录（probePython: false 时不要求真解释器）。
    void buildComplete(String root) {
      final sep = Platform.pathSeparator;
      Directory('$root${sep}src${sep}manga_translator').createSync(recursive: true);
      File('$root${sep}src${sep}requirements.txt').writeAsStringSync('torch\n');
      Directory('$root${sep}bin${sep}llama').createSync(recursive: true);
      File('$root${sep}bin${sep}llama${sep}llama-server').writeAsStringSync('');
      for (final sub in ['detection', 'inpainting', 'ocr', 'fonts']) {
        Directory('$root${sep}models$sep$sub').createSync(recursive: true);
        File('$root${sep}models$sep$sub${sep}f.bin').writeAsStringSync('x');
      }
      Directory('$root${sep}llm').createSync(recursive: true);
      File('$root${sep}llm${sep}sakura.gguf').writeAsStringSync('gguf');
      File(enginePythonPath(root)).createSync(recursive: true);
    }

    test('空目录 → 必需部件全部报缺', () async {
      final r = await inspectEngine(tmp.path, probePython: false);
      // 破坏点：空目录也判通过 → 导入后翻译时才炸，本条失败。
      expect(r.ok, isFalse);
      expect(r.failedRequired.map((c) => c.part.id), containsAll(['src', 'llama', 'llm']));
    });

    test('齐全目录 → 通过；nllb 缺失不算失败', () async {
      buildComplete(tmp.path);
      final r = await inspectEngine(tmp.path, probePython: false);
      // 破坏点：把 nllb 当必需 → 只有日译中也要被迫下 2.31 GB，本条失败。
      expect(r.ok, isTrue, reason: r.logLines.join('\n'));
      final nllb = r.checks.firstWhere((c) => c.part == EnginePart.modelsNllb);
      expect(nllb.ok, isFalse);
      expect(nllb.part.required, isFalse);
    });

    test('缺 llm 权重 → 仅该部件失败，且日志带具体路径', () async {
      buildComplete(tmp.path);
      Directory('${tmp.path}${Platform.pathSeparator}llm').deleteSync(recursive: true);
      final r = await inspectEngine(tmp.path, probePython: false);
      expect(r.ok, isFalse);
      expect(r.failedRequired.map((c) => c.part.id), ['llm']);
      expect(r.logLines.join('\n'), contains('gguf'));
    });

    test('缺 .engine.json → 允许导入但标记未校验', () async {
      buildComplete(tmp.path);
      final r = await inspectEngine(tmp.path, probePython: false);
      // 破坏点：没有元数据就拒绝导入 → 别人从旧版拷来的目录永远导不进来，本条失败。
      expect(r.manifestMissing, isTrue);
      expect(r.logLines.join('\n'), contains('.engine.json'));
      expect(r.ok, isTrue);
    });

    test('有 .engine.json → 读出后端与版本', () async {
      buildComplete(tmp.path);
      File(engineManifestPath(tmp.path)).writeAsStringSync('{"engineVersion":"0.9.1","llamaBackend":"vulkan"}');
      final r = await inspectEngine(tmp.path, probePython: false);
      expect(r.version, '0.9.1');
      expect(r.llamaBackend, 'vulkan');
    });
  });

  group('后端枚举', () {
    test('不含 DirectML（llama.cpp 无该构建）', () {
      // 破坏点：加回 directml → 用户选了必然下载失败，本条失败。
      expect(LlamaBackend.values.map((b) => b.id), isNot(contains('directml')));
    });

    test('CUDA 固定 12.4', () {
      expect(LlamaBackend.values.map((b) => b.id), contains('cuda-12.4'));
      expect(LlamaBackend.values.map((b) => b.id), isNot(contains('cuda-13.4')));
    });

    test('体积量级：Vulkan 远小于 CUDA', () {
      // 破坏点：不写体积 → 用户不知道 20 倍差距，本条失败。
      expect(LlamaBackend.vulkan.approxMb, lessThan(LlamaBackend.cuda12.approxMb));
    });
  });
}
