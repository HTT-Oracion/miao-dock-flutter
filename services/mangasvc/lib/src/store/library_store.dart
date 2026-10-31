import 'dart:convert';
import 'dart:io';

import '../server/http.dart';
import 'plans.dart';

/// 漫画库落盘 —— 「本 → 话 → 页」三层，目录即索引。
///
/// ## 目录约定（与原项目一致）
/// ```
/// <root>/
///   <书名>/                     ← 本（大类）
///     manifest.json             ← 元信息（title / author / cover）
///     01_第1话/                 ← 话
///       001.png                 ← 页（序号即文件名前缀）
///       001_translated.png      ← 译文
/// ```
///
/// ## 为什么「目录即索引」
/// 不维护数据库：扫目录就能还原书架，用户手动拷进拷出也不会失联。
/// 代价是扫描要读每个目录，故 `scan()` 做了浅层缓存（按 mtime 失效）。
class LibraryStore {
  LibraryStore({String? rootDir}) : _rootDir = rootDir; // ignore: prefer_initializing_formals

  String? _rootDir;

  /// 落盘根目录（惰性创建）。
  String get rootDir => _rootDir ??= _defaultRoot();

  static String _defaultRoot() {
    final env = Platform.environment;
    final home = env['HOME'] ?? '.';
    return '$home/MiaoDock/library';
  }

