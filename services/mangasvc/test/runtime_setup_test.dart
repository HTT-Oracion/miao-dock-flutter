import 'dart:io';

import 'package:test/test.dart';

import 'package:mangasvc/src/engine/runtime_setup.dart';

/// P0-C6a 断言：解包必须保留**可执行位**与**符号链接**。
///
/// 这两件事丢一个，Python venv 解出来就是「文件都在、但跑不起来」——
/// 症状极隐蔽，所以必须由断言钉死。
void main() {
  late Directory tmp;
  const setup = RuntimeSetup();

  setUp(() => tmp = Directory.systemTemp.createTempSync('miao_setup_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// 造一个带顶层目录的 tar.gz：内含可执行脚本 + 指向它的符号链接。
  Future<String> makeArchive({String topDir = 'bundle', bool nested = false}) async {
    final src = Directory('${tmp.path}/src')..createSync();
    final root = nested ? Directory('${src.path}/$topDir/inner') : Directory('${src.path}/$topDir');
    root.createSync(recursive: true);

    final exe = File('${root.path}/python');
    exe.writeAsStringSync('#!/bin/sh\necho ok\n');
    // 0755：可执行位
    Process.runSync('chmod', ['755', exe.path]);

    // 符号链接：venv/bin/python -> python（相对链接）
    Link('${root.path}/python-link').createSync('python');

    // 普通文件
    File('${root.path}/README').writeAsStringSync('runtime');

    final archive = '${tmp.path}/runtime.tar.gz';
    final strip = nested ? 2 : 1;
    final r = Process.runSync('tar', [
      '-czf',
      archive,
      if (strip > 1) ...['--transform', 's|^$topDir|$topDir|'],
      '-C',
      src.path,
      topDir,
    ]);
    expect(r.exitCode, 0, reason: '造归档失败：${r.stderr}');
    return archive;
  }

  group('格式与前置检查', () {
    test('归档不存在 → 明确报错，不静默成功', () async {
      final r = await setup.extract(archivePath: '${tmp.path}/nope.tar.gz', destDir: '${tmp.path}/out');
      // 破坏点：不存在也返回 ok → 上层以为装配好了，本条失败。
      expect(r.ok, isFalse);
      expect(r.error, contains('不存在'));
    });

    test('不支持的格式被拒绝', () async {
      final f = File('${tmp.path}/x.rar')..writeAsStringSync('x');
      final r = await setup.extract(archivePath: f.path, destDir: '${tmp.path}/out');
      // 破坏点：什么都往 tar 里塞 → 报一个看不懂的 tar 错误，本条失败。
      expect(r.ok, isFalse);
      expect(r.error, contains('不支持'));
    });
  });

  group('解包正确性', () {
    test('strip 1 层后内容直接落在目标目录', () async {
      final archive = await makeArchive();
      final out = '${tmp.path}/runtimes';
      final r = await setup.extract(archivePath: archive, destDir: out);

      expect(r.ok, isTrue, reason: r.error);
      // 破坏点：没 strip → 内容进了 runtimes/bundle/，运行时路径全对不上，本条失败。
      expect(File('$out/README').existsSync(), isTrue);
      expect(Directory('$out/bundle').existsSync(), isFalse);
    });

    test('可执行位被保留（0755）', () async {
      final archive = await makeArchive();
      final out = '${tmp.path}/runtimes';
      await setup.extract(archivePath: archive, destDir: out);

      final mode = Process.runSync('stat', ['-f', '%Lp', '$out/python']);
      // macOS / Linux 的 stat 参数不同，取不到就退到 test -x
      final executable = mode.exitCode == 0
          ? (mode.stdout.toString().trim().contains('7'))
          : Process.runSync('test', ['-x', '$out/python']).exitCode == 0;
      // 破坏点：用纯 Dart 解包丢 mode → venv 的 python 不可执行，本条失败。
      expect(executable, isTrue, reason: 'python 应保留可执行位');
    });

    test('符号链接被保留为链接（不是复制成普通文件）', () async {
      final archive = await makeArchive();
      final out = '${tmp.path}/runtimes';
      await setup.extract(archivePath: archive, destDir: out);

      // 破坏点：symlink 被解成普通文件 → 升级 python 后 venv 指向旧副本，本条失败。
      expect(FileSystemEntity.typeSync('$out/python-link', followLinks: false), FileSystemEntityType.link);
    });

    test('strip 过多导致空目录 → 报错而不是假的成功', () async {
      final archive = await makeArchive();
      final out = '${tmp.path}/runtimes';
      // 该归档只有 1 层，strip 2 会把内容全部剥掉
      final r = await setup.extract(archivePath: archive, destDir: out, stripComponents: 2);
      // 破坏点：空目录也报成功 → 用户看到「装配完成」但引擎永远起不来，本条失败。
      expect(r.ok, isFalse);
      expect(r.error, contains('为空'));
    });
  });

  group('原子性与失败隔离', () {
    test('解包失败时目标目录不被写入', () async {
      // 造一个损坏的归档
      final bad = File('${tmp.path}/bad.tar.gz')..writeAsBytesSync([1, 2, 3, 4]);
      final out = Directory('${tmp.path}/keep')..createSync();
      File('${out.path}/existing.txt').writeAsStringSync('keep me');

      final r = await setup.extract(archivePath: bad.path, destDir: out.path);
      expect(r.ok, isFalse);
      // 破坏点：失败前先清空目标目录 → 重跑时丢失已就绪部分，本条失败。
      expect(File('${out.path}/existing.txt').existsSync(), isTrue);
    });

    test('成功后不留临时目录', () async {
      final archive = await makeArchive();
      final out = '${tmp.path}/runtimes';
      await setup.extract(archivePath: archive, destDir: out);

      final leftovers = tmp.listSync().where((e) => e.path.contains('_extracting_')).toList();
      // 破坏点：临时目录残留 → 下次装配空间翻倍，本条失败。
      expect(leftovers, isEmpty);
    });

    test('覆盖同名文件（可重跑）', () async {
      final archive = await makeArchive();
      final out = Directory('${tmp.path}/runtimes')..createSync();
      File('${out.path}/README').writeAsStringSync('old');

      final r = await setup.extract(archivePath: archive, destDir: out.path);
      expect(r.ok, isTrue, reason: r.error);
      // 破坏点：rename 到已存在路径直接抛异常 → 装配不能重跑，本条失败。
      expect(File('${out.path}/README').readAsStringSync(), 'runtime');
    });
  });
}
