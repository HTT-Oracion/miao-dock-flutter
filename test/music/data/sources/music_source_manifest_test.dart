import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/domain/music_source_manifest.dart';

/// 清单从 JS 推导：类字段是唯一事实源（与漫画源同口径，字段精简）。
///
/// 破坏点：推导放水 → 坏包进运行时（无 platform / 无入口类 / 白名单缺失）。
const goodJs = '''
class NeteaseSource extends MusicSourceBase {
  name = '网易云';
  platform = 'netease';
  key = 'netease';
  version = '1.0.0';
  baseUrl = 'https://music.163.com';
  async searchSongs(args) { return { songs: [] }; }
  async charts() { return { charts: [] }; }
}
''';

void main() {
  test('合法 JS：全部字段从类字段与 URL 推导', () {
    final (m, issues) = manifestFromScript(goodJs, 'netease.js');
    expect(issues, isEmpty, reason: '$issues');
    expect(m!.id, 'netease');
    expect(m.platform, 'netease');
    expect(m.resolvedPlatform?.name, 'netease');
    expect(m.name, '网易云');
    expect(m.version, '1.0.0');
    expect(m.baseUrl, 'https://music.163.com');
    expect(m.entryClass, 'NeteaseSource');
    expect(m.sourceFile, 'netease.js');
    // hosts 从 JS 实际出现的 URL 推导。
    expect(m.hosts, contains('music.163.com'));
  });

  test('hosts 从实际 URL 推导：跨子域全部收录', () {
    // 破坏点：hosts 仍靠声明 → 源实际请求什么不受限（安全边界失守）。
    const js = '''
class X extends MusicSourceBase {
  name = 'X'; platform = 'kugou'; key = 'x'; version = '1';
  baseUrl = 'https://www.kugou.com';
  async searchSongs(args) { await fetch('https://songsearch.kugou.com/a'); }
  async songUrl(args) { return { url: 'https://gateway.kugou.com/b' }; }
}
''';
    final (m, issues) = manifestFromScript(js, 'x.js');
    expect(issues, isEmpty);
    expect(m!.hosts, containsAll(['www.kugou.com', 'songsearch.kugou.com', 'gateway.kugou.com']));
  });

  test('platform 字段缺失：拒绝（第一步必须映射到内置平台）', () {
    final js = goodJs.replaceFirst("platform = 'netease';", '');
    final (m, issues) = manifestFromScript(js, 'netease.js');
    expect(m, isNull);
    expect(issues, contains('platform'));
  });

  test('platform 不是内置平台：拒绝', () {
    final js = goodJs.replaceFirst("platform = 'netease';", "platform = 'bilibili';");
    final (m, issues) = manifestFromScript(js, 'netease.js');
    expect(m, isNull);
    expect(issues, contains('platform'));
  });

  test('入口类缺失 / 不继承 MusicSourceBase：拒绝', () {
    final (m, issues) = manifestFromScript('class X extends NotBase {}', 'x.js');
    expect(m, isNull);
    expect(issues, contains('entryClass'));
  });

  test('key / name / baseUrl 缺失：分别报字段名', () {
    var js = goodJs.replaceFirst("key = 'netease';", '');
    var (m, issues) = manifestFromScript(js, 'netease.js');
    expect(m, isNull);
    expect(issues, contains('key'));

    js = goodJs.replaceFirst("name = '网易云';", '');
    (m, issues) = manifestFromScript(js, 'netease.js');
    expect(issues, contains('name'));

    js = goodJs.replaceFirst("baseUrl = 'https://music.163.com';", '');
    (m, issues) = manifestFromScript(js, 'netease.js');
    expect(issues, contains('baseUrl'));
  });

  test('目录条目兜底：类字段缺失时用 catalog 值', () {
    // 破坏点：目录元信息不参与推导 → index.json 的 name/version 无意义。
    final js = goodJs.replaceFirst("version = '1.0.0';", '');
    final (m, issues) = manifestFromScript(
      js,
      'netease.js',
      catalogKey: 'netease-catalog',
      catalogName: '目录名',
      catalogVersion: '2.0.0',
    );
    expect(issues, isEmpty, reason: '$issues');
    expect(m!.version, '2.0.0');
  });
}
