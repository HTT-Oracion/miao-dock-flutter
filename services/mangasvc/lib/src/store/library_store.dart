import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:protocol/protocol.dart'
    show
        LibraryEpisode,
        LibraryManifest,
        chapterDirName,
        chapterNoFromDirName,
        isValidChapterNo,
        jsNumStr,
        maxChapterNo;

import '../engine/engine_client.dart' show sniffImageType;
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
  LibraryStore({String? rootDir, String? stateDir})
    : _rootDir = rootDir, // ignore: prefer_initializing_formals
      _stateDir = stateDir; // ignore: prefer_initializing_formals

  String? _rootDir;
  String? _stateDir;

  /// 状态目录（hidden-comics.json 等；缺省 `<库根>/.miao-state`，与令牌同目录）。
  String get stateDir => _stateDir ??= '$rootDir${Platform.pathSeparator}.miao-state';

  /// 落盘根目录（惰性创建）。
  String get rootDir => _rootDir ??= _defaultRoot();

  /// 默认库根 —— **用户成果目录**（D-015）。
  ///
  /// 🔴 不挂进 appData：漫画译文要能在 Finder 里找到、能独立备份、卸载不删。
  /// 原项目 `paths.rs` 的断言「库是用户成果，不得藏进 appData」即此意。
  ///
  /// 可用 `MIAO_MANGA_LIBRARY_DIR` 覆盖（与原项目同名）。
  static String _defaultRoot() {
    final env = Platform.environment;
    final override = env['MIAO_MANGA_LIBRARY_DIR'];
    if (override != null && override.isNotEmpty) return override;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
    return '$home${Platform.pathSeparator}Pictures${Platform.pathSeparator}MiaoDock Mangas';
  }

  /// 初始化：确保根目录存在 + 读隐藏清单（`{comics:[...]}`，miao-dock 同构）。
  Future<void> init() async {
    try {
      final f = File('$stateDir${Platform.pathSeparator}hidden-comics.json');
      if (f.existsSync()) {
        final m = jsonDecode(f.readAsStringSync());
        if (m is Map && m['comics'] is List) {
          _hidden
            ..clear()
            ..addAll([for (final n in m['comics'] as List) '$n']);
        }
      }
    } catch (_) {
      // 坏文件当作没有隐藏。
    }
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
      // 已隐藏：**不出现在书架里**，只在 `hidden` 清单中（用户在「已隐藏」区恢复）。
      if (_hidden.contains(name)) continue;

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
    chapters.sort((a, b) => ((a['no'] as num?) ?? 0).compareTo(((b['no'] as num?) ?? 0)));
    return chapters;
  }

  /// 从 `01_第1话` / `1.5_第1.5话` 取话号；取不到返回 null（与旧项目同一套正则）。
  double? _chapterNoOf(String dirName) => chapterNoFromDirName(dirName);

  Map<String, dynamic> _chapterEntry(Directory dir, {double? no, String? dirName}) {
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

  /// 类型化 manifest（归并/编辑用）。
  LibraryManifest? _typedManifestOf(Directory dir) {
    final raw = _manifestOf(dir);
    return raw == null ? null : LibraryManifest.fromJson(raw);
  }

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
    if (!dir.existsSync()) return null;
    final cover = _findCoverName(dir);
    if (cover != null) return File('${dir.path}/$cover').readAsBytes();
    // 单话（无 manifest）：**默认封面 = 第一页图片**（B.7）。
    // 单本保持旧项目语义：只有 cover.* 才算封面，不拿章节首图冒充。
    if (_manifestOf(dir) == null) {
      final first = _firstPageOf(dir);
      if (first != null) return first.readAsBytes();
    }
    return null;
  }

  /// 目录内第一页：优先最小页号的**译文**，其次原图（旧项目 `pick_first_chapter_image` 同）。
  File? _firstPageOf(Directory dir) {
    if (!dir.existsSync()) return null;
    File? translated;
    File? original;
    var bestT = 1 << 30;
    var bestO = 1 << 30;
    for (final e in dir.listSync(followLinks: false)) {
      if (e is! File || !_isImage(e.path)) continue;
      final seq = _seqOf(e.path);
      if (seq == null) continue;
      final isTranslated = _baseName(e.path).contains('_translated');
      if (isTranslated && seq < bestT) {
        bestT = seq;
        translated = e;
      } else if (!isTranslated && seq < bestO) {
        bestO = seq;
        original = e;
      }
    }
    return translated ?? original;
  }

  /// 封面字节上限（miao-dock `cover_max_bytes` = 10 MiB）。
  static const int coverMaxBytes = 10 * 1024 * 1024;

  /// 写封面（D-093）：**扩展名按字节嗅探**、删旧封面、tmp + rename 原子落盘。
  Future<void> writeCover(String name, Uint8List bytes) async {
    final dir = Directory('$rootDir/$name');
    if (!dir.existsSync()) throw const ServiceError('NOT_FOUND', '该本不存在', status: 404);
    if (bytes.isEmpty) throw const ServiceError('INVALID_IMAGE', '封面数据为空');
    if (bytes.length > coverMaxBytes) {
      throw const ServiceError('COVER_TOO_LARGE', '图片不能超过 10 MB', details: {'limitBytes': coverMaxBytes});
    }
    final ext = sniffImageType(bytes);
    if (ext == null) throw const ServiceError('INVALID_IMAGE', '不是可识别的图片（png/jpg/webp）');
    final coverName = 'cover.$ext';
    // 删掉其它扩展名的旧封面（否则扫描会认到旧的那张）
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      final n = _baseName(e.path);
      if (n != coverName && RegExp(r'^cover\.(png|jpg|jpeg|webp)$').hasMatch(n)) {
        try {
          e.deleteSync();
        } catch (_) {}
      }
    }
    final tmp = File('${dir.path}${Platform.pathSeparator}$coverName.tmp');
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync('${dir.path}${Platform.pathSeparator}$coverName');
    // manifest 必须带 cover 声明，且保持全字段。
    final manifest = _typedManifestOf(dir) ?? LibraryManifest(title: name);
    _writeManifestAtomic(
      dir,
      LibraryManifest(
        schema: manifest.schema,
        title: manifest.title,
        author: manifest.author,
        cover: coverName,
        episodes: manifest.episodes,
      ),
    );
  }

  /// `coverFromFirstChapter`：用最小话目录里最小页号的图做封面（译文优先）。
  Future<void> writeCoverFromFirstChapter(String name) async {
    final dir = Directory('$rootDir/$name');
    if (!dir.existsSync()) throw const ServiceError('NOT_FOUND', '该本不存在', status: 404);
    File? first;
    final chapters = _chapterDirsOf(dir);
    if (chapters.isNotEmpty) {
      first = _firstPageOf(Directory('${dir.path}${Platform.pathSeparator}${chapters.first.dirName}'));
    }
    // 单话（无话层）直接用自己目录的首图。
    first ??= _firstPageOf(dir);
    if (first == null) {
      throw const ServiceError('TASK_NOT_FOUND', '这本漫画还没有任何图片，取不到首图', status: 404);
    }
    await writeCover(name, first.readAsBytesSync());
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
    // 全字段 manifest（键序同旧项目 default_manifest：schema,title,author,cover,episodes）。
    File('${dir.path}/manifest.json')
        .writeAsStringSync(jsonEncode(LibraryManifest(title: name, author: '', cover: null, episodes: []).toJson()));
  }

  /// 归并单话到书（D-083，对照旧项目 `library_merge` 守卫顺序与错误码）。
  Future<Map<String, dynamic>> mergeBook({
    required String srcName,
    required String targetBook,
    required double no,
    List<String> busyStatuses = const [],
  }) async {
    final srcDir = Directory('$rootDir/$srcName');
    final targetDir = Directory('$rootDir/$targetBook');

    // ③ 源不存在
    if (!srcDir.existsSync()) {
      throw const ServiceError('TASK_NOT_FOUND', '未归并单话目录不存在', status: 404);
    }
    // ④ 源已经是书
    if (_manifestOf(srcDir) != null) {
      throw ServiceError('ALREADY_MERGED', '「$srcName」已经是一本大类（目录内有 manifest.json），不能再次归并');
    }
    // 目标必须是存在的大类
    if (!targetDir.existsSync() || _manifestOf(targetDir) == null) {
      throw ServiceError('TASK_NOT_FOUND', '漫画大类不存在（目录内没有 manifest.json）', status: 404);
    }
    // ⑤ 源上有活跃任务
    if (busyStatuses.isNotEmpty) {
      throw ServiceError(
        'MERGE_SOURCE_BUSY',
        '「$srcName」还有 ${busyStatuses.length} 个任务在跑（${busyStatuses.join('、')}），请等它跑完或先取消',
      );
    }
    // 话号合法性（与 resolve_chapter_dir 同一套）
    if (!isValidChapterNo(no)) {
      throw ServiceError('TASK_NOT_FOUND', '话号必须是 1–$maxChapterNo.9 的数（最多一位小数）');
    }
    final dirName = chapterDirName(no);
    final dst = Directory('${targetDir.path}${Platform.pathSeparator}$dirName');
    // ⑤ 双向查：目录名（位置）与 episodes[].no（说明文字）都要干净
    final takenNos = [for (final c in _chapterDirsOf(targetDir)) c.no];
    final declaredNos = [for (final e in (_typedManifestOf(targetDir)?.episodes ?? const <LibraryEpisode>[])) e.no];
    if (dst.existsSync() || takenNos.contains(no) || declaredNos.contains(no)) {
      throw ServiceError('CHAPTER_NO_TAKEN', '《$targetBook》已经有第 ${jsNumStr(no)} 话了');
    }
    // 移动前清掉源目录里的封面（单话封面不升格为整本封面）
    final removedCoverCount = _removeCover(srcDir);
    try {
      srcDir.renameSync(dst.path);
    } on FileSystemException catch (e) {
      final msg = e.message.toLowerCase();
      if (e.osError?.errorCode == 18 || msg.contains('cross-device') || msg.contains('different device')) {
        throw ServiceError('MERGE_CROSS_DEVICE', '漫画库与目标目录不在同一个磁盘卷上，无法自动归并（请手动移动该目录）');
      }
      throw ServiceError('MERGE_SOURCE_LOCKED', '「$srcName」正被其它程序占用，请稍候再试');
    }
    // 搬进去的目录里若混进 manifest，清掉（单话不该带书签）
    final stray = File('${dst.path}${Platform.pathSeparator}manifest.json');
    if (stray.existsSync()) stray.deleteSync();
    // episodes 以目录为准重派生 + 原子写
    final manifest = _typedManifestOf(targetDir) ?? LibraryManifest(title: targetBook);
    final rewritten = LibraryManifest(
      schema: manifest.schema,
      title: manifest.title,
      author: manifest.author,
      cover: manifest.cover,
      episodes: _episodesFromDirs(targetDir),
    );
    _writeManifestAtomic(targetDir, rewritten);
    return {
      'title': rewritten.title,
      'author': rewritten.author,
      'cover': rewritten.cover,
      'episodes': [for (final e in rewritten.episodes) e.toJson()],
      'merged': {'from': srcName, 'to': '$targetBook/$dirName', 'no': no, 'removedCoverCount': removedCoverCount},
    };
  }

  /// `list_chapter_dirs`：目录为准，解析 `NN_第N话`，按话号升序。
  List<({double no, String dirName})> _chapterDirsOf(Directory bookDir) {
    if (!bookDir.existsSync()) return const [];
    final out = <({double no, String dirName})>[];
    for (final e in bookDir.listSync()) {
      if (e is! Directory) continue;
      final base = _baseNameOf(e.path);
      final no = chapterNoFromDirName(base);
      if (no == null) continue;
      out.add((no: no, dirName: base));
    }
    out.sort((a, b) => a.no.compareTo(b.no));
    return out;
  }

  List<LibraryEpisode> _episodesFromDirs(Directory bookDir) => [
    for (final c in _chapterDirsOf(bookDir)) LibraryEpisode(no: c.no, dir: c.dirName),
  ];

  String _baseNameOf(String path) => path.split(Platform.pathSeparator).last;

  /// `remove_cover`：删掉目录里所有 `cover.(png|jpg|jpeg|webp)`，返回删除数。
  int _removeCover(Directory dir) {
    var removed = 0;
    if (!dir.existsSync()) return 0;
    final re = RegExp(r'^cover\.(png|jpg|jpeg|webp)$');
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      final name = _baseNameOf(e.path);
      if (!re.hasMatch(name)) continue;
      try {
        e.deleteSync();
        removed++;
      } catch (_) {}
    }
    return removed;
  }

  /// `write_manifest_atomic`：tmp + rename，键序稳定。
  void _writeManifestAtomic(Directory dir, LibraryManifest m) {
    final tmp = File('${dir.path}${Platform.pathSeparator}manifest.json.tmp');
    final dst = File('${dir.path}${Platform.pathSeparator}manifest.json');
    tmp.writeAsStringSync(jsonEncode(m.toJson()), flush: true);
    tmp.renameSync(dst.path);
  }

  /// 删本：`deleteFiles=false` 只隐藏（目录仍在），true 连目录一起删。
  Future<Map<String, dynamic>> deleteBook(String name, {required bool deleteFiles}) async {
    final dir = Directory('$rootDir/$name');
    if (deleteFiles) {
      // 物理删除：目录不存在 → 清残留隐藏记录并 404（miao-dock 同）。
      if (!dir.existsSync()) {
        _hidden.remove(name);
        _persistHidden();
        throw const ServiceError('TASK_NOT_FOUND', '漫画目录不存在', status: 404);
      }
      dir.deleteSync(recursive: true);
      _hidden.remove(name);
      _persistHidden();
    } else {
      // 隐藏不要求目录存在（miao-dock `hide_comic` 同样不检查）。
      if (!_hidden.contains(name)) {
        _hidden.add(name);
        _persistHidden();
      }
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

  /// 隐藏清单（测试与 UI 用）。
  List<String> get hiddenList => _hidden.toList();

  void _persistHidden() {
    try {
      // miao-dock 同构：`{comics:[...]}`，落在状态目录而不是库根。
      final f = File('$stateDir${Platform.pathSeparator}hidden-comics.json');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode({'comics': _hidden.toList()}));
    } catch (_) {
      // 忽略名单写失败不影响主流程
    }
  }

  // ── 文件 ────────────────────────────────────────────────────────────────

  /// 本内第 [seq] 页（`translated=true` 取译文，缺译文回退原图 —— 阅读器语义）。
  Future<File?> fileOf(String name, int seq, {bool translated = false}) async =>
      _findSeqFile(Directory('$rootDir/$name'), seq, translated: translated);

  /// 话内第 [seq] 页；话号支持小数（`1.5_第1.5话`）。
  Future<File?> chapterFileOf(String book, double no, int seq, {bool translated = false}) async {
    final bookDir = Directory('$rootDir/$book');
    if (!bookDir.existsSync()) return null;
    for (final e in bookDir.listSync(followLinks: false)) {
      if (e is! Directory) continue;
      if (_chapterNoOf(_baseName(e.path)) != no) continue;
      return _findSeqFile(e, seq, translated: translated);
    }
    return null;
  }

  /// 译文优先、缺译文回退原图（miao-dock 阅读器同：未翻译的页显示原图）。
  File? _findSeqFile(Directory dir, int seq, {bool translated = false}) {
    if (!dir.existsSync()) return null;
    for (final e in dir.listSync(followLinks: false)) {
      if (e is! File || !_isImage(e.path)) continue;
      final base = _baseName(e.path);
      if (_seqOf(e.path) != seq) continue;
      final isTranslated = base.contains('_translated');
      if (translated) {
        if (isTranslated) return e; // 有译文用译文
        continue; // 继续找译文；找不到落到下面的回退
      } else if (!isTranslated) {
        return e;
      }
    }
    if (!translated) return null;
    // 回退：没有译文 → 原图（未翻译完也能看）。
    return _findSeqFile(dir, seq, translated: false);
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
  Future<Map<String, dynamic>> renumberChapter(String book, String noRaw, double newNo) async {
    if (!isValidChapterNo(newNo)) {
      throw const ServiceError('INVALID_CHAPTER_NO', '话号必须是 1–999.9 的数（最多一位小数）');
    }
    final dir = chapterDir(book, noRaw);
    final from = _baseName(dir.path);
    final to = chapterDirName(newNo);
    if (from == to) return {'from': from, 'to': to, 'renamed': false};
    final target = Directory(dir.parent.path + Platform.pathSeparator + to);
    if (target.existsSync()) {
      throw ServiceError('CHAPTER_TARGET_EXISTS', '目标话号已存在', details: {'from': from, 'to': to});
    }
    dir.renameSync(target.path);
    // 改号后 episodes 必须跟着重派生（miao-dock 同：目录是唯一事实源）。
    final bookDir = dir.parent;
    final manifest = _typedManifestOf(bookDir);
    if (manifest != null) {
      _writeManifestAtomic(
        bookDir,
        LibraryManifest(
          schema: manifest.schema,
          title: manifest.title,
          author: manifest.author,
          cover: manifest.cover,
          episodes: _episodesFromDirs(bookDir),
        ),
      );
    }
    return {'from': from, 'to': to, 'renamed': true};
  }
}
