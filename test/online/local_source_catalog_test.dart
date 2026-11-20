import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/manga/online/data/source_import.dart';
import 'package:miao_dock_flutter/shared/domain/source_library.dart';

/// 本地源仓库（`index.json`）导入：用户实测「选 miao-dock-sources/manga/index.json
/// 提示 source.json 不是有效 JSON」——旧实现把所有 .json 都当单源清单解析。
///
/// 破坏点（修复前）：本地 JSON 一律走 `SourceImporter.importManifest`（source.json
/// 格式）→ 数组仓库直接 FormatException → 弹「source.json 不是有效 JSON」，仓库装不进来。
void main() {
  /// 外部源仓库（与 flutter 工程同级）：这里锁「仓库里的漫画源永远可导入」。
  File repoIndex() => File('../miao-dock-sources/manga/index.json');

  test('仓库形态判定：数组 / sources 列表是仓库，带 specVersion 的是单源清单', () {
    final repoRaw = repoIndex().readAsStringSync();
    expect(isSourceCatalogDocument(repoRaw), isTrue);
    expect(isSourceCatalogDocument('{"name":"r","sources":[]}'), isTrue);
    expect(isSourceCatalogDocument('{"name":"r","entries":[]}'), isTrue);
    // 单源清单（source.json）含 specVersion，必须仍走单源导入分支。
    expect(isSourceCatalogDocument('{"specVersion":2,"id":"X","sources":[]}'), isFalse);
    expect(isSourceCatalogDocument('not json'), isFalse);
  });

  test('本地 index.json：条目按 file:// 相对解析（不带 allowLocalFile 时会被过滤）', () {
    final index = repoIndex();
    expect(index.existsSync(), isTrue, reason: '源仓库缺失：请确认 ../miao-dock-sources/manga 存在');
    final raw = index.readAsStringSync();
    final baseUrl = index.absolute.uri.toString();

    final catalog = parseSourceCatalog(raw, baseUrl, allowLocalFile: true);
    expect(catalog.entries, hasLength(1));
    final entry = catalog.entries.single;
    expect(entry.key, 'ManHuaGui');
    expect(entry.name, '漫画柜');
    expect(entry.manifestUrl, startsWith('file:'));
    final entryFile = File(Uri.parse(entry.manifestUrl).toFilePath());
    expect(entryFile.existsSync(), isTrue, reason: '仓库条目应指向同目录 manhuagui.js');

    // 反证：旧行为（远程语义）把 file 条目全部过滤 → 本地仓库「没有可导入的源」。
    expect(parseSourceCatalog(raw, baseUrl).entries, isEmpty);
  });

  test('远程仓库解析不受影响：相对 fileName 仍解析成 http(s) 地址', () {
    const raw = '[{"key":"a","name":"A","version":"1.0.0","fileName":"a.js"}]';
    final catalog = parseSourceCatalog(raw, 'https://example.com/repo/index.json');
    expect(catalog.entries.single.manifestUrl, 'https://example.com/repo/a.js');
  });

  group('本地仓库安装（落盘根注入临时目录）', () {
    late Directory temp;
    late SourceImporter importer;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('miao-manga-catalog');
      importer = SourceImporter(rootResolver: () => temp);
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('真实仓库条目：读取 index.json → 安装漫画柜源并落盘', () async {
      final catalog = await importer.loadLocalCatalog(repoIndex().path);
      final result = await importer.importCatalogEntry(catalog.entries.single);

      // 破坏点：把 index.json 当 source.json 解析 → 这里拿到 invalidJson。
      expect(result.ok, isTrue, reason: 'errors=${result.errors} warnings=${result.warnings}');
      final source = result.source!;
      expect(source.id, 'ManHuaGui');
      expect(source.name, '漫画柜');
      expect(source.version, '1.2.2');
      expect(source.capabilities, contains('loadComicInfo'));

      final installed = Directory('${temp.path}/sources/ManHuaGui');
      expect(installed.existsSync(), isTrue);
      expect(File('${installed.path}/source.json').existsSync(), isTrue);
      expect(File('${installed.path}/source.js').existsSync(), isTrue);
    });

    test('条目文件缺失 / 非 ComicSource 脚本：逐条报错，不拖垮整仓库', () async {
      File('${temp.path}/good.js').writeAsStringSync('''
class GoodSource extends ComicSource {
  name = "好源";
  key = "GoodSource";
  version = "1.0.0";
  baseUrl = "https://example.com";
}
''');
      File('${temp.path}/bad.js').writeAsStringSync('class NotASource {}');
      File('${temp.path}/index.json').writeAsStringSync('''
[
  {"key":"GoodSource","name":"好源","version":"1.0.0","fileName":"good.js"},
  {"key":"NotASource","name":"坏源","version":"1.0.0","fileName":"bad.js"},
  {"key":"Missing","name":"缺文件","version":"1.0.0","fileName":"missing.js"}
]
''');
      final catalog = await importer.loadLocalCatalog('${temp.path}/index.json');
      expect(catalog.entries, hasLength(3));

      final results = [for (final entry in catalog.entries) await importer.importCatalogEntry(entry)];
      expect(results[0].ok, isTrue, reason: '${results[0].errors}');
      expect(results[1].errors.single.code, 'notComicSource');
      expect(results[2].errors.single.code, 'catalogEntryMissing');
    });
  });
}
