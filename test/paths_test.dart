import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/storage/paths.dart';

/// 目录约定断言（D-015）。
///
/// 这些路径错一个，后果不是「界面难看」而是**用户数据找不到 / 卸载被删**，
/// 所以每条都写清破坏点。
void main() {
  group('两棵树必须分开', () {
    test('漫画库不在数据根下（用户成果不得藏进 appData）', () {
      final lib = mangaLibraryDir();
      final data = dataRoot();
      // 破坏点：把库放进 dataRoot → 卸载器会连用户译文一起删，本条失败。
      expect(lib.startsWith(data), isFalse, reason: '漫画库不得位于数据根内：$lib vs $data');
    });

    test('漫画库默认在 Pictures 下且名为 MiaoDock Mangas', () {
      // 仅在未被环境变量覆盖时校验默认值（CI 可能设了 MIAO_MANGA_LIBRARY_DIR）
      if (Platform.environment['MIAO_MANGA_LIBRARY_DIR'] == null) {
        // 破坏点：改回 `~/MiaoDock/library` → 主目录凭空多一个文件夹，本条失败。
        expect(mangaLibraryDir(), contains('Pictures'));
        expect(mangaLibraryDir(), endsWith('MiaoDock Mangas'));
      }
    });
  });

  group('引擎运行时结构', () {
    test('运行时根在数据根的 manga 子目录下', () {
      final rt = mangaRuntimeRoot();
      final data = dataRoot();
      // 破坏点：运行时挂到库目录下 → 换库位置会连带搬走数 GB 引擎，本条失败。
      expect(rt.startsWith(data), isTrue);
      expect(rt, contains('manga'));
      expect(rt, endsWith('runtimes'));
    });

    test('src 与 venv 挂在运行时根下（跟随用户选的目录）', () {
      final rt = mangaRuntimeRoot();
      // 破坏点：任一路径写死绝对位置 → 用户改选安装目录后失效，本条失败。
      expect(engineSrcDir(rt), startsWith(rt));
      expect(engineVenvDir(rt), startsWith(rt));
      expect(engineSrcDir(rt), endsWith('src'));
      expect(engineVenvDir(rt), endsWith('venv'));
    });

    test('模型目录挂在 state 下，**不跟随**运行时（D-016 刻意偏离原项目）', () {
      final models = modelsStoreDir();
      // 破坏点：把模型放回 runtimes 下 → 导入本地 / 换盘时数 GB 模型要重下，本条失败。
      expect(models.startsWith(mangaStateDir()), isTrue, reason: '模型应在 state 下');
      expect(models.endsWith('models-state'), isTrue);
      expect(models.startsWith(mangaRuntimeRoot()), isFalse, reason: '模型不得挂在运行时下');
    });

    test('解释器路径按平台分叉', () {
      final py = enginePythonPath('/tmp/rt');
      if (Platform.isWindows) {
        // 破坏点：Windows 用 bin/python → 找不到解释器，本条失败。
        expect(py, contains('Scripts'));
        expect(py, endsWith('python.exe'));
      } else {
        expect(py, contains('bin'));
        expect(py, endsWith('python'));
      }
    });
  });

  group('浅检查（非完整性校验）', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('miao_paths_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('空目录报告缺 src 与 venv', () {
      // 破坏点：把「目录存在」当成「安装完整」→ 用户导入空目录也能通过，本条失败。
      final missing = inspectRuntimeDir(tmp.path);
      expect(missing, contains('src'));
      expect(missing, contains('venv'));
    });

    test('src + venv 齐全时浅检查通过', () {
      Directory('${tmp.path}${Platform.pathSeparator}src').createSync();
      Directory('${tmp.path}${Platform.pathSeparator}venv').createSync();
      // models-store 允许缺失（首次下载后再建）
      expect(inspectRuntimeDir(tmp.path), isEmpty);
    });

    test('目录不存在时明确报告', () {
      expect(inspectRuntimeDir('${tmp.path}/nope'), contains('runtime-root'));
    });
  });
}
