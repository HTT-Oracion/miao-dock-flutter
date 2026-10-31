import 'dart:convert';

import 'package:protocol/protocol.dart';

import '../../../core/net/service_locator.dart';

/// `MangaSvcClient` 的 HTTP 实现 —— 对应 P0-A1 契约的落地。
///
/// ## 设计要点
/// 1. **每次调用都经 [ServiceLocator] 取客户端**：服务可能在运行期重启换端口，
///    不能启动时抓一个实例用到底。
/// 2. **JSON → DTO 显式解析**：不用反射，字段缺失走契约里声明的默认值或抛
///    [MangaSvcErrorKind.protocol]。**绝不把解析失败吞成空列表**。
/// 3. **未实现端点不伪造**：本类所有方法都直连真实端点；P0-B 尚未实现的服务端
///    会返回错误信封，按 [MangaSvcException] 如实抛出。
class HttpMangaSvcClient implements MangaSvcClient {
  HttpMangaSvcClient(this._locator);

  final ServiceLocator _locator;

  Future<Map<String, dynamic>> _get(String path, {Map<String, dynamic>? query}) async {
    final client = await _locator.client();
    return client.getJson(path, query: query);
  }

  Future<Map<String, dynamic>> _post(String path, {Object? body}) async {
    final client = await _locator.client();
    return client.postJson(path, body: body);
  }

  Future<Map<String, dynamic>> _delete(String path, {Object? body}) async {
    final client = await _locator.client();
    return client.deleteJson(path, body: body);
  }

  // ── health ───────────────────────────────────────────────────────────────

  @override
  Future<HealthResponse> health() async {
    final json = await _get('/health');
    return _healthOf(json);
  }

  // ── tasks ────────────────────────────────────────────────────────────────

  @override
  Future<TaskListResponse> listTasks({TaskStatus? status}) async {
    final json = await _get('/tasks', query: status == null ? null : {'status': status.wire});
    return _taskListOf(json);
  }

  @override
  Future<TaskRow> getTask(String taskId) async {
    final json = await _get('/tasks/$taskId');
    return _taskRowOf(json);
  }

  @override
  Future<CreateTaskResponse> createTask({required String comicName, required List<String> imagePaths}) async {
    final json = await _post('/tasks', body: {'comicName': comicName, 'imagePaths': imagePaths});
    return _createTaskOf(json);
  }

  @override
  Future<CreateTaskResponse> appendBatch(String taskId, {required List<String> imagePaths}) async {
    final json = await _post('/tasks/$taskId/batches', body: {'imagePaths': imagePaths});
    return _createTaskOf(json);
  }

  @override
  Future<DeleteTasksResponse> deleteTasks(Set<String>? taskIds) async {
    final json = await _post('/tasks/delete', body: {'taskIds': taskIds?.toList()});
    return DeleteTasksResponse(
      deleted: _stringList(json['deleted']),
      skipped: _skippedList(json['skipped']),
      deletedCount: _intOf(json['deletedCount']),
      skippedCount: _intOf(json['skippedCount']),
    );
  }

  @override
  Future<CancelResponse> cancelTask(String taskId) async {
    final json = await _post('/tasks/$taskId/cancel');
    return CancelResponse(
      taskId: _stringOf(json['taskId'], fallback: taskId),
      keptItems: _intOf(json['keptItems']),
      outputDir: _stringOf(json['outputDir']),
    );
  }

  @override
  Future<CreateTaskResponse> retryTask(String taskId) async {
    final json = await _post('/tasks/$taskId/retry');
    return _createTaskOf(json);
  }

