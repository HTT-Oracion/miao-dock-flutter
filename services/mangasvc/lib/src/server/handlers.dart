import 'dart:io';

import '../queue/task_queue.dart';
import '../store/plans.dart';
import '../store/library_store.dart';
import 'http.dart';
import 'routes.dart';

/// 端点实现的分发层。
///
/// 职责：把 `RouteMatch` 映射到具体处理函数，读体、调门面、出信封。
/// 业务逻辑住在 `queue/` 与 `store/`，本层只做搬运（与客户端的分层对称）。
class Handlers {
  /// 用 factory 保证 `store` 与 `queue` 共用**同一个** rootDir，
  /// 而不是各建一个 LibraryStore 实例（那会在惰性默认值上产生两份真相）。
  factory Handlers({String? rootDir, String engineMode = 'mock'}) {
    final store = LibraryStore(rootDir: rootDir);
    return Handlers._(store, TaskQueue(engineMode: engineMode, rootDir: store.rootDir), engineMode);
  }

  Handlers._(this.store, this.queue, this.engineMode);

  final LibraryStore store;
  final TaskQueue queue;
  final String engineMode;

  /// 服务启动时刻（`/health` 用）。
  final DateTime startedAt = DateTime.now().toUtc();

  Future<void> init() => store.init();

  Future<void> dispose() async {
    await queue.dispose();
  }

  Future<void> handle(HttpRequest req, RouteMatch match) async {
    final r = match.route;
    final p = match.params;

    switch (r.id) {
      // ── health ──────────────────────────────────────────────────────────
      case 'GET /health':
      case 'GET /api/v1/health':
        await _health(req);
      // ── tasks ───────────────────────────────────────────────────────────
      case 'GET /api/v1/tasks':
        await _listTasks(req);
      case 'POST /api/v1/tasks':
        await _createTask(req);
      case 'GET /api/v1/tasks/{taskId}':
        await _getTask(req, p['taskId']!);
      case 'POST /api/v1/tasks/delete':
        await _deleteTasks(req);
      case 'POST /api/v1/tasks/{taskId}/cancel':
        await _cancelTask(req, p['taskId']!);
      case 'POST /api/v1/tasks/{taskId}/retry':
        await _retryTask(req, p['taskId']!);
      case 'POST /api/v1/tasks/{taskId}/batches':
        await _appendBatch(req, p['taskId']!);
      case 'GET /api/v1/tasks/{taskId}/events':
        await _taskEvents(req, p['taskId']!);
      // ── queue ───────────────────────────────────────────────────────────
      case 'GET /api/v1/queue':
        await _queue(req);
      // ── library ─────────────────────────────────────────────────────────
      case 'GET /api/v1/library':
        await _library(req);
      case 'POST /api/v1/library/create':
        await _createBook(req);
      case 'GET /api/v1/library/{name}/meta':
        await _getMeta(req, p['name']!);
      case 'POST /api/v1/library/{name}/meta':
        await _setMeta(req, p['name']!);
      case 'GET /api/v1/library/{name}/cover':
        await _getCover(req, p['name']!);
      case 'POST /api/v1/library/{name}/cover':
        await _setCover(req, p['name']!);
      case 'DELETE /api/v1/library/{name}/cover':
        await _deleteCover(req, p['name']!);
      case 'POST /api/v1/library/{name}/delete':
        await _deleteBook(req, p['name']!);
      case 'POST /api/v1/library/{name}/unhide':
        await _unhideBook(req, p['name']!);
      case 'GET /api/v1/library/{name}/files/{seq}':
        await _getBookFile(req, p['name']!, int.tryParse(p['seq'] ?? '') ?? 0);
      case 'GET /api/v1/library/{book}/chapters/{no}/files/{seq}':
        await _getChapterFile(req, p['book']!, int.tryParse(p['no'] ?? '') ?? 0, int.tryParse(p['seq'] ?? '') ?? 0);
      case 'GET /api/v1/library/{name}/resume':
        await _resumePlan(req, p['name']!);
      case 'GET /api/v1/library/{name}/retranslate':
        await _retranslatePlan(req, p['name']!);
      case 'GET /api/v1/library/{book}/chapters/{no}/resume':
        await _chapterResumePlan(req, p['book']!, p['no']!);
      case 'GET /api/v1/library/{book}/chapters/{no}/retranslate':
        await _chapterRetranslatePlan(req, p['book']!, p['no']!);
      case 'POST /api/v1/library/{book}/chapters/{no}/renumber':
        await _renumberChapter(req, p['book']!, p['no']!);
      // ── 尚未实现（P0-B 其余项）──────────────────────────────────────────
      default:
        await writeErrorCode(req.response, 501, 'NOT_IMPLEMENTED', '端点尚未实现：${r.id}');
    }
  }

  // ── health ──────────────────────────────────────────────────────────────

  Future<void> _health(HttpRequest req) async {
    await writeJson(req.response, 200, {
      'status': 'ok',
      'service': 'mangasvc',
      'version': '0.1.0',
      'apiVersion': 'v1',
      'sidecar': {'state': 'ready', 'port': req.connectionInfo?.localPort, 'engine': engineMode},
      'rootDir': store.rootDir,
      'startedAt': isoOf(startedAt),
    });
  }

