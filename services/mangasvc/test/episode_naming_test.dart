import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

/// D-078：话号命名必须与 miao-dock 逐字节一致（照 `library.rs` 规则）。
void main() {
  test('整数话号：两位零填充', () {
    expect(chapterDirName(1), '01_第1话');
    expect(chapterDirName(10), '10_第10话');
    expect(chapterDirName(99), '99_第99话');
    expect(chapterDirName(100), '100_第100话');
  });

  test('小数话号：前缀与话名都保留小数，不补零', () {
    // 破坏点：把小数当整数截断或给小数补零 → 目录名与旧项目不一致，本条失败。
    expect(chapterDirName(1.5), '1.5_第1.5话');
    expect(chapterDirName(14.9), '14.9_第14.9话');
  });

  test('目录名 → 话号：取「第N话」里的数', () {
    expect(chapterNoFromDirName('01_第1话'), 1.0);
    expect(chapterNoFromDirName('1.5_第1.5话'), 1.5);
    expect(chapterNoFromDirName('14.9_第14.9话'), 14.9);
    expect(chapterNoFromDirName('乱目录'), isNull);
  });

  test('合法性：1.0–999.9，小数只允许 .[1-9] 一位', () {
    expect(isValidChapterNo(1), isTrue);
    expect(isValidChapterNo(999.9), isTrue);
    expect(isValidChapterNo(1000), isFalse);
    expect(isValidChapterNo(0.5), isFalse);
    expect(isValidChapterNo(1.0), isTrue);
    // 1.10 在 double 里就是 1.1（Rust 同样如此），会被当 1.1 接受 —— 与 miao-dock 一致。
    expect(isValidChapterNo(1.05), isFalse); // 「.05」不匹配 ^\d{1,3}\.[1-9]$
  });

  test('jsNumStr：整数不带小数点', () {
    expect(jsNumStr(1.0), '1');
    expect(jsNumStr(14.9), '14.9');
  });

  test('manifest 键序与字段完整', () {
    final m = LibraryManifest(
      title: '书',
      episodes: const [LibraryEpisode(no: 1.5, dir: '1.5_第1.5话')],
    );
    final keys = m.toJson().keys.toList();
    // 破坏点：键序乱了 → 落盘字节与旧项目对不上，本条失败。
    expect(keys, ['schema', 'title', 'author', 'cover', 'episodes']);
    final parsed = LibraryManifest.fromJson(m.toJson());
    expect(parsed!.hasEpisode(1.5), isTrue);
  });
}