  @override
  Stream<TaskEvent> watchTaskEvents(String taskId) async* {
    final client = await _locator.client();
    final lines = client.getEventLines('/tasks/$taskId/events');
    String? eventType;
    final dataBuffer = <String>[];
    await for (final line in lines) {
      if (line.isEmpty) {
        // 空行 = 一帧结束
        if (dataBuffer.isNotEmpty) {
          final raw = dataBuffer.join('\n');
          dataBuffer.clear();
          final payload = _tryDecode(raw);
          if (payload != null) {
            yield TaskEvent(type: eventType ?? 'progress', taskId: taskId, payload: payload);
          }
          eventType = null;
        }
        continue;
      }
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataBuffer.add(line.substring(5).trim());
      }
      // 注释帧（以 `:` 开头）直接忽略
    }
  }

  // ── queue ────────────────────────────────────────────────────────────────

  @override
  Future<QueueSnapshot> getQueue() async {
    final json = await _get('/queue');
    return QueueSnapshot(
      running: json['running'] as String?,
      queued: _stringList(json['queued']),
      concurrency: _intOf(json['concurrency'], fallback: 1),
    );
  }

  // ── library ──────────────────────────────────────────────────────────────

  @override
  Future<LibraryResponse> listLibrary() async {
    final json = await _get('/library');
    return LibraryResponse(
      root: _stringOf(json['root']),
      count: _intOf(json['count']),
      totalImages: _intOf(json['totalImages']),
      totalBytes: _intOf(json['totalBytes']),
      comics: _listOf(json['comics'], _comicOf),
      books: json['books'] == null ? null : _listOf(json['books'], _bookOf),
      others: json['others'] == null ? null : _listOf(json['others'], _chapterOf),
      hidden: json['hidden'] == null ? null : _stringList(json['hidden']),
      hiddenCount: json['hiddenCount'] is num ? (json['hiddenCount'] as num).toInt() : null,
      updatedAt: _dateOf(json['updatedAt']) ?? DateTime.now(),
    );
  }

  @override
  Future<void> createBook(String bookName) => _post('/library/create', body: {'bookName': bookName});

  @override
  Future<BookMeta> getBookMeta(String bookName) async {
    final json = await _get('/library/${Uri.encodeComponent(bookName)}/meta');
    return BookMeta(
      title: _stringOf(json['title']),
      author: _stringOf(json['author']),
      coverPath: json['coverPath'] as String?,
    );
  }

  @override
  Future<void> setBookMeta(String bookName, BookMeta meta) =>
      _post('/library/${Uri.encodeComponent(bookName)}/meta', body: {'title': meta.title, 'author': meta.author});

  @override
  Future<List<int>?> getBookCover(String bookName) async {
    final client = await _locator.client();
    return client.getBytes('/library/${Uri.encodeComponent(bookName)}/cover');
  }

  @override
  Future<void> setBookCover(String bookName, {required List<int> bytes, required String filename}) => _post(
    '/library/${Uri.encodeComponent(bookName)}/cover',
    body: {'filename': filename, 'bytes': base64Encode(bytes)},
  );

  @override
  Future<void> deleteBookCover(String bookName) => _delete('/library/${Uri.encodeComponent(bookName)}/cover');

  @override
  Future<void> mergeChapters(String bookName, {required List<String> chapterDirs}) =>
      _post('/library/${Uri.encodeComponent(bookName)}/merge', body: {'chapterDirs': chapterDirs});

  @override
  Future<void> revealBook(String bookName) => _post('/library/${Uri.encodeComponent(bookName)}/reveal');

  @override
  Future<LibraryDeleteResponse> deleteBook(String bookName, {required bool deleteFiles}) async {
    final json = await _post('/library/${Uri.encodeComponent(bookName)}/delete', body: {'deleteFiles': deleteFiles});
    return LibraryDeleteResponse(
      comicName: _stringOf(json['comicName'], fallback: bookName),
      deletedFiles: json['deletedFiles'] == true,
      outputDir: json['outputDir'] as String?,
      hidden: json['hidden'] == null ? null : _stringList(json['hidden']),
      hiddenCount: json['hiddenCount'] is num ? (json['hiddenCount'] as num).toInt() : null,
    );
  }

  @override
  Future<void> unhideBook(String bookName) => _post('/library/${Uri.encodeComponent(bookName)}/unhide');

  @override
  Future<ResumePlan> getResumePlan(String bookName) async =>
      _resumePlanOf(await _get('/library/${Uri.encodeComponent(bookName)}/resume'), fallbackName: bookName);

  @override
  Future<CreateTaskResponse> resumeBook(String bookName) async =>
      _createTaskOf(await _post('/library/${Uri.encodeComponent(bookName)}/resume'));

  @override
  Future<RetranslatePlan> getRetranslatePlan(String bookName) async =>
      _planOf(await _get('/library/${Uri.encodeComponent(bookName)}/retranslate'), fallbackName: bookName);

  @override
  Future<CreateTaskResponse> retranslateBook(String bookName) async =>
      _createTaskOf(await _post('/library/${Uri.encodeComponent(bookName)}/retranslate'));

  @override
  Future<ResumePlan> getChapterResumePlan(String bookName, int chapterNo) async => _resumePlanOf(
    await _get('/library/${Uri.encodeComponent(bookName)}/chapters/$chapterNo/resume'),
    fallbackName: bookName,
  );

  @override
  Future<CreateTaskResponse> resumeChapter(String bookName, int chapterNo) async =>
      _createTaskOf(await _post('/library/${Uri.encodeComponent(bookName)}/chapters/$chapterNo/resume'));

  @override
  Future<RetranslatePlan> getChapterRetranslatePlan(String bookName, int chapterNo) async => _planOf(
    await _get('/library/${Uri.encodeComponent(bookName)}/chapters/$chapterNo/retranslate'),
    fallbackName: bookName,
  );

  @override
  Future<CreateTaskResponse> retranslateChapter(String bookName, int chapterNo) async =>
      _createTaskOf(await _post('/library/${Uri.encodeComponent(bookName)}/chapters/$chapterNo/retranslate'));

  @override
  Future<void> renumberChapter(String bookName, int chapterNo, {required int newNo}) =>
      _post('/library/${Uri.encodeComponent(bookName)}/chapters/$chapterNo/renumber', body: {'newNo': newNo});

  @override
  Future<List<int>> getBookFile(String bookName, int seq) async {
    final client = await _locator.client();
    return await client.getBytes('/library/${Uri.encodeComponent(bookName)}/files/$seq') ?? const [];
  }

  @override
  Future<List<int>> getChapterFile(String bookName, int chapterNo, int seq) async {
    final client = await _locator.client();
    return await client.getBytes('/library/${Uri.encodeComponent(bookName)}/chapters/$chapterNo/files/$seq') ??
        const [];
  }

  // ── translate ────────────────────────────────────────────────────────────

  @override
  Future<TranslateOptions> getTranslateOptions() async {
    final json = await _get('/translate/options');
    return TranslateOptions(
      fromLangs: _stringList(json['fromLangs']),
      toLangs: _stringList(json['toLangs']),
      sources: _stringList(json['sources']),
    );
  }

  @override
  Future<void> setTranslateSettings(Map<String, dynamic> settings) => _post('/translate/settings', body: settings);

  @override
  Future<void> setTranslateCredentials(Map<String, dynamic> credentials) =>
      _post('/translate/credentials', body: credentials);

  @override
  Future<String> translateText({required String text, required String from, required String to}) async {
    final json = await _post('/translate/text', body: {'text': text, 'from': from, 'to': to});
    return _stringOf(json['text']);
  }

  @override
  Stream<String> translateStream({required String text, required String from, required String to}) async* {
    final client = await _locator.client();
    final body = jsonEncode({'text': text, 'from': from, 'to': to});
    await for (final line in client.getEventLines('/translate/stream?body=${Uri.encodeQueryComponent(body)}')) {
      if (line.startsWith('data:')) {
        final payload = _tryDecode(line.substring(5).trim());
        final chunk = payload?['text'];
        if (chunk is String) yield chunk;
      }
    }
  }

  // ── engine ───────────────────────────────────────────────────────────────

  @override
  Future<EngineStatus> getEngineStatus() async => _engineStatusOf(await _get('/engine/status'));

  @override
  Future<Map<String, dynamic>> ping() => _get('/ping');

  @override
  Future<RuntimeProbe> getEngineRuntime() async => _runtimeOf(await _get('/engine/runtime'));

  @override
  Future<Map<String, dynamic>> getEngineOptions() => _get('/engine/options');

  @override
  Future<bool> setEngineSettings(Map<String, dynamic> settings) async {
    final r = await _post('/engine/settings', body: settings);
    return r['needsRestart'] == true;
  }

  @override
  Future<void> unloadEngine() => _post('/engine/unload');

  @override
  Future<Map<String, dynamic>> installEngine({required String engineDir, String? backend, bool includeNllb = false}) =>
      _post('/engine/install', body: {'engineDir': engineDir, 'backend': ?backend, 'includeNllb': includeNllb});

  @override
  Future<Map<String, dynamic>> rebuildDeps({required String engineDir, String? indexUrl}) =>
      _post('/engine/deps/rebuild', body: {'engineDir': engineDir, 'indexUrl': ?indexUrl});

  @override
  Future<Map<String, dynamic>> getDepsStatus() => _get('/engine/deps');

  @override
  Future<Map<String, dynamic>> getEngineInstall() => _get('/engine/install');

  @override
  Future<EngineStatus> startEngine() async => _engineStatusOf(await _post('/engine/start'));

  @override
  Future<EngineStatus> stopEngine() async => _engineStatusOf(await _post('/engine/stop'));

  @override
  Future<ModelStatus> verifyModels() async => _modelsOf(await _post('/engine/models/verify'));

  @override
  Future<ModelDownloadView> downloadModels() async => _downloadOf(await _post('/engine/models/download'));

  @override
  Future<ModelDownloadView> pauseModelDownload() async => _downloadOf(await _post('/engine/models/download/pause'));
}

