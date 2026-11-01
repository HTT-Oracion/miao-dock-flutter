import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mangasvc/src/server/http.dart';
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

  test('取首图：写入 cover.<嗅探扩展名> 并在 manifest 声明', () async {
    final dir = Directory('${root.path}/某书')..createSync();
    File('${dir.path}/manifest.json')
        .writeAsStringSync('{"schema":1,"title":"某书","author":"","cover":null,"episodes":[]}');
    final ch = Directory('${dir.path}/01_第1话')..createSync();
    // 真 PNG 头 + 内容：嗅探要能认出 png。
    // 嗅探要求 ≥12 字节（PNG 签名 8 + 至少 4）。
    File('${ch.path}/001.png').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D]);
    await store.writeCoverFromFirstChapter('某书');
    expect(File('${dir.path}/cover.png').existsSync(), isTrue);
    final m = jsonDecode(File('${dir.path}/manifest.json').readAsStringSync());
    // 破坏点：写了图片却忘了 manifest.cover → 扫描认不到封面。
    expect(m['cover'], 'cover.png');
  });

  test('非图片字节拒绝（不写出坏封面）', () async {
    final dir = Directory('${root.path}/某书')..createSync();
    File('${dir.path}/manifest.json')
        .writeAsStringSync('{"schema":1,"title":"某书","author":"","cover":null,"episodes":[]}');
    expect(
      () => store.writeCover('某书', Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<ServiceError>().having((e) => e.code, 'code', 'INVALID_IMAGE')),
    );
  });

  test('移除封面：删文件并清 manifest.cover', () async {
    final dir = Directory('${root.path}/某书')..createSync();
    File('${dir.path}/manifest.json')
        .writeAsStringSync('{"schema":1,"title":"某书","author":"","cover":"cover.png","episodes":[]}');
    File('${dir.path}/cover.png').writeAsBytesSync([1]);
    await store.deleteCover('某书');
    expect(File('${dir.path}/cover.png').existsSync(), isFalse);
    final m = jsonDecode(File('${dir.path}/manifest.json').readAsStringSync());
    // 破坏点：只删文件不清声明 → manifest 指向不存在的封面。
    expect(m.containsKey('cover'), isFalse);
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