  // ── tasks ───────────────────────────────────────────────────────────────

  Future<void> _listTasks(HttpRequest req) async {
    final status = req.uri.queryParameters['status'];
    await writeJson(req.response, 200, queue.listView(status: status));
  }

  Future<void> _createTask(HttpRequest req) async {
    final body = await readJsonBody(req);
    final comicName = body['comicName'];
    final imagePaths = body['imagePaths'];
    if (comicName is! String || comicName.trim().isEmpty) {
      throw const ServiceError('INVALID_COMIC_NAME', '漫画名不能为空');
    }
    if (imagePaths is! List || imagePaths.isEmpty) {
      throw const ServiceError('INVALID_IMAGES', '没有可用图片');
    }
    final paths = imagePaths.whereType<String>().toList();
    final created = await queue.createTask(comicName: comicName.trim(), imagePaths: paths);
    await writeJson(req.response, 200, created);
  }

  Future<void> _getTask(HttpRequest req, String id) async {
    final row = queue.getTask(id);
    if (row == null) throw const ServiceError('NOT_FOUND', '任务不存在', status: 404);
    await writeJson(req.response, 200, row);
  }

  Future<void> _deleteTasks(HttpRequest req) async {
    final body = await readJsonBody(req);
    final ids = body['taskIds'];
    final target = ids is List ? ids.whereType<String>().toSet() : null;
    await writeJson(req.response, 200, queue.deleteTasks(target));
  }

  Future<void> _cancelTask(HttpRequest req, String id) async {
    await writeJson(req.response, 200, await queue.cancelTask(id));
  }

  Future<void> _retryTask(HttpRequest req, String id) async {
    await writeJson(req.response, 200, await queue.retryTask(id));
  }

  Future<void> _appendBatch(HttpRequest req, String id) async {
    final body = await readJsonBody(req);
    final images = body['imagePaths'];
    if (images is! List || images.isEmpty) {
      throw const ServiceError('INVALID_IMAGES', '没有可用图片');
    }
    await writeJson(req.response, 200, await queue.appendBatch(id, images.whereType<String>().toList()));
  }

  /// SSE 进度流。
  Future<void> _taskEvents(HttpRequest req, String id) async {
    final res = req.response;
    res.statusCode = 200;
    res.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
    res.headers.set('Cache-Control', 'no-cache');
    res.headers.set('Connection', 'keep-alive');
    await for (final event in queue.events(id)) {
      res.write('event: ${event['type']}\n');
      res.write('data: ${event['data']}\n\n');
      await res.flush();
      if (event['type'] == 'done' || event['type'] == 'failed' || event['type'] == 'canceled') break;
    }
    await res.close();
  }

  // ── queue ───────────────────────────────────────────────────────────────

  Future<void> _queue(HttpRequest req) async {
    await writeJson(req.response, 200, queue.snapshot());
  }

  // ── library ─────────────────────────────────────────────────────────────

  Future<void> _library(HttpRequest req) async {
    await writeJson(req.response, 200, await store.scan());
  }

  Future<void> _createBook(HttpRequest req) async {
    final body = await readJsonBody(req);
    final name = body['bookName'];
    if (name is! String || name.trim().isEmpty) {
      throw const ServiceError('INVALID_BOOK_NAME', '漫画名不能为空');
    }
    await store.createBook(name.trim());
    await writeJson(req.response, 200, {'ok': true});
  }

  Future<void> _getMeta(HttpRequest req, String name) async {
    await writeJson(req.response, 200, await store.readMeta(name));
  }

  Future<void> _setMeta(HttpRequest req, String name) async {
    final body = await readJsonBody(req);
    await store.writeMeta(name, body);
    await writeJson(req.response, 200, {'ok': true});
  }

  Future<void> _getCover(HttpRequest req, String name) async {
    final bytes = await store.readCover(name);
    if (bytes == null) {
      throw const ServiceError('NOT_FOUND', '该本没有封面', status: 404);
    }
    final res = req.response;
    res.statusCode = 200;
    res.headers.contentType = ContentType('image', 'png');
    res.headers.contentLength = bytes.length;
    res.add(bytes);
    await res.close();
  }

  Future<void> _setCover(HttpRequest req, String name) async {
    final body = await readJsonBody(req);
    final data = body['bytes'];
    if (data is! String || data.isEmpty) {
      throw const ServiceError('INVALID_IMAGE', '缺少封面数据');
    }
    await store.writeCover(name, data);
    await writeJson(req.response, 200, {'ok': true});
  }

  Future<void> _deleteCover(HttpRequest req, String name) async {
    await store.deleteCover(name);
    await writeJson(req.response, 200, {'ok': true});
  }

  Future<void> _deleteBook(HttpRequest req, String name) async {
    final body = await readJsonBody(req);
    final deleteFiles = body['deleteFiles'] == true;
    await writeJson(req.response, 200, await store.deleteBook(name, deleteFiles: deleteFiles));
  }

