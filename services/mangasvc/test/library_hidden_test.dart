import 'dart:io';

import 'package:mangasvc/src/store/library_store.dart';
import 'package:test/test.dart';

/// D-082：隐藏机制（miao-dock `library_delete` + `hide_comic` 语义）。
void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lib-hidden-test-');
    store = LibraryStore(rootDir: root.path, stateDir: '${root.path}/.miao-state');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('deleteFiles=false → 目录保留、进隐藏清单、落盘 hidden-comics.json', () async {
    final dir = Directory('${root.path}/某漫画')..createSync();
    File('${dir.path}/001.jpg').writeAsBytesSync([1]);

    final r = await store.deleteBook('某漫画', deleteFiles: false);
    expect(r['deletedFiles'], false);
    expect(dir.existsSync(), isTrue); // 目录还在（隐藏 ≠ 删除）

    final hidden = store.hiddenList;
    expect(hidden, contains('某漫画'));
    // 落盘持久化（重启后仍隐藏）
    expect(File('${root.path}/.miao-state/hidden-comics.json').existsSync(), isTrue);
  });

  test('deleteFiles=true → 物理删除并清隐藏记录', () async {
    final dir = Directory('${root.path}/某漫画')..createSync();
    File('${dir.path}/001.jpg').writeAsBytesSync([1]);
    await store.deleteBook('某漫画', deleteFiles: false);
    final r = await store.deleteBook('某漫画', deleteFiles: true);
    expect(r['deletedFiles'], true);
    expect(dir.existsSync(), isFalse);
    expect(store.hiddenList, isEmpty);
  });

  test('unhide → 移出隐藏清单并落盘', () async {
    await store.deleteBook('某漫画', deleteFiles: false);
    await store.unhide('某漫画');
    expect(store.hiddenList, isEmpty);
  });

  test('重复隐藏不重复入列', () async {
    await store.deleteBook('某漫画', deleteFiles: false);
    await store.deleteBook('某漫画', deleteFiles: false);
    expect(store.hiddenList, ['某漫画']);
  });
}