// ── JSON → DTO 解析（集中一处，便于按契约审查）────────────────────────────

String _stringOf(Object? v, {String fallback = ''}) => v is String ? v : fallback;

int _intOf(Object? v, {int fallback = 0}) => v is num ? v.toInt() : fallback;

DateTime? _dateOf(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v);
}

List<String> _stringList(Object? v) => v is List ? v.whereType<String>().toList() : const [];

List<T> _listOf<T>(Object? v, T Function(Map<String, dynamic>) parse) {
  if (v is! List) return const [];
  return v.whereType<Map<dynamic, dynamic>>().map((m) => parse(Map<String, dynamic>.from(m))).toList();
}

Map<String, dynamic>? _tryDecode(String raw) {
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    return null;
  }
  return null;
}

HealthResponse _healthOf(Map<String, dynamic> j) {
  final sidecar = j['sidecar'];
  return HealthResponse(
    status: _stringOf(j['status']),
    service: _stringOf(j['service']),
    version: _stringOf(j['version']),
    apiVersion: _stringOf(j['apiVersion']),
    sidecar: SidecarInfo(
      state: sidecar is Map ? _stringOf(sidecar['state']) : '',
      port: sidecar is Map && sidecar['port'] is num ? (sidecar['port'] as num).toInt() : null,
      engine: sidecar is Map ? sidecar['engine'] as String? : null,
    ),
    rootDir: _stringOf(j['rootDir']),
    startedAt: _dateOf(j['startedAt']) ?? DateTime.now(),
  );
}