  /// 初始化：确保根目录存在。
  Future<void> init() async {
    final dir = Directory(rootDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  // ── 扫描 ────────────────────────────────────────────────────────────────

  /// 扫描全库，产出契约 `LibraryResponse`。
  Future<Map<String, dynamic>> scan() async {
    final root = Directory(rootDir);
    if (!root.existsSync()) {
      return _emptyView();
    }
    final books = <Map<String, dynamic>>[];
    final comics = <Map<String, dynamic>>[];
    final others = <Map<String, dynamic>>[];
    var totalImages = 0;
    var totalBytes = 0;

    for (final entity in root.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = _baseName(entity.path);
      if (name.startsWith('.')) continue; // 跳过隐藏目录
      // 服务自己的状态目录（token / hidden-comics.json）不是漫画，必须排除。
      if (name == 'state') continue;

      final chapters = _chaptersOf(entity);
      final hasManifest = _manifestOf(entity) != null;
      if (hasManifest) {
        final meta = _manifestOf(entity)!;
        final pageCount = chapters.fold<int>(0, (s, c) => s + (c['seqMax'] as int));
        final bytes = _dirBytes(entity);
        totalImages += pageCount;
        totalBytes += bytes;
        books.add({
          'bookName': name,
          'dirName': name,
          'outputDir': entity.path,
          'title': (meta['title'] as String?) ?? name,
          'author': (meta['author'] as String?) ?? '',
          'coverPath': (meta['cover'] as String?) ?? _findCoverName(entity),
          'chapterCount': chapters.length,
          'totalPages': pageCount,
          'byteSize': bytes,
          'modifiedAt': _mtimeOf(entity),
          'chapters': chapters,
        });
        comics.add(_comicEntry(name, entity, pageCount, bytes));
      } else {
        // 没有 manifest：按「未归并单话」处理。
        final chapter = _chapterEntry(entity, no: null);
        others.add(chapter);
        totalImages += chapter['seqMax'] as int;
        final bytes = _dirBytes(entity);
        totalBytes += bytes;
        comics.add(_comicEntry(name, entity, chapter['seqMax'] as int, bytes));
      }
    }

    return {
      'root': rootDir,
      'count': books.length,
      'totalImages': totalImages,
      'totalBytes': totalBytes,
      'comics': comics,
      'books': books,
      'others': others,
      'hidden': _hidden.toList(),
      'hiddenCount': _hidden.length,
      'updatedAt': isoNow(),
    };
  }

  Map<String, dynamic> _emptyView() => {
    'root': rootDir,
    'count': 0,
    'totalImages': 0,
    'totalBytes': 0,
    'comics': <Map<String, dynamic>>[],
    'books': <Map<String, dynamic>>[],
    'others': <Map<String, dynamic>>[],
    'hidden': _hidden.toList(),
    'hiddenCount': _hidden.length,
    'updatedAt': isoNow(),
  };

  /// 本下的全部话（按话号升序）。
  List<Map<String, dynamic>> _chaptersOf(Directory bookDir) {
    final chapters = <Map<String, dynamic>>[];
    for (final e in bookDir.listSync(followLinks: false)) {
      if (e is! Directory) continue;
      final name = _baseName(e.path);
      if (name.startsWith('.')) continue;
      final no = _chapterNoOf(name);
      if (no == null) continue;
      chapters.add(_chapterEntry(e, no: no, dirName: name));
    }
    chapters.sort((a, b) => (a['no'] as int).compareTo(b['no'] as int));
    return chapters;
  }

  /// 从 `01_第1话` 这类目录名取话号；取不到返回 null。
  int? _chapterNoOf(String dirName) {
    final m = RegExp(r'^(\d+)').firstMatch(dirName);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  Map<String, dynamic> _chapterEntry(Directory dir, {int? no, String? dirName}) {
    final files = dir.listSync(followLinks: false).whereType<File>().where((f) => _isImage(f.path)).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final seqs = <int>[];
    final translated = <int>[];
    for (final f in files) {
      final seq = _seqOf(f.path);
      if (seq == null) continue;
      seqs.add(seq);
      if (_baseName(f.path).contains('_translated')) translated.add(seq);
    }
    seqs.sort();
    translated.sort();
    final seqMax = seqs.isEmpty ? 0 : seqs.reduce((a, b) => a > b ? a : b);
    // 1..seqMax 内没有原图的页码。
    final missing = [
      for (var i = 1; i <= seqMax; i++)
        if (!seqs.contains(i)) i,
    ];
    return {
      'no': no,
      'dirName': dirName ?? _baseName(dir.path),
      'absDir': dir.path,
      'imageCount': seqs.length,
      'translatedCount': translated.length,
      'seqMax': seqMax,
      'translatedSeqs': translated,
      'missingSeqs': missing,
      'merged': no != null,
      'mergedTo': no != null ? {'bookName': _baseName(dir.parent.path), 'no': no} : null,
      'modifiedAt': _mtimeOf(dir),
    };
  }

  Map<String, dynamic> _comicEntry(String name, Directory dir, int pageCount, int bytes) => {
    'comicName': name,
    'dirName': name,
    'outputDir': dir.path,
    'imageCount': pageCount,
    'translatedCount': _translatedCountOf(dir),
    'byteSize': bytes,
    'seqMax': pageCount,
    'nextSeq': pageCount + 1,
    'translatedSeqs': _translatedSeqsOf(dir),
    'missingSeqs': <int>[],
    'modifiedAt': _mtimeOf(dir),
  };

  int _translatedCountOf(Directory dir) => _translatedSeqsOf(dir).length;

  List<int> _translatedSeqsOf(Directory dir) {
    final out = <int>[];
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is! File || !_isImage(e.path)) continue;
      final base = _baseName(e.path);
      if (!base.contains('_translated')) continue;
      final seq = _seqOf(e.path);
      if (seq != null) out.add(seq);
    }
    return out..sort();
  }

  // ── 元信息 ──────────────────────────────────────────────────────────────

  /// 读 `manifest.json`；不存在或损坏返回 null。
  Map<String, dynamic>? _manifestOf(Directory dir) {
    final f = File('${dir.path}/manifest.json');
    if (!f.existsSync()) return null;
    try {
      final decoded = jsonDecode(f.readAsStringSync());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// 读本元信息（契约 `GET /library/{name}/meta`）。
  Future<Map<String, dynamic>> readMeta(String name) async {
    final dir = Directory('$rootDir/$name');
    final meta = _manifestOf(dir) ?? const <String, dynamic>{};
    return {
      'title': (meta['title'] as String?) ?? name,
      'author': (meta['author'] as String?) ?? '',
      'coverPath': (meta['cover'] as String?) ?? _findCoverName(dir),
    };
  }

  /// 写本元信息。
  Future<void> writeMeta(String name, Map<String, dynamic> body) async {
    final dir = Directory('$rootDir/$name');
    if (!dir.existsSync()) {
      throw const ServiceError('NOT_FOUND', '该本不存在', status: 404);
    }
    final current = _manifestOf(dir) ?? <String, dynamic>{};
    current['title'] = body['title'] ?? current['title'] ?? name;
    current['author'] = body['author'] ?? current['author'] ?? '';
    File('${dir.path}/manifest.json').writeAsStringSync(jsonEncode(current));
  }

  // ── 封面 ────────────────────────────────────────────────────────────────

  String? _findCoverName(Directory dir) {
    for (final ext in ['png', 'jpg', 'jpeg', 'webp']) {
      final f = File('${dir.path}/cover.$ext');
      if (f.existsSync()) return 'cover.$ext';
    }
    return null;
  }

  Future<List<int>?> readCover(String name) async {
    final dir = Directory('$rootDir/$name');
    final cover = _findCoverName(dir);
    if (cover == null) return null;
    return File('${dir.path}/$cover').readAsBytes();
  }

  Future<void> writeCover(String name, String base64Data) async {
    final dir = Directory('$rootDir/$name');
    if (!dir.existsSync()) throw const ServiceError('NOT_FOUND', '该本不存在', status: 404);
    final bytes = base64Decode(base64Data);
    final file = File('${dir.path}/cover.png')..writeAsBytesSync(bytes);
    final meta = _manifestOf(dir) ?? <String, dynamic>{};
    meta['cover'] = 'cover.png';
    File('${dir.path}/manifest.json').writeAsStringSync(jsonEncode(meta));
    file.existsSync();
  }

  Future<void> deleteCover(String name) async {
    final dir = Directory('$rootDir/$name');
    final cover = _findCoverName(dir);
    if (cover != null) File('${dir.path}/$cover').deleteSync();
    final meta = _manifestOf(dir);
    if (meta != null) {
      meta.remove('cover');
      File('${dir.path}/manifest.json').writeAsStringSync(jsonEncode(meta));
    }
  }

  // ── 增删 ────────────────────────────────────────────────────────────────

  Future<void> createBook(String name) async {
    final dir = Directory('$rootDir/$name');
    if (dir.existsSync()) {
      throw const ServiceError('DUPLICATE_BOOK', '同名漫画已存在');
    }
    dir.createSync(recursive: true);
    File('${dir.path}/manifest.json').writeAsStringSync(jsonEncode({'title': name, 'author': ''}));
  }

  /// 删本：`deleteFiles=false` 只隐藏（目录仍在），true 连目录一起删。
  Future<Map<String, dynamic>> deleteBook(String name, {required bool deleteFiles}) async {
    final dir = Directory('$rootDir/$name');
    if (!dir.existsSync() && !_hidden.contains(name)) {
      throw const ServiceError('NOT_FOUND', '该本不存在', status: 404);
    }
    if (deleteFiles) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } else {
      _hidden.add(name);
      _persistHidden();
    }
    return {
      'comicName': name,
      'deletedFiles': deleteFiles,
      'outputDir': dir.path,
      'hidden': _hidden.toList(),
      'hiddenCount': _hidden.length,
    };
  }

  Future<void> unhide(String name) async {
    _hidden.remove(name);
    _persistHidden();
  }

  final Set<String> _hidden = {};

  void _persistHidden() {
    try {
      final f = File('$rootDir/hidden-comics.json');
      f.writeAsStringSync(jsonEncode(_hidden.toList()));
    } catch (_) {
      // 忽略名单写失败不影响主流程
    }
  }

  // ── 文件 ────────────────────────────────────────────────────────────────

  /// 本内第 [seq] 页的原图。
  Future<File?> fileOf(String name, int seq) async => _findSeqFile(Directory('$rootDir/$name'), seq);

  /// 话内第 [seq] 页的原图。
  Future<File?> chapterFileOf(String book, int no, int seq) async {
    final bookDir = Directory('$rootDir/$book');
    if (!bookDir.existsSync()) return null;
    for (final e in bookDir.listSync(followLinks: false)) {
      if (e is! Directory) continue;
      if (_chapterNoOf(_baseName(e.path)) != no) continue;
      return _findSeqFile(e, seq);
    }
    return null;
  }

  File? _findSeqFile(Directory dir, int seq) {
    if (!dir.existsSync()) return null;
    for (final e in dir.listSync(followLinks: false)) {
      if (e is! File || !_isImage(e.path)) continue;
      if (_baseName(e.path).contains('_translated')) continue;
      if (_seqOf(e.path) == seq) return e;
    }
    return null;
  }

  // ── 工具 ────────────────────────────────────────────────────────────────

  static const _imageExts = {'png', 'jpg', 'jpeg', 'webp'};

  bool _isImage(String path) => _imageExts.contains(path.split('.').last.toLowerCase());

  /// 文件名前缀数字（`001.png` → 1）。
  int? _seqOf(String path) {
    final m = RegExp(r'(\d+)').firstMatch(_baseName(path));
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  String _baseName(String path) => path.split(Platform.pathSeparator).last;

  String? _mtimeOf(Directory dir) {
    try {
      return dir.statSync().modified.toUtc().toIso8601String();
    } catch (_) {
      return null;
    }
  }

  int _dirBytes(Directory dir) {
    var total = 0;
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) total += e.lengthSync();
      }
    } catch (_) {
      // 统计失败不影响扫描
    }
    return total;
  }
}

