/// 漫画库的**话号命名**与 **manifest 模型**（D-078）。
///
/// 全部规则逐条对照 `miao-dock/src-tauri/src/mangasvc/library.rs`：
/// - `chapter_dir_name`：`NN_第N话`，整数前缀两位零填充；小数原样（`1.5_第1.5话`）；
/// - `chapter_no_from_dir_name`：正则解析 `第N话` 里的数，不匹配返回 null（**不猜**）；
/// - `is_valid_chapter_no`：`[1.0, 999.9]`；小数部分必须匹配 `^\d{1,3}\.[1-9]$`。
library;

/// 最大话号（miao-dock `MAX_CHAPTER_NO = 999`）。
const int maxChapterNo = 999;

/// JS `String(number)`：整数不带小数点，`14.9` 原样。
String jsNumStr(double n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();

/// 话号 → 目录名：`NN_第N话`。
///
/// 两位零填充是**对字符串长度**做的（不是对整数部分）：
/// `1` → `01_第1话`；`1.5` → `1.5_第1.5话`（长度 3，不补零）。
String chapterDirName(double no) {
  final s = jsNumStr(no);
  final padded = s.length < 2 ? '0$s' : s;
  return '${padded}_第${jsNumStr(no)}话';
}

/// 目录名 → 话号；不匹配返回 `null`（不猜）。
double? chapterNoFromDirName(String dirName) {
  final m = RegExp(r'^(\d{1,3}(?:\.\d{1,3})?)_第(\d{1,3}(?:\.\d{1,3})?)话$').firstMatch(dirName);
  if (m == null) return null;
  return double.tryParse(m.group(2)!);
}

/// 话号是否合法。
bool isValidChapterNo(double v) {
  if (!v.isFinite || v < 1.0 || v > maxChapterNo + 0.9) return false;
  if (v == v.roundToDouble()) return true;
  return RegExp(r'^\d{1,3}\.[1-9]$').hasMatch(v.toString());
}

/// 一话（manifest 里的条目）。
class LibraryEpisode {
  const LibraryEpisode({required this.no, required this.dir});

  final double no;
  final String dir;

  Map<String, dynamic> toJson() => {'no': no, 'dir': dir};

  static LibraryEpisode? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final no = raw['no'];
    final dir = raw['dir'];
    if (no is! num || dir is! String) return null;
    return LibraryEpisode(no: no.toDouble(), dir: dir);
  }
}

/// 书（大类）的 manifest。
///
/// 键序刻意保持 `schema, title, author, cover, episodes` ——
/// 与 miao-dock 的 Node 字面量序一致，落盘字节可逐字节比对。
class LibraryManifest {
  const LibraryManifest({this.schema = 1, required this.title, this.author = '', this.cover, this.episodes = const []});

  final int schema;
  final String title;
  final String author;
  final String? cover;
  final List<LibraryEpisode> episodes;

  Map<String, dynamic> toJson() => {
    'schema': schema,
    'title': title,
    'author': author,
    'cover': cover,
    'episodes': [for (final e in episodes) e.toJson()],
  };

  /// 解析；字段缺失用默认值，**结构错乱返回 null**（调用方按「无 manifest」处理）。
  static LibraryManifest? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'];
    if (title is! String || title.isEmpty) return null;
    return LibraryManifest(
      schema: (raw['schema'] as num?)?.toInt() ?? 1,
      title: title,
      author: '${raw['author'] ?? ''}',
      cover: raw['cover'] is String ? raw['cover'] as String : null,
      episodes: [
        for (final e in (raw['episodes'] as List? ?? const []))
          if (LibraryEpisode.fromJson(e) != null) LibraryEpisode.fromJson(e)!,
      ],
    );
  }

  /// 是否存在某话号。
  bool hasEpisode(double no) => episodes.any((e) => e.no == no);
}
