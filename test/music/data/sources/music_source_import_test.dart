import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/data/sources/js/music_source_dto.dart';
import 'package:miao_dock_flutter/features/music/data/sources/js/music_source_remote.dart';
import 'package:miao_dock_flutter/features/music/data/sources/js/music_source_import.dart';

/// `music_source.json` 包导入：校验 → 能力扫描 → 落盘。
///
/// 破坏点：入口类检查放水 → 任意 JS 被实例化执行；能力扫描漏判 → UI 能力位错。
const manifestJson = '''
{
  "specVersion": 1, "id": "probe", "platform": "netease", "name": "探针源",
  "version": "1.0.0", "baseUrl": "https://music.163.com", "entryClass": "ProbeSource",
  "sourceFile": "probe.js", "hosts": ["music.163.com"]
}
''';

const jsSource = '''
class ProbeSource extends MusicSourceBase {
  name = '探针源';
  platform = 'netease';
  key = 'probe';
  version = '1.0.0';
  baseUrl = 'https://music.163.com';
  async searchSongs(args) { return { songs: [] }; }
  async charts() { return { charts: [] }; }
}
''';

void main() {
  testBundledPackages();

  late Directory tempDir;
  late MusicSourceImporter importer;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('music-source-test');
    importer = MusicSourceImporter(rootResolver: () => tempDir);
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('能力扫描：只认契约白名单内的方法', () {
    final caps = scanMusicSourceCapabilities(jsSource);
    expect(caps, containsAll(['searchSongs', 'charts']));
    expect(caps.contains('lyrics'), isFalse);
    // 破坏点：白名单外的方法也算能力 → 源可以声明任意调用面。
    expect(caps.contains('init'), isFalse);
  });

  test('合法包：导入成功并落盘', () async {
    final dir = Directory('${tempDir.path}/pkg')..createSync();
    File('${dir.path}/music_source.json').writeAsStringSync(manifestJson);
    File('${dir.path}/probe.js').writeAsStringSync(jsSource);

    final result = await importer.importFromDirectory(dir);
    // 破坏点：入口类 / 能力检查漏 → 拒绝逻辑形同虚设。
    expect(result.ok, isTrue, reason: 'errors=${result.errors}');
    expect(result.source!.capabilities, containsAll(['searchSongs', 'charts']));
    expect(result.installedAt!.path, contains('probe'));
    expect(File('${result.installedAt!.path}/probe.js').existsSync(), isTrue);
  });

  test('入口类不存在：拒绝导入', () async {
    final dir = Directory('${tempDir.path}/pkg')..createSync();
    File('${dir.path}/music_source.json').writeAsStringSync(manifestJson);
    File('${dir.path}/probe.js').writeAsStringSync('class Wrong extends NotSourceBase {}');

    final result = await MusicSourceImporter().importFromDirectory(dir);
    // 破坏点：入口类检查放水 → 任意 JS 被实例化。
    expect(result.ok, isFalse);
    expect(result.errors.first.code, 'entryClass');
  });

  test('installedSources：枚举落盘包（坏包跳过）', () async {
    final dir = Directory('${tempDir.path}/pkg')..createSync();
    File('${dir.path}/music_source.json').writeAsStringSync(manifestJson);
    File('${dir.path}/probe.js').writeAsStringSync(jsSource);
    await importer.importFromDirectory(dir);
    // 包目录 ≠ 安装目录：导入完成后删掉源包，避免它也被枚举。
    dir.deleteSync(recursive: true);

    // 坏包：只有坏 json 无 JS，不该拖垮枚举。
    final bad = Directory('${tempDir.path}/broken')..createSync();
    File('${bad.path}/music_source.json').writeAsStringSync('{bad');

    final sources = importer.installedSources();
    expect(sources.length, 1);
    expect(sources.first.id, 'probe');
    expect(sources.first.platform.name, 'netease');
  });

  test('本地目录导入：index.json 按 file:// 解析同目录 JS', () async {
    // 与 UI _importLocalPaths 的 .json 分支同链路：解析目录清单 → 读同目录 JS → 导入。
    final jsA = jsSource
        .replaceAll("platform = 'netease';", "platform = 'kugou';")
        .replaceAll("key = 'probe';", "key = 'srcA';");
    File('${tempDir.path}/index.json').writeAsStringSync(
      '{"name":"本地目录","sources":['
      '{"key":"probe","name":"探针源","version":"1.0.0","fileName":"probe.js"},'
      '{"key":"srcA","name":"源A","version":"1.0.0","fileName":"a.js"}]}',
    );
    File('${tempDir.path}/probe.js').writeAsStringSync(jsSource);
    File('${tempDir.path}/a.js').writeAsStringSync(jsA);

    final raw = File('${tempDir.path}/index.json').readAsStringSync();
    final catalog = parseMusicSourceCatalog(raw, Uri.file('${tempDir.path}/index.json').toString());
    expect(catalog.entries.length, 2);

    // 破坏点：目录解析不接受 file:// → 本地导入永远 0 条。
    for (final entry in catalog.entries) {
      expect(entry.fileUrl, startsWith('file://'), reason: '本地清单应解析出 file 协议地址');
      final entryPath = Uri.parse(entry.fileUrl).toFilePath();
      final result = await importer.importScript(
        await File(entryPath).readAsString(),
        fileName: entryPath.split('/').last,
        catalogKey: entry.key,
        catalogName: entry.name,
        catalogVersion: entry.version,
      );
      expect(result.ok, isTrue, reason: '${entry.key}: ${result.errors}');
    }
    final sources = importer.installedSources();
    expect(sources.map((s) => s.id).toSet(), {'probe', 'srcA'});
  });
}

/// 外部源仓库（`../miao-dock-sources/music`，与 flutter 工程同级）：四平台 JS
/// 都能通过真实导入校验。应用不再内置源 —— 这个测试守住「仓库里的源永远可导」。
void testBundledPackages() {
  final assets = [('netease', 'NeteaseSource'), ('kugou', 'KugouSource'), ('qq', 'QqSource'), ('migu', 'MiguSource')];
  for (final (pkg, entry) in assets) {
    test('源仓库 $pkg：清单可推导且能力齐全', () async {
      final repoDir = Directory('../miao-dock-sources/music');
      expect(repoDir.existsSync(), isTrue, reason: '源仓库缺失：请确认 ../miao-dock-sources/music 存在');
      final jsFile = File('${repoDir.path}/$pkg.js');
      expect(jsFile.existsSync(), isTrue, reason: '源仓库缺 $pkg.js');
      final js = jsFile.readAsStringSync();
      expect(
        RegExp('class\\s+${RegExp.escape(entry)}\\s+extends\\s+MusicSourceBase').hasMatch(js),
        isTrue,
        reason: '$pkg 入口类不符',
      );
      final caps = scanMusicSourceCapabilities(js);
      expect(caps, containsAll(['searchSongs', 'songUrl']), reason: '$pkg 缺核心能力');
      // 跑真实导入校验（platform 推导 / hosts 扫描 / 入口类）。
      final result = await MusicSourceImporter().importScript(js, fileName: '$pkg.js');
      expect(result.ok, isTrue, reason: '$pkg 导入校验失败：${result.errors}');
      expect(result.source!.manifest.resolvedPlatform, isNotNull);
    });
  }
}