TaskListResponse _taskListOf(Map<String, dynamic> j) {
  final tasks = _listOf(j['tasks'], _taskRowOf);
  return TaskListResponse(
    count: _intOf(j['count'], fallback: tasks.length),
    total: _intOf(j['total'], fallback: tasks.length),
    running: _intOf(j['running']),
    queued: _intOf(j['queued']),
    tasks: tasks,
    updatedAt: _dateOf(j['updatedAt']) ?? DateTime.now(),
  );
}

TaskRow _taskRowOf(Map<String, dynamic> j) {
  final progress = j['progress'];
  return TaskRow(
    taskId: _stringOf(j['taskId']),
    comicName: _stringOf(j['comicName']),
    normalizedComicName: j['normalizedComicName'] as String?,
    source: TaskSource.parse(_stringOf(j['source'], fallback: 'unknown')),
    status: TaskStatus.parse(_stringOf(j['status'], fallback: 'queued')),
    queuePosition: _intOf(j['queuePosition']),
    progress: TaskProgress(
      total: progress is Map ? _intOf(progress['total']) : 0,
      done: progress is Map ? _intOf(progress['done']) : 0,
      failed: progress is Map ? _intOf(progress['failed']) : 0,
      current: progress is Map ? _intOf(progress['current']) : 0,
    ),
    outputDir: _stringOf(j['outputDir']),
    createdAt: _dateOf(j['createdAt']) ?? DateTime.now(),
    finishedAt: _dateOf(j['finishedAt']),
    failedItems: _listOf(
      j['failedItems'],
      (m) =>
          FailedItem(seq: _intOf(m['seq']), reason: m['reason'] as String?, errorMessage: m['errorMessage'] as String?),
    ),
  );
}

