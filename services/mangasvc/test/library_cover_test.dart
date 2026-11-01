import 'dart:io';

import 'package:mangasvc/src/store/library_store.dart';
import 'package:test/test.dart';

/// D-085：封面规则（B.7）。
void main() {
  late Directory root;
  late LibraryStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lib-cover-test-');
    store = LibraryStore(rootDir: root.path, stateDir: '${root.path}/.miao-state');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('单话（无 manifest）：封面默认第一页，且优先译文', () async {
    final dir = Directory('${root.path}/某单话')..createSync();
    File('${dir.path}/001.png').writeAsBytesSync([1, 1, 1]);
    File('${dir.path}/002.png').writeAsBytesSync([2, 2, 2]);
    File('${dir.path}/001_translated.png').writeAsBytesSync([9, 9, 9]);

    // 破坏点：拿原图或拿第二页 → 字节不等于 9。
    expect(await store.readCover('某单话'), [9, 9, 9]);
  });

  test('单话无译文：回退第一页原图', () async {
    final dir = Directory('${root.path}/某单话')..createSync();
    File('${dir.path}/001.png').writeAsBytesSync([1]);
    File('${dir.path}/002.png').writeAsBytesSync([2]);
    expect(await store.readCover('某单话'), [1]);
  });

  test('单本：没有 cover.* 就不给封面（不拿章节首图冒充）', () async {
    final dir = Directory('${root.path}/某本')..createSync();
    File('${dir.path}/manifest.json')
        .writeAsStringSync('{"schema":1,"title":"某本","author":"","cover":null,"episodes":[]}');
    final ch = Directory('${dir.path}/01_第1话')..createSync();
    File('${ch.path}/001.png').writeAsBytesSync([7]);
    // 破坏点：单本回退章节首图 → 本条会拿到 [7]。
    expect(await store.readCover('某本'), isNull);
  });

  test('单本：cover.png 优先于一切', () async {
    final dir = Directory('${root.path}/某本')..createSync();
    File('${dir.path}/manifest.json')
        .writeAsStringSync('{"schema":1,"title":"某本","author":"","cover":null,"episodes":[]}');
    File('${dir.path}/cover.png').writeAsBytesSync([5]);
    final ch = Directory('${dir.path}/01_第1话')..createSync();
    File('${ch.path}/001.png').writeAsBytesSync([7]);
    expect(await store.readCover('某本'), [5]);
  });
}
