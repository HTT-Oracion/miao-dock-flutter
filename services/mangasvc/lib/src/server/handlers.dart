import 'dart:io';

import 'package:protocol/protocol.dart';

import '../engine/engine_facade.dart';
import '../queue/task_queue.dart';
import '../translate/youdao_client.dart';
import '../translate/youdao_errors.dart';
import '../translate/youdao_http.dart';
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
  factory Handlers({String? rootDir, String? runtimeRoot, String? modelsDir, String engineMode = 'mock'}) {
    final store = LibraryStore(rootDir: rootDir);
    final rt = runtimeRoot ?? _defaultEngineDir();
    final md = modelsDir ?? _defaultModelsDir();
    final facade = EngineFacade(runtimeRoot: rt, modelsDir: md);
    final queue = TaskQueue(engineMode: engineMode, rootDir: store.rootDir);
    // 真实模式：把引擎能力注入队列（D-057）。
    // mock 模式不注入 —— 那种模式下的「译文」是原图字节，仅供界面演示。
    if (engineMode != 'mock') queue.translateImage = facade.translateImage;
    return Handlers._(store, queue, facade, engineMode);
  }

  Handlers._(this.store, this.queue, this.engine, this.engineMode);

  final LibraryStore store;
  final TaskQueue queue;
  final EngineFacade engine;
  final String engineMode;

  /// 引擎目录默认根（`<数据根>/manga/engine`，与 `lib/core/storage/paths.dart` 同口径）。
  ///
  /// 这是「应用下载的一切」的根：python / src / bin/llama / models / llm（D-027）。
  static String _defaultEngineDir() {
    final env = Platform.environment;
    final override = env['MIAO_MANGA_ENGINE_DIR'];
    if (override != null && override.isNotEmpty) return override;
    return '${_dataRoot()}${Platform.pathSeparator}manga${Platform.pathSeparator}engine';
  }

  /// 模型目录默认值：`<engine>/models`（MIT 的 model_dir，D-027 废止 D-016）。
  static String _defaultModelsDir() {
    final env = Platform.environment;
    final override = env['MIAO_MODELS_DIR'];
    if (override != null && override.isNotEmpty) return override;
    return '${_defaultEngineDir()}${Platform.pathSeparator}models';
  }

  static String _dataRoot() {
    final env = Platform.environment;
    final override = env['MIAO_ROOT'];
    if (override != null && override.isNotEmpty) return override;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
    final String appData;
    if (Platform.isMacOS) {
      appData = '$home/Library/Application Support';
    } else if (Platform.isWindows) {
      appData = env['LOCALAPPDATA'] ?? '$home\\AppData\\Local';
    } else {
      appData = '$home/.local/share';
    }
    return '$appData${Platform.pathSeparator}MiaoDock';
  }

  /// 服务启动时刻（`/health` 用）。
  final DateTime startedAt = DateTime.now().toUtc();

  Future<void> init() => store.init();

  Future<void> dispose() async {
    await queue.dispose();
    await engine.dispose();
  }

  Future<void> handle(HttpRequest req, RouteMatch match) async {
    final r = match.route;
    final p = match.params;

    switch (r.id) {
      // ── health ──────────────────────────────────────────────────────────
      case 'GET /health':
      case 'GET /api/v1/health':
        await _health(req);
      case 'GET /api/v1/ping':
        await _ping(req);
      case 'POST /api/v1/translate/text':
        await _translateText(req);
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
      // ── engine（P0-C1~C5）───────────────────────────────────────────────
      case 'GET /api/v1/engine/status':
        await writeJson(req.response, 200, engine.status());
      case 'GET /api/v1/engine/runtime':
        await writeJson(req.response, 200, engine.runtimeProbe());
      case 'GET /api/v1/engine/options':
        await writeJson(req.response, 200, engine.options());
      case 'POST /api/v1/engine/settings':
        await writeJson(req.response, 200, await engine.applySettings(await readJsonBody(req)));
      case 'POST /api/v1/engine/unload':
        await writeJson(req.response, 200, await engine.unload());
      case 'POST /api/v1/engine/models/verify':
        await writeJson(req.response, 200, await engine.verifyModels());
      case 'POST /api/v1/engine/models/download':
        await writeJson(req.response, 200, await engine.startDownload());
      case 'POST /api/v1/engine/models/download/pause':
        await writeJson(req.response, 200, await engine.pauseDownload());
      case 'POST /api/v1/engine/start':
        await writeJson(req.response, 200, await engine.startEngine());
      case 'POST /api/v1/engine/stop':
        await writeJson(req.response, 200, await engine.stopEngine());
      case 'POST /api/v1/engine/install':
        final body = await readJsonBody(req);
        await writeJson(
          req.response,
          200,
          await engine.startInstall(
            engineDir: (body['engineDir'] as String?) ?? _defaultEngineDir(),
            backend: LlamaBackend.byId((body['backend'] as String?) ?? 'auto') ?? LlamaBackend.auto,
            includeNllb: body['includeNllb'] == true,
            parts: (body['parts'] as List?)?.whereType<String>().map(EnginePart.byId).whereType<EnginePart>().toSet(),
          ),
        );
      case 'GET /api/v1/engine/install':
        await writeJson(req.response, 200, engine.installStatus());
      case 'POST /api/v1/engine/deps/rebuild':
        final body = await readJsonBody(req);
        await writeJson(
          req.response,
          200,
          await engine.startDepsRebuild(
            engineDir: (body['engineDir'] as String?) ?? _defaultEngineDir(),
            indexUrl: body['indexUrl'] as String?,
          ),
        );
      case 'GET /api/v1/engine/deps':
        await writeJson(req.response, 200, engine.depsStatus());
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

  /// 文本翻译（D-053/D-054）：走在线平台，**不进引擎**。
  ///
  /// 这是「大模型翻译」与「本地翻译」的分界：本地翻译把文本交给引擎里的 Sakura，
  /// 这里直接调在线服务。
  ///
  /// 🔴 凭证**随请求传入**、用完即弃：唯一事实源是桌面端的系统钥匙串，
  /// 服务端不落盘（D-054 定案，撤销 D-052）。
  Future<void> _translateText(HttpRequest req) async {
    final body = await readJsonBody(req);
    final text = body['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const ServiceError('INVALID_TEXT', '待翻译文本不能为空');
    }
    final rawCred = body['credentials'];
    final cred = rawCred is Map ? Map<String, dynamic>.from(rawCred) : const <String, dynamic>{};
    final appKey = '${cred['appKey'] ?? ''}';
    final appSecret = '${cred['appSecret'] ?? ''}';
    if (appKey.isEmpty || appSecret.isEmpty) {
      throw const ServiceError('TRANSLATE_NOT_CONFIGURED', '未收到在线翻译密钥（appKey / appSecret）', status: 409);
    }

    final client = YoudaoClient(
      transport: youdaoTransport ?? makeYoudaoTransport(),
      baseUrl: youdaoBaseUrl(),
      appKey: appKey,
      appSecret: appSecret,
    );
    try {
      final result = await client.translateText(
        YoudaoTranslateRequest(text: text, from: '${body['from'] ?? 'ja'}', to: '${body['to'] ?? 'zh-CHS'}'),
      );
      await writeJson(req.response, 200, {'text': result.text, 'langType': result.langType});
    } on TranslateError catch (e) {
      await writeJson(req.response, 502, e.toJson());
    }
  }

  /// 远程连通性探测（D-045）。
  ///
  /// 能走到这里就说明**令牌是对的**（鉴权在路由之前）；返回内容再补齐
  /// 「对面引擎起没起」与「平台」两件事。
  Future<void> _ping(HttpRequest req) async {
    await writeJson(req.response, 200, {
      'ok': true,
      'service': 'mangasvc',
      'version': '0.1.0',
      'platform': Platform.operatingSystem,
      'engineReady': engineMode == 'ready',
      'engineMode': engineMode,
      'requiresToken': true,
      'serverTime': isoOf(DateTime.now()),
    });
  }

  // ── tasks ───────────────────────────────────────────────────────────────

  Future<void> _listTasks(HttpRequest req) async {
    final status = req.uri.queryParameters['status'];
    // `client` 是调用方自己的身份；`source` 是显式过滤。两者都支持，方便插件/手机端自证。
    final client = req.uri.queryParameters['client'];
    final source =
        req.uri.queryParameters['source'] ??
        switch (client) {
          'app' || 'mobile' => 'app',
          'plugin' || 'extension' => 'plugin',
          _ => null,
        };
    await writeJson(req.response, 200, queue.listView(status: status, source: source));
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
    // 来源归因（D-046）：**请求体 `client` 优先**，缺省回落到 `X-Box-Client` 头。
    // 定案用请求体字段（方案 B），保留 header 是为了兼容早期调用方。
    final bodyClient = body['client'];
    final client = (bodyClient is String && bodyClient.isNotEmpty)
        ? bodyClient
        : (req.headers.value('x-box-client') ?? 'desktop');
    final source = switch (client) {
      'app' || 'mobile' => 'app',
      'plugin' || 'extension' => 'plugin',
      _ => 'desktop',
    };
    final created = await queue.createTask(comicName: comicName.trim(), imagePaths: paths, source: source);
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