/// 章节定位与重命名 —— 供 B7 使用。
extension ChapterOps on LibraryStore {
  /// 本目录（校验存在）。
  Directory bookDir(String book) {
    final dir = Directory('$rootDir/$book');
    if (!dir.existsSync()) {
      throw ServiceError('TASK_NOT_FOUND', '漫画目录不存在', details: {'book': book}, status: 404);
    }
    return dir;
  }

  /// 解析 `<book>/chapters/<no>` 对应的目录。
  Directory chapterDir(String book, String noRaw) {
    final no = parseChapterNo(noRaw);
    final bookDir = Directory('$rootDir/$book');
    if (!bookDir.existsSync()) {
      throw ServiceError('TASK_NOT_FOUND', '漫画目录不存在', details: {'book': book}, status: 404);
    }
    final target = chapterDirName(no);
    for (final e in bookDir.listSync(followLinks: false)) {
      if (e is Directory && e.path.split(Platform.pathSeparator).last == target) return e;
    }
    throw ServiceError(
      'TASK_NOT_FOUND',
      '话目录不存在',
      details: {'book': book, 'no': noRaw, 'expected': target},
      status: 404,
    );
  }

  /// 改话号：把 `01_第1话` 改成 `02_第2话`。
  ///
  /// 目标目录已存在时报冲突（**不覆盖**）。
  Future<Map<String, dynamic>> renumberChapter(String book, String noRaw, int newNo) async {
    final dir = chapterDir(book, noRaw);
    final from = dir.path.split(Platform.pathSeparator).last;
    final to = chapterDirName(newNo.toDouble());
    if (from == to) return {'from': from, 'to': to, 'renamed': false};
    final target = Directory(dir.parent.path + Platform.pathSeparator + to);
    if (target.existsSync()) {
      throw ServiceError('CHAPTER_TARGET_EXISTS', '目标话号已存在', details: {'from': from, 'to': to});
    }
    dir.renameSync(target.path);
    return {'from': from, 'to': to, 'renamed': true};
  }
}
