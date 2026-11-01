/// 模糊匹配（D-104，移植 miao-dock `tools/index.ts matchIndices/fuzzyMatch`）。
///
/// 判定用**子序列**而非 `includes`：漫画名常是「第12话 · 学园祭」这种长串，
/// 用户只记得「12学」也应命中。子序列天然覆盖「连续子串」的情形，
/// 所以不必再补测一次 `includes`。
///
/// 大小写折叠用 `toLowerCase()` 而非 `toLocaleLowerCase()`：
/// 后者在土耳其语等 locale 下把 `I` 折成 `ı`，同一份代码在不同机器上结果不同。
library;

/// 返回命中字符在原文中的下标（用于高亮）；未命中返回 `null`，空查询返回空表。
List<int>? matchIndices(String text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final map = <int>[];
  final folded = StringBuffer();
  final chars = text.split('');
  for (var i = 0; i < chars.length; i++) {
    final lc = chars[i].toLowerCase();
    for (var k = 0; k < lc.length; k++) {
      map.add(i);
    }
    folded.write(lc);
  }
  final foldedStr = folded.toString();
  final out = <int>[];
  var i = 0;
  for (var j = 0; j < foldedStr.length && i < q.length; j++) {
    if (foldedStr[j] == q[i]) {
      out.add(map[j]);
      i++;
    }
  }
  return i == q.length ? out : null;
}

/// 是否模糊命中（不区分大小写）。
bool fuzzyMatch(String text, String query) => matchIndices(text, query) != null;