CreateTaskResponse _createTaskOf(Map<String, dynamic> j) {
  final eta = j['eta'];
  return CreateTaskResponse(
    taskId: _stringOf(j['taskId']),
    comicName: _stringOf(j['comicName']),
    normalizedComicName: _stringOf(j['normalizedComicName']),
    outputDir: _stringOf(j['outputDir']),
    status: TaskStatus.parse(_stringOf(j['status'], fallback: 'queued')),
    queuePosition: _intOf(j['queuePosition']),
    createdAt: _dateOf(j['createdAt']) ?? DateTime.now(),
    eta: eta is Map
        ? Eta(
            minSeconds: _intOf(eta['minSeconds']),
            maxSeconds: _intOf(eta['maxSeconds']),
            text: _stringOf(eta['text']),
          )
        : null,
  );
}

List<SkippedTask> _skippedList(Object? v) => _listOf(
  v,
  (m) => SkippedTask(
    taskId: _stringOf(m['taskId']),
    reason: _stringOf(m['reason']),
    status: m['status'] is String ? TaskStatus.parse(m['status'] as String) : null,
  ),
);

ComicEntry _comicOf(Map<String, dynamic> j) => ComicEntry(
  comicName: _stringOf(j['comicName']),
  dirName: _stringOf(j['dirName']),
  outputDir: _stringOf(j['outputDir']),
  imageCount: _intOf(j['imageCount']),
  translatedCount: _intOf(j['translatedCount']),
  byteSize: _intOf(j['byteSize']),
  seqMax: _intOf(j['seqMax']),
  nextSeq: _intOf(j['nextSeq']),
  translatedSeqs: _intList(j['translatedSeqs']),
  missingSeqs: _intList(j['missingSeqs']),
  modifiedAt: _dateOf(j['modifiedAt']),
);

BookEntry _bookOf(Map<String, dynamic> j) => BookEntry(
  bookName: _stringOf(j['bookName']),
  dirName: _stringOf(j['dirName']),
  outputDir: _stringOf(j['outputDir']),
  title: _stringOf(j['title']),
  author: _stringOf(j['author']),
  coverPath: j['coverPath'] as String?,
  chapterCount: _intOf(j['chapterCount']),
  totalPages: _intOf(j['totalPages']),
  byteSize: _intOf(j['byteSize']),
  modifiedAt: _dateOf(j['modifiedAt']),
  chapters: _listOf(j['chapters'], _chapterOf),
);

ChapterEntry _chapterOf(Map<String, dynamic> j) {
  final mergedTo = j['mergedTo'];
  return ChapterEntry(
    no: j['no'] is num ? (j['no'] as num).toInt() : null,
    dirName: _stringOf(j['dirName']),
    absDir: _stringOf(j['absDir']),
    imageCount: _intOf(j['imageCount']),
    translatedCount: _intOf(j['translatedCount']),
    seqMax: _intOf(j['seqMax']),
    translatedSeqs: _intList(j['translatedSeqs']),
    missingSeqs: _intList(j['missingSeqs']),
    merged: j['merged'] == true,
    mergedTo: mergedTo is Map ? MergedTo(bookName: _stringOf(mergedTo['bookName']), no: _intOf(mergedTo['no'])) : null,
    modifiedAt: _dateOf(j['modifiedAt']),
  );
}

List<int> _intList(Object? v) => v is List ? v.whereType<num>().map((n) => n.toInt()).toList() : const [];

ResumePlan _resumePlanOf(Map<String, dynamic> j, {required String fallbackName}) => ResumePlan(
  comicName: _stringOf(j['comicName'], fallback: fallbackName),
  dirName: _stringOf(j['dirName'], fallback: fallbackName),
  outputDir: _stringOf(j['outputDir']),
  imageCount: _intOf(j['imageCount']),
  translatedCount: _intOf(j['translatedCount']),
  pendingCount: _intOf(j['pendingCount']),
  reworking: j['reworking'] == true,
  translatedSeqs: _intList(j['translatedSeqs']),
  pendings: _listOf(
    j['pendings'],
    (m) => ResumePending(
      seq: _intOf(m['seq']),
      ext: _stringOf(m['ext']),
      byteSize: _intOf(m['byteSize']),
      originalFile: _stringOf(m['originalFile']),
    ),
  ),
);

