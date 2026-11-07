import 'dart:typed_data';

/// 阅读器页图缓存（D-167）。
///
/// 为什么必须有它：翻页时新页 `ReaderPage` 会先挂载、再去取字节，取回来之前
/// 只能画 loading —— 这一帧就是用户看到的「闪一下」。有了缓存，翻过的页
/// （以及预载过的前后页）**同步**就有字节，翻页当帧直接出图。
///
/// 只缓存**已解码前的字节**（`Uint8List`），不缓存 [Image]：字节小、可复用，
/// 而 Image 与尺寸/设备像素比绑定，跨页复用会错位。上限按页数算（一页几百 KB）。
class ReaderImageCache {
  ReaderImageCache._();

  /// 上限按「本话页数 + 前后预载」估：24–40 页足够来回翻不重取。
  static const int maxEntries = 48;

  /// 插入顺序即淘汰顺序（FIFO）：阅读是顺序访问，不需要真 LRU。
  static final Map<String, Uint8List> _entries = <String, Uint8List>{};

  static int get length => _entries.length;

  static Uint8List? get(String key) => _entries[key];

  static void put(String key, Uint8List bytes) {
    if (bytes.isEmpty) return;
    if (_entries.containsKey(key)) return;
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = bytes;
  }

  /// 仅测试用：用例之间要能清干净，避免「上一条用例的字节」让断言假通过。
  static void clear() => _entries.clear();
}

/// 缓存键：书/话 + 页码 + 原图/译文。
///
/// 译文与原图是两份不同的图，**必须分开键**：同一页切换原文时不能命中另一份。
String readerImageKey({
  required String bookKey,
  required double? chapterNo,
  required int seq,
  required bool translated,
}) => '$bookKey|${chapterNo ?? ''}|$seq|${translated ? 't' : 'o'}';
