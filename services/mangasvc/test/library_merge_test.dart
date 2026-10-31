import 'dart:convert';
import 'dart:io';

import 'package:mangasvc/src/server/http.dart';
import 'package:mangasvc/src/store/library_store.dart';
import 'package:test/test.dart';

/// D-083：单话归并（对照旧项目 `library_merge` 守卫顺序与结果）。
void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lib-merge-test-');
    store = LibraryStore(rootDir: root.path, stateDir: '${root.path}/.miao-state');
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<void> makeBook(String name) async {
    await store.createBook(name);
  }

  test('归并成功：目录搬移 + 改号 + episodes 重派生（含小数话号）', () async {
    await makeBook('目标书');
    final src = Directory('${root.path}/某单话')..createSync();
    File('${src.path}/001.jpg').writeAsBytesSync([1]);
    File('${src.path}/cover.png').writeAsBytesSync([2]); // 单话封面应在归并前被清掉

    final r = await store.mergeBook(srcName: '某单话', targetBook: '目标书', no: 1.5);

    expect(r['merged']['from'], '某单话');
    expect(r['merged']['no'], 1.5);
    expect(r['merged']['removedCoverCount'], 1);
    // 目录按旧项目命名：小数**不补零**
    final dst = Directory('${root.path}/目标书/1.5_第1.5话');
    expect(dst.existsSync(), isTrue);
    expect(File('${dst.path}/001.jpg').existsSync(), isTrue);
    expect(File('${dst.path}/cover.png').existsSync(), isFalse);
    // manifest.episodes 重派生
    final manifest = jsonDecode(File('${root.path}/目标书/manifest.json').readAsStringSync());
    expect(manifest['episodes'], [
      {'no': 1.5, 'dir': '1.5_第1.5话'},
    ]);
  });

  test('守卫：源不存在 → TASK_NOT_FOUND', () async {
    await makeBook('目标书');
    expect(
      () => store.mergeBook(srcName: '没有', targetBook: '目标书', no: 1),
      throwsA(isA<ServiceError>().having((e) => e.code, 'code', 'TASK_NOT_FOUND')),
    );
  });

  test('守卫：源已是书 → ALREADY_MERGED', () async {
    await makeBook('源书');
    await makeBook('目标书');
    expect(
      () => store.mergeBook(srcName: '源书', targetBook: '目标书', no: 1),
      throwsA(isA<ServiceError>().having((e) => e.code, 'code', 'ALREADY_MERGED')),
    );
  });

  test('守卫：目标不是书 → TASK_NOT_FOUND（大类不存在）', () async {
    Directory('${root.path}/某单话').createSync();
    expect(
      () => store.mergeBook(srcName: '某单话', targetBook: '没这本书', no: 1),
      throwsA(isA<ServiceError>().having((e) => e.code, 'code', 'TASK_NOT_FOUND')),
    );
  });

  test('守卫：话号已被占 → CHAPTER_NO_TAKEN（目录与 episodes 双向查）', () async {
    await makeBook('目标书');
    Directory('${root.path}/某单话').createSync();
    await store.mergeBook(srcName: '某单话', targetBook: '目标书', no: 2);
    Directory('${root.path}/某单话2').createSync();
    expect(
      () => store.mergeBook(srcName: '某单话2', targetBook: '目标书', no: 2),
      throwsA(isA<ServiceError>().having((e) => e.code, 'code', 'CHAPTER_NO_TAKEN')),
    );
  });

  test('守卫：源上有活跃任务 → MERGE_SOURCE_BUSY', () async {
    await makeBook('目标书');
    Directory('${root.path}/某单话').createSync();
    expect(
      () => store.mergeBook(srcName: '某单话', targetBook: '目标书', no: 1, busyStatuses: const ['running']),
      throwsA(isA<ServiceError>().having((e) => e.code, 'code', 'MERGE_SOURCE_BUSY')),
    );
  });

  test('守卫：非法话号 → TASK_NOT_FOUND', () async {
    await makeBook('目标书');
    Directory('${root.path}/某单话').createSync();
    expect(
      () => store.mergeBook(srcName: '某单话', targetBook: '目标书', no: 1000),
      throwsA(isA<ServiceError>().having((e) => e.code, 'code', 'TASK_NOT_FOUND')),
    );
  });
}