  Future<void> _unhideBook(HttpRequest req, String name) async {
    await store.unhide(name);
    await writeJson(req.response, 200, {'ok': true});
  }

  Future<void> _getBookFile(HttpRequest req, String name, int seq) async {
    final file = await store.fileOf(name, seq);
    if (file == null) throw const ServiceError('NOT_FOUND', '文件不存在', status: 404);
    await _sendFile(req.response, file);
  }

  Future<void> _getChapterFile(HttpRequest req, String book, int no, int seq) async {
    final file = await store.chapterFileOf(book, no, seq);
    if (file == null) throw const ServiceError('NOT_FOUND', '文件不存在', status: 404);
    await _sendFile(req.response, file);
  }

  // ── 续做 / 返工计划（B7/B8）────────────────────────────────────────────

  /// 整本续做计划：本目录下所有话的待补页汇总。
  Future<void> _resumePlan(HttpRequest req, String name) async {
    final dir = store.bookDir(name);
    final merged = await _aggregatePlan(dir, name, resume: true);
    await writeJson(req.response, 200, merged);
  }

  /// 整本返工计划。
  Future<void> _retranslatePlan(HttpRequest req, String name) async {
    final dir = store.bookDir(name);
    final merged = await _aggregatePlan(dir, name, resume: false);
    await writeJson(req.response, 200, merged);
  }

  /// 单话续做计划。
  Future<void> _chapterResumePlan(HttpRequest req, String book, String no) async {
    final dir = store.chapterDir(book, no);
    await writeJson(req.response, 200, buildResumePlan(_dirName(dir.path), dir));
  }

  /// 单话返工计划。
  Future<void> _chapterRetranslatePlan(HttpRequest req, String book, String no) async {
    final dir = store.chapterDir(book, no);
    await writeJson(req.response, 200, buildRetranslatePlan(_dirName(dir.path), dir));
  }

  /// 改话号。
  Future<void> _renumberChapter(HttpRequest req, String book, String no) async {
    final body = await readJsonBody(req);
    final newNo = body['no'];
    if (newNo is! num) {
      throw const ServiceError('INVALID_CHAPTER_NO', '缺少目标话号（no）');
    }
    await writeJson(req.response, 200, await store.renumberChapter(book, no, newNo.toInt()));
  }

  /// 整本计划：把每个话目录的计划合并成一个。
  ///
  /// 整本的 `seq` 用「话序号 × 1000 + 页序号」编码，保证跨话唯一且有序；
  /// UI 需要分话展示时按 [chapterNo] 分组。
  Future<Map<String, dynamic>> _aggregatePlan(Directory bookDir, String name, {required bool resume}) async {
    final chapters = <Map<String, dynamic>>[];
    var imageCount = 0;
    var translatedCount = 0;
    var total = 0;
    var overwrite = 0;

    for (final e in bookDir.listSync(followLinks: false)) {
      if (e is! Directory) continue;
      final dirName = _dirName(e.path);
      final no = int.tryParse(RegExp(r'^(\d+)').firstMatch(dirName)?.group(1) ?? '');
      if (no == null) continue;

      if (resume) {
        final plan = buildResumePlan(dirName, e);
        final pendings = plan['pendings'] as List;
        if (pendings.isEmpty) continue;
        imageCount += plan['imageCount'] as int;
        translatedCount += plan['translatedCount'] as int;
        total += pendings.length;
        chapters.add({
          'chapterNo': no,
          'chapterDir': dirName,
          'pendings': [
            for (final p in pendings.cast<Map<String, dynamic>>()) {...p, 'seq': no * 1000 + (p['seq'] as int)},
          ],
        });
      } else {
        final plan = buildRetranslatePlan(dirName, e);
        final candidates = plan['candidates'] as List;
        if (candidates.isEmpty) continue;
        imageCount += plan['imageCount'] as int;
        translatedCount += plan['translatedCount'] as int;
        total += candidates.length;
        overwrite += plan['overwriteCount'] as int;
        chapters.add({
          'chapterNo': no,
          'chapterDir': dirName,
          'candidates': [
            for (final c in candidates.cast<Map<String, dynamic>>()) {...c, 'seq': no * 1000 + (c['seq'] as int)},
          ],
        });
      }
    }

    final base = {
      'comicName': name,
      'dirName': name,
      'outputDir': bookDir.path,
      'imageCount': imageCount,
      'translatedCount': translatedCount,
      'chapterPlans': chapters,
    };
    if (resume) {
      return {
        ...base,
        'pendingCount': total,
        'translatedSeqs': const <int>[],
        'pendings': const <Map<String, dynamic>>[],
      };
    }
    return {
      ...base,
      'retranslateCount': total,
      'overwriteCount': overwrite,
      'candidates': const <Map<String, dynamic>>[],
    };
  }

  String _dirName(String path) => path.split(Platform.pathSeparator).last;

  Future<void> _sendFile(HttpResponse res, File file) async {
    final bytes = await file.readAsBytes();
    res.statusCode = 200;
    res.headers.contentType = ContentType('application', 'octet-stream');
    res.headers.contentLength = bytes.length;
    res.add(bytes);
    await res.close();
  }
}
