import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

/// D-079：漫画名规范化必须与旧项目 names.rs 一致。
void main() {
  test('旧项目自带用例：「  a/b:c*  」→ abc', () {
    // 旧项目 names.rs 测试原文 assert_eq!(normalize("  a/b:c*  "), "abc")
    final r = normalizeComicName('  a/b:c*  ');
    expect(r.isOk, isTrue);
    expect(r.name, 'abc');
  });

  test('NFKC：全角转半角（旧项目提示里的「全角转半角」）', () {
    final r = normalizeComicName('ＡＢＣ１２３');
    expect(r.name, 'ABC123');
  });

  test('折叠连续空白为单个半角空格，去首尾', () {
    final r = normalizeComicName('  星轨   邮差   ');
    expect(r.name, '星轨 邮差');
  });

  test('剥 Windows 非法字符与尾点', () {
    final r = normalizeComicName('a<b>c?*|"d.');
    expect(r.name, 'abcd');
  });

  test('保留名：CON 与 con.txt 都拒绝', () {
    expect(normalizeComicName('CON').code, 'INVALID_COMIC_NAME');
    expect(normalizeComicName('con.txt').code, 'INVALID_COMIC_NAME');
  });

  test('长度超过 64 个 Unicode 字符拒绝', () {
    final r = normalizeComicName('a' * 65);
    expect(r.code, 'INVALID_COMIC_NAME');
    expect(r.message, contains('64'));
  });

  test('规范化后为空 → COMIC_NAME_REQUIRED', () {
    expect(normalizeComicName('///').code, 'COMIC_NAME_REQUIRED');
    expect(normalizeComicName('   ').code, 'COMIC_NAME_REQUIRED');
  });

  test('U+0000 拒绝', () {
    expect(normalizeComicName('a\u0000b').code, 'INVALID_COMIC_NAME');
  });

  test('isSafeDirName：单段名防越界', () {
    expect(isSafeDirName('正常名字'), isTrue);
    expect(isSafeDirName('a/b'), isFalse);
    expect(isSafeDirName('..'), isFalse);
    expect(isSafeDirName(''), isFalse);
    expect(isSafeDirName('a\\b'), isFalse);
  });
}
