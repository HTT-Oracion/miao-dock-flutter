import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

/// D-104：模糊匹配（移植 miao-dock `matchIndices`）。
void main() {
  test('子序列命中：12学 → 第12话 · 学园祭', () {
    // 破坏点：改成 includes → 本用例失败（这正是引入模糊匹配的理由）。
    expect(fuzzyMatch('第12话 · 学园祭', '12学'), isTrue);
    expect('第12话 · 学园祭'.contains('12学'), isFalse); // 说明 contains 确实不行
  });

  test('连续子串也命中（子序列天然覆盖）', () {
    expect(fuzzyMatch('学园祭', '学园'), isTrue);
  });

  test('不区分大小写', () {
    expect(fuzzyMatch('Sakura Translation', 'sakura'), isTrue);
    expect(fuzzyMatch('SAKURA', 'sak'), isTrue);
  });

  test('顺序不对不命中', () {
    expect(fuzzyMatch('学园祭', '祭学'), isFalse);
  });

  test('空查询命中一切', () {
    expect(fuzzyMatch('任意', ''), isTrue);
    expect(fuzzyMatch('任意', '   '), isTrue);
  });

  test('matchIndices 返回原文下标（用于高亮）', () {
    expect(matchIndices('第12话', '1话'), [1, 3]);
    expect(matchIndices('第12话', 'xyz'), isNull);
  });
}
