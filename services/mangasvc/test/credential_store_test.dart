import 'dart:convert';
import 'dart:io';

import 'package:mangasvc/src/translate/credential_store.dart';
import 'package:test/test.dart';

/// D-052：凭证落盘的正确性（原子写、0600、永不回显 secret）。
void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('cred-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  CredentialStore store() => CredentialStore(rootDir: tmp.path);

  test('没存过 → null', () {
    // 破坏点：文件不存在时抛异常 → 设置页打不开，本条失败。
    expect(store().read(), isNull);
  });

  test('保存后可读回，且原子写不残留 .tmp', () async {
    await store().save(platform: 'youdaoZhiYun', appKey: 'k', appSecret: 's');
    final c = store().read();
    expect(c?.appKey, 'k');
    expect(c?.usable, isTrue);
    // 破坏点：临时文件没被 rename 掉 → 目录里残留垃圾，本条失败。
    final files = tmp.listSync().whereType<File>().map((f) => f.path.split('/').last).toList();
    expect(files, contains('credentials.json'));
    expect(files.any((n) => n.endsWith('.tmp')), isFalse);
  });

  test('对外 JSON 不含 secret（只有布尔）', () async {
    await store().save(platform: 'youdaoZhiYun', appKey: 'k', appSecret: 'topsecret');
    final masked = store().read()!.toMaskedJson();
    // 破坏点：回显 secret → 日志/抓包泄漏密钥，本条失败。
    expect(masked.values.join('|'), isNot(contains('topsecret')));
    expect(masked['hasSecret'], isTrue);
    expect(masked.containsKey('appSecret'), isFalse);
  });

  test('文件权限收紧到 0600（POSIX）', () async {
    if (Platform.isWindows) return;
    await store().save(platform: 'youdaoZhiYun', appKey: 'k', appSecret: 's');
    final out = Process.runSync('stat', ['-f', '%Lp', '${tmp.path}/credentials.json']);
    // 破坏点：权限 644 → 同机其他用户可读密钥，本条失败。
    expect((out.stdout as String).trim(), '600');
  });

  test('文件损坏 → 按未配置处理，不抛', () {
    File('${tmp.path}/credentials.json').writeAsStringSync('{not json');
    expect(store().read(), isNull);
  });

  test('清除后读回为 null', () async {
    await store().save(platform: 'youdaoZhiYun', appKey: 'k', appSecret: 's');
    await store().clear();
    expect(store().read(), isNull);
  });

  test('落盘内容是明文 JSON（已记录的代价）', () async {
    await store().save(platform: 'youdaoZhiYun', appKey: 'k', appSecret: 's');
    final raw = jsonDecode(File('${tmp.path}/credentials.json').readAsStringSync()) as Map;
    // 这条不是缺陷断言，而是把「明文落盘」这个已接受的代价钉在测试里，
    // 将来若改成加密存储，这条会提醒你同步更新文档。
    expect(raw['appSecret'], 's');
  });
}