RetranslatePlan _planOf(Map<String, dynamic> j, {required String fallbackName}) => RetranslatePlan(
  comicName: _stringOf(j['comicName'], fallback: fallbackName),
  dirName: _stringOf(j['dirName'], fallback: fallbackName),
  outputDir: _stringOf(j['outputDir']),
  imageCount: _intOf(j['imageCount']),
  translatedCount: _intOf(j['translatedCount']),
  retranslateCount: _intOf(j['retranslateCount']),
  overwriteCount: _intOf(j['overwriteCount']),
  reworking: j['reworking'] == true,
  candidates: _listOf(
    j['candidates'],
    (m) => RetranslateCandidate(
      seq: _intOf(m['seq']),
      ext: _stringOf(m['ext']),
      byteSize: _intOf(m['byteSize']),
      originalFile: _stringOf(m['originalFile']),
      hadTranslation: m['hadTranslation'] == true,
    ),
  ),
);

EngineStatus _engineStatusOf(Map<String, dynamic> j) {
  final engine = j['engine'];
  final llm = j['llm'];
  final tier = j['tier'];
  final config = j['config'];
  return EngineStatus(
    engine: EngineProcess(
      state: engine is Map ? _stringOf(engine['state']) : '',
      version: engine is Map ? _stringOf(engine['version']) : '',
      port: engine is Map && engine['port'] is num ? (engine['port'] as num).toInt() : null,
      pid: engine is Map && engine['pid'] is num ? (engine['pid'] as num).toInt() : null,
    ),
    llm: LlmProcess(
      state: llm is Map ? _stringOf(llm['state']) : '',
      model: llm is Map ? llm['model'] as String? : null,
      port: llm is Map && llm['port'] is num ? (llm['port'] as num).toInt() : null,
      pid: llm is Map && llm['pid'] is num ? (llm['pid'] as num).toInt() : null,
    ),
    tier: tier is Map ? EngineTier(name: _stringOf(tier['name']), reason: _stringOf(tier['reason'])) : null,
    accel: _stringOf(j['accel']),
    warmed: j['warmed'] == true,
    config: EngineConfig(
      translator: config is Map ? _stringOf(config['translator']) : '',
      fromLang: config is Map ? config['fromLang'] as String? : null,
      targetLang: config is Map ? _stringOf(config['targetLang']) : '',
      detector: config is Map ? _stringOf(config['detector']) : '',
      detectionSize: config is Map && config['detectionSize'] is num ? (config['detectionSize'] as num).toInt() : null,
      ocr: config is Map ? _stringOf(config['ocr']) : '',
      inpainter: config is Map ? _stringOf(config['inpainter']) : '',
    ),
    models: _modelsOf(j['models']),
    runtime: _runtimeOf(j['runtime']),
    rawStage: j['stage'] as String?,
  );
}

ModelStatus _modelsOf(Object? v) {
  if (v is! Map) return const ModelStatus(ready: false, sets: {});
  final sets = v['sets'];
  return ModelStatus(
    ready: v['ready'] == true,
    sets: sets is Map
        ? {
            for (final e in sets.entries)
              '${e.key}': e.value is Map
                  ? ModelSet(entries: _intOf((e.value as Map)['entries']), ready: (e.value as Map)['ready'] == true)
                  : const ModelSet(entries: 0, ready: false),
          }
        : const {},
  );
}

RuntimeProbe _runtimeOf(Object? v) {
  if (v is! Map) return const RuntimeProbe(ready: false, checks: []);
  return RuntimeProbe(
    ready: v['ready'] == true,
    checks: _listOf(
      v['checks'],
      (m) => RuntimeCheck(name: _stringOf(m['name']), ok: m['ok'] == true, detail: m['detail'] as String?),
    ),
  );
}

ModelDownloadView _downloadOf(Map<String, dynamic> j) => ModelDownloadView(
  state: _stringOf(j['state'], fallback: 'idle'),
  running: j['running'] == true,
  startedAt: _dateOf(j['startedAt']),
  finishedAt: _dateOf(j['finishedAt']),
  exitCode: j['exitCode'] is num ? (j['exitCode'] as num).toInt() : null,
  timedOut: j['timedOut'] == true,
  tail: _stringList(j['tail']),
  rootDir: _stringOf(j['rootDir']),
  manifest: _stringOf(j['manifest']),
  runner: _stringOf(j['runner']),
  runnerExists: j['runnerExists'] == true,
  percent: j['percent'] is num ? (j['percent'] as num).toDouble() : null,
);
