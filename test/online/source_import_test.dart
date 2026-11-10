import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/manga/online/data/source_import.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/source_manifest.dart';

Map<String, Object?> manifest({
  int specVersion = 2,
  String id = 'demo.source',
  List<String> hosts = const ['example.com'],
  String entryClass = 'DemoSource',
  String sourceFile = 'source.js',
}) => {
  'specVersion': specVersion,
  'id': id,
  'name': '示例源',
  'version': '1.0.0',
  'lang': 'zh',
  'baseUrl': 'https://example.com',
  'entryClass': entryClass,
  'sourceFile': sourceFile,
  'hosts': hosts,
  'request': {
    'timeoutMs': 15000,
    'headers': {'Referer': 'https://example.com/'},
  },
  'rateLimit': {'intervalMs': 400, 'concurrency': 2},
};

const goodScript = '''
class DemoSource extends SourceBase {
  async explore(ctx) { return { sections: [] }; }
  async categories() { return []; }
  async category(ctx) { return { items: [], page: 1, hasMore: false }; }
  async search(ctx) { return { items: [], page: 1, hasMore: false }; }
  async loadComicInfo(ctx) { return { id: ctx.id, title: '', chapters: [] }; }
  async loadComicPages(ctx) { return []; }
  async getImageLoadingConfig(ctx) { return {}; }
  async init() {}
}
''';

Future<Directory> package({String? jsonText, String? script, String scriptName = 'source.js'}) async {
  final dir = await Directory.systemTemp.createTemp('online-source-test-');
  addTearDown(() => dir.delete(recursive: true));
  await File('${dir.path}/source.json')
      .writeAsString(jsonText ?? const JsonEncoder.withIndent('  ').convert(manifest()));
  await File('${dir.path}/$scriptName').writeAsString(script ?? goodScript);
  return dir;
}

void main() {
  test('source.json 必填字段与命名规则', () {
    final valid = SourceManifest.fromMap(manifest());
    expect(valid.validate(), isEmpty);
    expect(valid.timeoutMs, 15000);

    expect(SourceManifest.fromMap(manifest(specVersion: 1)).validate(), contains('specVersion'));
    expect(SourceManifest.fromMap(manifest(id: 'A')).validate(), contains('id'));
    expect(SourceManifest.fromMap(manifest(hosts: [])).validate(), contains('hosts'));
    expect(SourceManifest.fromMap(manifest(hosts: ['not a host'])).validate(), contains('hosts'));
    expect(SourceManifest.fromMap(manifest(entryClass: '')).validate(), contains('entryClass'));

    final traversal = SourceManifest.fromMap({...manifest(), 'sourceFile': '../evil.js'});
    // 破坏点：路径校验被删掉时，traversal 不再命中 path。
    expect(traversal.validate(), contains('path'));
  });

  test('完整包导入：静态检查入口类与能力', () async {
    final dir = await package();
    final result = await SourceImporter().importManifest('${dir.path}/source.json');
    expect(result.ok, isTrue);
    expect(result.source!.id, 'demo.source');
    expect(result.source!.capabilities, containsAll({'explore', 'loadComicInfo', 'loadComicPages'}));
    expect(result.errors, isEmpty);
  });

  test('specVersion 拒绝', () async {
    final dir = await package(jsonText: const JsonEncoder.withIndent('  ').convert(manifest(specVersion: 1)));
    final result = await SourceImporter().importManifest('${dir.path}/source.json');
    expect(result.ok, isFalse);
    expect(result.errors.map((e) => e.code), contains('field'));
    expect(result.errors.map((e) => e.detail), contains('specVersion'));
  });

  test('缺 source.js 拒绝', () async {
    final dir = await package();
    await File('${dir.path}/source.js').delete();
    final result = await SourceImporter().importManifest('${dir.path}/source.json');
    expect(result.ok, isFalse);
    expect(result.errors.single.code, 'sourceMissing');
  });

  test('入口类未继承 SourceBase 拒绝', () async {
    final dir = await package(script: 'class DemoSource { }');
    final result = await SourceImporter().importManifest('${dir.path}/source.json');
    expect(result.ok, isFalse);
    expect(result.errors.map((e) => e.code), contains('entryClass'));
  });

  test('缺 loadComicInfo 拒绝（required capability）', () async {
    final dir = await package(
      script: goodScript.replaceAll(
        'async loadComicInfo(ctx) { return { id: ctx.id, title: \'\', chapters: [] }; }',
        '',
      ),
    );
    final result = await SourceImporter().importManifest('${dir.path}/source.json');
    expect(result.ok, isFalse);
    expect(result.errors.single.code, 'capabilityMissing');
    expect(result.errors.single.detail, 'loadComicInfo');
  });

  test('缺可选能力只警告，不拒收', () async {
    final dir = await package(
      script: 'class DemoSource extends SourceBase {\n  async loadComicInfo(ctx) { return { chapters: [] }; }\n}',
    );
    final result = await SourceImporter().importManifest('${dir.path}/source.json');
    expect(result.ok, isTrue);
    expect(result.warnings.map((e) => e.code), contains('capabilityOptional'));
    // 破坏点：把可选能力当必填时，这条会变红。
    expect(result.errors, isEmpty);
  });
}
