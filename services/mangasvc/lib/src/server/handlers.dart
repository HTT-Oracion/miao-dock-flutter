import 'dart:convert';
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
  factory Handlers({
    String? rootDir,
    String? runtimeRoot,
    String? modelsDir,
    String? stateDir,
    String engineMode = 'mock',
  }) {
    final store = LibraryStore(rootDir: rootDir, stateDir: stateDir);
    final rt = runtimeRoot ?? _defaultEngineDir();
    final md = modelsDir ?? _defaultModelsDir();
    final facade = EngineFacade(runtimeRoot: rt, modelsDir: md);
    final queue = TaskQueue(engineMode: engineMode, rootDir: store.rootDir, stateDir: stateDir);
    // 真实模式：把引擎能力注入队列（D-057）。
    // mock 模式不注入 —— 那种模式下的「译文」是原图字节，仅供界面演示。
    if (engineMode != 'mock') {
      queue.translateImage = (bytes, onStage) => facade.translateImage(bytes, onStage: onStage);
    }
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

  Future<void> init() async {
    await store.init();
    await queue.load();
  }

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
      case 'GET /api/v1/translate/options':
        await _translateOptions(req);
      case 'POST /api/v1/translate/settings':
        await _translateSettings(req);
      case 'POST /api/v1/translate/stream':
        await _translateStream(req);
      case 'GET /api/v1/translate/log':
        await _translateLog(req);
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
      case 'POST /api/v1/library/{name}/merge':
        await _mergeBook(req, p['name']!);
      case 'POST /api/v1/library/{name}/reveal':
        await _revealBook(req, p['name']!);
      case 'POST /api/v1/library/{name}/resume':
        await _launchFromDir(req, _bookOrChapterDir(p['name']!), p['name']!, resume: true);
      case 'POST /api/v1/library/{name}/retranslate':
        await _launchFromDir(req, _bookOrChapterDir(p['name']!), p['name']!, resume: false);
      case 'POST /api/v1/library/{book}/chapters/{no}/resume':
        await _launchFromDir(req, _chapterDirOf(p['book']!, p['no']!), '${p['book']}/${p['no']}', resume: true);
      case 'POST /api/v1/library/{book}/chapters/{no}/retranslate':
        await _launchFromDir(req, _chapterDirOf(p['book']!, p['no']!), '${p['book']}/${p['no']}', resume: false);
      case 'GET /api/v1/library/{name}/files/{seq}':
        await _getBookFile(req, p['name']!, int.tryParse(p['seq'] ?? '') ?? 0);
      case 'GET /api/v1/library/{book}/chapters/{no}/files/{seq}':
        await _getChapterFile(req, p['book']!, double.tryParse(p['no'] ?? '') ?? 0, int.tryParse(p['seq'] ?? '') ?? 0);
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

  /// 翻译日志（D-075）：只回尾部，不回全量 —— 环形缓冲本来就是为「最近发生了什么」设计的。
  Future<void> _translateLog(HttpRequest req) async {
    await writeJson(req.response, 200, {'tail': queue.translateLogTail(), 'updatedAt': isoOf(DateTime.now())});
  }

  /// 文本翻译（D-053/D-054）：走在线平台，**不进引擎**。
  ///
  /// 这是「大模型翻译」与「本地翻译」的分界：本地翻译把文本交给引擎里的 Sakura，
  /// 这里直接调在线服务。
  ///
  /// 🔴 凭证**随请求传入**、用完即弃：唯一事实源是桌面端的系统钥匙串，
  /// 服务端不落盘（D-054 定案，撤销 D-052）。
  /// 可选项（方向 / 平台）：供设置页下拉使用。
  Future<void> _translateOptions(HttpRequest req) async {
    await writeJson(req.response, 200, {
      'platforms': ['youdaoZhiYun'],
      'settings': _translateSettingsView(),
      'sources': const <String>[],
      'credentials': const <String>[],
      'fileIssues': const {'exists': true, 'corrupt': false},
    });
  }

  /// 非密钥设置补丁：白名单 strict（未知键直接报错，不静默吞）。
  Future<void> _translateSettings(HttpRequest req) async {
    final body = await readJsonBody(req);
    const allowed = {'fromLang', 'toLang', 'platform'};
    final unknown = [
      for (final k in body.keys)
        if (!allowed.contains(k)) k,
    ];
    if (unknown.isNotEmpty) {
      throw ServiceError('INVALID_SETTING', '不支持的设置项：${unknown.join('、')}');
    }
    final file = _translateSettingsFile();
    final current = _translateSettingsView();
    final next = {...current, ...body};
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(next));
    await writeJson(req.response, 200, {'ok': true, 'changed': body.length, 'settings': next});
  }

  /// 流式文本翻译：**逐分片**推送（首包发头，之后每行一个 `data:`）。
  ///
  /// 与旧项目一致：长文本一次返回对用户没有意义，流式才能看到进度。
  Future<void> _translateStream(HttpRequest req) async {
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
    final res = req.response;
    res.statusCode = 200;
    res.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
    final client = YoudaoClient(
      transport: youdaoTransport ?? makeYoudaoTransport(),
      baseUrl: youdaoBaseUrl(),
      appKey: appKey,
      appSecret: appSecret,
    );
    try {
      final result = await client.translateText(
        YoudaoTranslateRequest(text: text, from: '${body['fromLang'] ?? 'ja'}', to: '${body['toLang'] ?? 'zh'}'),
      );
      res.write('data: ${jsonEncode({'type': 'result', 'text': result.text})}\n\n');
    } catch (e) {
      res.write('data: ${jsonEncode({'type': 'error', 'message': '$e'})}\n\n');
    }
    await res.close();
  }

  Map<String, dynamic> _translateSettingsView() {
    try {
      final f = _translateSettingsFile();
      if (!f.existsSync()) return {'platform': 'youdaoZhiYun', 'fromLang': 'ja', 'toLang': 'zh'};
      final m = jsonDecode(f.readAsStringSync());
      return m is Map ? Map<String, dynamic>.from(m) : const {};
    } catch (_) {
      return const {};
    }
  }

  File _translateSettingsFile() => File('${store.stateDir}${Platform.pathSeparator}translate-settings.json');

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
    // 规范化与旧项目 names.rs 一致（NFKC/剥非法字符/保留名/64 字符上限，D-079）。
    final nameResult = normalizeComicName(comicName);
    if (!nameResult.isOk) {
      throw ServiceError(nameResult.code!, nameResult.message!);
    }
    final normalized = nameResult.name!;
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
    final created = await queue.createTask(
      comicName: normalized,
      imagePaths: paths,
      source: source,
      langFrom: '${body['langFrom'] ?? 'ja'}',
      langTo: '${body['langTo'] ?? 'zh'}',
      translator: '${body['translator'] ?? 'sakura'}',
      clientTaskRef: body['clientTaskRef'] as String?,
      idempotencyKey: body['idempotencyKey'] as String?,
    );
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
    // 两种来源（miao-dock `coverFromFirstChapter` / 直接上传）：
    if (body['fromFirstChapter'] == true) {
      await store.writeCoverFromFirstChapter(name);
      await writeJson(req.response, 200, {'ok': true, 'source': 'firstChapter'});
      return;
    }
    final data = body['bytes'];
    if (data is! String || data.isEmpty) {
      throw const ServiceError('INVALID_IMAGE', '缺少封面数据');
    }
    await store.writeCover(name, base64Decode(data));
    await writeJson(req.response, 200, {'ok': true, 'source': 'inline'});
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

  /// 归并（D-083）：`POST /library/{src}/merge`，body `{targetBook|book|target, no}`。
  Future<void> _mergeBook(HttpRequest req, String name) async {
    final body = await readJsonBody(req);
    final targetRaw = body['targetBook'] ?? body['book'] ?? body['target'];
    final no = body['no'];
    if (targetRaw is! String || targetRaw.isEmpty || no is! num) {
      throw const ServiceError('INVALID_BOOK_META', '请求体缺少 targetBook/no');
    }
    final srcNorm = normalizeComicName(name);
    final targetNorm = normalizeComicName(targetRaw);
    if (!srcNorm.isOk || !targetNorm.isOk) {
      throw ServiceError(srcNorm.code ?? targetNorm.code!, srcNorm.message ?? targetNorm.message!);
    }
    final busy = queue.activeStatusesForDir(srcNorm.name!);
    final merged = await store.mergeBook(
      srcName: srcNorm.name!,
      targetBook: targetNorm.name!,
      no: no.toDouble(),
      busyStatuses: busy,
    );
    await writeJson(req.response, 200, merged);
  }

  Future<void> _getBookFile(HttpRequest req, String name, int seq) async {
    final variant = req.uri.queryParameters['variant'];
    final file = await store.fileOf(name, seq, translated: variant == 'translated');
    if (file == null) throw const ServiceError('NOT_FOUND', '文件不存在', status: 404);
    await _sendFile(req.response, file);
  }

  Future<void> _getChapterFile(HttpRequest req, String book, double no, int seq) async {
    final variant = req.uri.queryParameters['variant'];
    final file = await store.chapterFileOf(book, no, seq, translated: variant == 'translated');
    if (file == null) throw const ServiceError('NOT_FOUND', '文件不存在', status: 404);
    await _sendFile(req.response, file);
  }

  // ── 续做 / 返工计划（B7/B8）────────────────────────────────────────────

  /// 打开目录（reveal）。
  Future<void> _revealBook(HttpRequest req, String name) async {
    // name 可能是「书」或「书/话目录」：分段拼接并断言仍在库根内（防越界）。
    final parts = name.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) throw const ServiceError('NOT_FOUND', '目录不存在', status: 404);
    var dir = store.bookDir(parts.first);
    for (final seg in parts.skip(1)) {
      if (seg == '.' || seg == '..' || seg.contains('\\')) {
        throw const ServiceError('PERMISSION_DENIED', '路径越界', status: 403);
      }
      dir = Directory('${dir.path}${Platform.pathSeparator}$seg');
    }
    final rootPath = store.bookDir(parts.first).parent.path;
    if (!dir.path.startsWith(rootPath)) {
      throw const ServiceError('PERMISSION_DENIED', '路径越界', status: 403);
    }
    if (!dir.existsSync()) throw const ServiceError('NOT_FOUND', '目录不存在', status: 404);
    if (Platform.isMacOS) {
      await Process.run('open', [dir.path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [dir.path]);
    } else {
      await Process.run('xdg-open', [dir.path]);
    }
    await writeJson(req.response, 200, {'comicName': name, 'revealed': true});
  }

  /// 整本目录（`<root>/<name>`）。
  Directory _bookOrChapterDir(String name) => store.bookDir(name);

  /// 章节目录（`<root>/<book>/<NN_第N话>`），话号支持小数。
  Directory _chapterDirOf(String book, String noRaw) {
    final no = double.tryParse(noRaw);
    if (no == null || !isValidChapterNo(no)) {
      throw const ServiceError('INVALID_CHAPTER_NO', '话号必须是 1–999.9 的数（最多一位小数）');
    }
    final dir = Directory('${store.bookDir(book).path}${Platform.pathSeparator}${chapterDirName(no)}');
    if (!dir.existsSync()) throw const ServiceError('TASK_NOT_FOUND', '这本漫画没有这一话', status: 404);
    return dir;
  }

  /// 按目录（可选页子集）建任务：resume 只补缺译文的页；retranslate 重做全部页。
  Future<void> _launchFromDir(HttpRequest req, Directory dir, String label, {required bool resume}) async {
    final body = await readJsonBody(req);
    final wanted = (body['seqs'] as List?)?.cast<num>().map((e) => e.toInt()).toSet();
    // 目录可能是整本（多话）：逐个话目录扫；单话目录直接用。
    final targets = <Directory>[];
    if (chapterNoFromDirName(_dirName(dir.path)) != null) {
      targets.add(dir);
    } else {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is! Directory) continue;
        if (chapterNoFromDirName(_dirName(e.path)) == null) continue;
        targets.add(e);
      }
    }
    // 每个话目录单独建任务：任务落盘目录 = 该话目录（不能用整本书根，否则串层）。
    Map<String, dynamic>? first;
    var createdCount = 0;
    for (final d in targets) {
      final plan = resume ? buildResumePlan(_dirName(d.path), d) : buildRetranslatePlan(_dirName(d.path), d);
      final items = (resume ? plan['pendings'] : plan['candidates']) as List;
      final paths = <String>[
        for (final raw in items)
          if (wanted == null || wanted.contains((raw as Map<String, dynamic>)['seq'] as int))
            '${d.path}${Platform.pathSeparator}${(raw as Map<String, dynamic>)['originalFile']}',
      ];
      if (paths.isEmpty) continue;
      final created = await queue.createTask(
        comicName: label.contains('/') ? label.split('/').first : label,
        imagePaths: paths,
        source: 'library',
        targetDir: d.path,
      );
      first ??= created;
      createdCount++;
    }
    if (first == null) {
      throw const ServiceError('NO_PENDING_PAGES', '没有需要处理的页', status: 409);
    }
    await writeJson(req.response, 201, {...first, 'chapters': createdCount});
  }

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
    await writeJson(req.response, 200, await store.renumberChapter(book, no, newNo.toDouble()));
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
      final no = chapterNoFromDirName(dirName);
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
            for (final p in pendings.cast<Map<String, dynamic>>())
              {...p, 'seq': (no * 1000).round() + (p['seq'] as int)},
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
            for (final c in candidates.cast<Map<String, dynamic>>())
              {...c, 'seq': (no * 1000).round() + (c['seq'] as int)},
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
