import 'dart:async';
import 'dart:math';

import 'dto/api_error.dart';
import 'dto/engine.dart';
import 'dto/library.dart';
import 'dto/task_row.dart';
import 'dto/task_status.dart';
import 'manga_svc_client.dart';

/// A 级替身（AGENTS §2 / third-party-packages）：内存队列与内存书架，
/// UI 日常开发与热重载用，不需要任何服务进程。
///
/// ## 边界（重要）
/// 只实现 **UI 开发真正需要**的那一小组端点：任务列表 / 建单 / 删除 / 取消 / 书架 / 队列。
/// 其余端点一律抛 `MangaSvcException(unreachable)` —— **不返回假数据**。
/// 引擎状态、模型下载若给假值，会在联调时掩盖真实缺口。
class FakeMangaSvcClient implements MangaSvcClient {
  FakeMangaSvcClient({int seedTasks = 16}) {
    if (seedTasks > 0) _seed(seedTasks);
  }

  final List<TaskRow> _tasks = [];
  int _seq = 0;

  /// 当前内存任务（测试可读）。
  List<TaskRow> get tasks => List.unmodifiable(_tasks);

  void _seed(int count) {
    const names = [
      '未来回归',
      '星海航路',
      '深夜食堂 · 外传',
      '雾都侦探',
      '南国之夏',
      '机械之心',
      '古书店的谜题',
      '北境之歌',
      '城市猎人 2025',
      '银翼快枪',
      '时间旅行者的妻子',
      '红发安妮 · 续',
      '深海列车',
      '纸飞机与晚风',
      '季风花园',
      'Lost · 拾遗',
    ];
    const statuses = [
      TaskStatus.running,
      TaskStatus.queued,
      TaskStatus.done,
      TaskStatus.done,
      TaskStatus.done,
      TaskStatus.partialFailed,
      TaskStatus.done,
      TaskStatus.failed,
      TaskStatus.done,
      TaskStatus.canceled,
      TaskStatus.done,
      TaskStatus.done,
      TaskStatus.done,
      TaskStatus.done,
      TaskStatus.done,
      TaskStatus.done,
    ];
    final now = DateTime.now();
    for (var i = 0; i < count; i++) {
      final status = statuses[i % statuses.length];
      final pages = 16 + Random(i).nextInt(32);
      final done = switch (status) {
        TaskStatus.done => pages,
        TaskStatus.partialFailed => pages - 3,
        TaskStatus.running => pages ~/ 3,
        _ => 0,
      };
      _tasks.add(
        TaskRow(
          taskId: 't-${++_seq}',
          comicName: names[i % names.length],
          normalizedComicName: names[i % names.length],
          source: i % 3 == 0 ? TaskSource.desktop : TaskSource.extension,
          status: status,
          queuePosition: status == TaskStatus.queued ? i : 0,
          progress: TaskProgress(
            total: pages,
            done: done,
            failed: status == TaskStatus.partialFailed ? 3 : 0,
            current: 0,
          ),
          outputDir: '/fake/library/${names[i % names.length]}',
          createdAt: now.subtract(Duration(hours: 16 - (i % 16))),
        ),
      );
    }
  }

  // ── tasks（真实实现）──────────────────────────────────────────────────────

  @override
  Future<TaskListResponse> listTasks({TaskStatus? status}) async {
    final rows = status == null ? List<TaskRow>.of(_tasks) : _tasks.where((t) => t.status == status).toList();
    return TaskListResponse(
      count: rows.length,
      total: _tasks.length,
      running: _tasks.where((t) => t.status == TaskStatus.running).length,
      queued: _tasks.where((t) => t.status == TaskStatus.queued).length,
      tasks: rows,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<TaskRow> getTask(String taskId) async {
    final t = _tasks.where((e) => e.taskId == taskId).firstOrNull;
    if (t == null) throw _notFound('任务', taskId);
    return t;
  }

  @override
  Future<CreateTaskResponse> createTask({required String comicName, required List<String> imagePaths}) async {
    final now = DateTime.now();
    final position = _tasks.where((t) => t.status.occupiesQueue).length + 1;
    final row = TaskRow(
      taskId: 't-${++_seq}',
      comicName: comicName,
      normalizedComicName: comicName,
      source: TaskSource.desktop,
      status: TaskStatus.queued,
      queuePosition: position,
      progress: TaskProgress(total: imagePaths.length, done: 0, failed: 0, current: 0),
      outputDir: '/fake/library/$comicName',
      createdAt: now,
    );
    _tasks.insert(0, row);
    return CreateTaskResponse(
      taskId: row.taskId,
      comicName: comicName,
      normalizedComicName: comicName,
      outputDir: row.outputDir,
      status: TaskStatus.queued,
      queuePosition: position,
      createdAt: now,
    );
  }

  @override
  Future<DeleteTasksResponse> deleteTasks(Set<String>? taskIds) async {
    final targets = _tasks.where((t) => t.status.deletable && (taskIds == null || taskIds.contains(t.taskId))).toList();
    final deleted = targets.map((t) => t.taskId).toList();
    _tasks.removeWhere((t) => deleted.contains(t.taskId));
    final skipped = _tasks
        .where((t) => taskIds != null && taskIds.contains(t.taskId))
        .map((t) => SkippedTask(taskId: t.taskId, reason: 'not_deletable', status: t.status))
        .toList();
    return DeleteTasksResponse(
      deleted: deleted,
      skipped: skipped,
      deletedCount: deleted.length,
      skippedCount: skipped.length,
    );
  }

  @override
  Future<CancelResponse> cancelTask(String taskId) async {
    final i = _tasks.indexWhere((t) => t.taskId == taskId);
    if (i < 0) throw _notFound('任务', taskId);
    final t = _tasks[i];
    // 取消后保留进度计数（已落盘张数），状态改 canceled。
    _tasks[i] = TaskRow(
      taskId: t.taskId,
      comicName: t.comicName,
      normalizedComicName: t.normalizedComicName,
      source: t.source,
      status: TaskStatus.canceled,
      queuePosition: 0,
      progress: t.progress,
      outputDir: t.outputDir,
      createdAt: t.createdAt,
    );
    return CancelResponse(taskId: taskId, keptItems: t.progress.done, outputDir: t.outputDir);
  }

  // ── library / queue（真实实现，内存书架）──────────────────────────────────

  @override
  Future<LibraryResponse> listLibrary() async {
    final done = _tasks.where((t) => t.status == TaskStatus.done).toList();
    final books = <BookEntry>[];
    final comics = <ComicEntry>[];
    for (final (i, t) in done.indexed) {
      final chapters = List.generate(3, (ci) {
        final pages = 20 + ci * 4;
        return ChapterEntry(
          no: ci + 1,
          dirName: '0${ci + 1}_第${ci + 1}话',
          absDir: '${t.outputDir}/0${ci + 1}_第${ci + 1}话',
          imageCount: pages,
          translatedCount: pages,
          seqMax: pages,
          translatedSeqs: List.generate(pages, (p) => p + 1),
          missingSeqs: const [],
          merged: true,
          modifiedAt: DateTime.now(),
        );
      });
      final totalPages = chapters.fold<int>(0, (s, c) => s + c.seqMax);
      books.add(
        BookEntry(
          bookName: t.comicName,
          dirName: t.comicName,
          outputDir: t.outputDir,
          title: t.comicName,
          author: ['', '山田太郎', '李默', 'Aki'][i % 4],
          coverPath: i.isEven ? 'cover.png' : null,
          chapterCount: chapters.length,
          totalPages: totalPages,
          byteSize: totalPages * 512 * 1024,
          modifiedAt: DateTime.now(),
          chapters: chapters,
        ),
      );
      comics.add(
        ComicEntry(
          comicName: t.comicName,
          dirName: t.comicName,
          outputDir: t.outputDir,
          imageCount: totalPages,
          translatedCount: totalPages,
          byteSize: totalPages * 512 * 1024,
          seqMax: totalPages,
          nextSeq: totalPages + 1,
          translatedSeqs: List.generate(totalPages, (p) => p + 1),
          missingSeqs: const [],
          modifiedAt: DateTime.now(),
        ),
      );
    }
    return LibraryResponse(
      root: '/fake/library',
      count: books.length,
      totalImages: comics.fold<int>(0, (s, c) => s + c.imageCount),
      totalBytes: comics.fold<int>(0, (s, c) => s + c.byteSize),
      comics: comics,
      books: books,
      others: const [],
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<QueueSnapshot> getQueue() async {
    final running = _tasks.where((t) => t.status == TaskStatus.running).firstOrNull;
    final queued = _tasks.where((t) => t.status == TaskStatus.queued).map((t) => t.taskId).toList();
    return QueueSnapshot(running: running?.taskId, queued: queued, concurrency: 1);
  }

  @override
  Future<HealthResponse> health() async => HealthResponse(
    status: 'ok',
    service: 'mangasvc',
    version: 'fake',
    apiVersion: 'v1',
    sidecar: const SidecarInfo(state: 'fake', engine: 'fake'),
    rootDir: '/fake/library',
    startedAt: DateTime(2026),
  );

  // ── 未实现端点：如实抛错，绝不伪造 ────────────────────────────────────────

  Never _unimplemented(String endpoint) =>
      throw MangaSvcException(kind: MangaSvcErrorKind.unreachable, message: 'A 级替身未实现 $endpoint（需真实 mangasvc，见 P0-B）');

  Never _notFound(String what, String id) =>
      throw MangaSvcException(kind: MangaSvcErrorKind.apiError, message: '$what 不存在：$id', statusCode: 404);

  @override
  Future<CreateTaskResponse> appendBatch(String taskId, {required List<String> imagePaths}) =>
      _unimplemented('POST /tasks/{id}/batches');

  @override
  Future<CreateTaskResponse> retryTask(String taskId) => _unimplemented('POST /tasks/{id}/retry');

  @override
  Stream<TaskEvent> watchTaskEvents(String taskId) => _unimplemented('GET /tasks/{id}/events');

  @override
  Future<void> createBook(String bookName) => _unimplemented('POST /library/create');

  @override
  Future<BookMeta> getBookMeta(String bookName) => _unimplemented('GET /library/{name}/meta');

  @override
  Future<void> setBookMeta(String bookName, BookMeta meta) => _unimplemented('POST /library/{name}/meta');

  @override
  Future<List<int>?> getBookCover(String bookName) => _unimplemented('GET /library/{name}/cover');

  @override
  Future<void> setBookCover(String bookName, {required List<int> bytes, required String filename}) =>
      _unimplemented('POST /library/{name}/cover');

  @override
  Future<void> deleteBookCover(String bookName) => _unimplemented('DELETE /library/{name}/cover');

  @override
  Future<void> mergeChapters(String bookName, {required List<String> chapterDirs}) =>
      _unimplemented('POST /library/{name}/merge');

  @override
  Future<void> revealBook(String bookName) => _unimplemented('POST /library/{name}/reveal');

  @override
  Future<LibraryDeleteResponse> deleteBook(String bookName, {required bool deleteFiles}) =>
      _unimplemented('POST /library/{name}/delete');

  @override
  Future<void> unhideBook(String bookName) => _unimplemented('POST /library/{name}/unhide');

  @override
  Future<ResumePlan> getResumePlan(String bookName) => _unimplemented('GET /library/{name}/resume');

  @override
  Future<CreateTaskResponse> resumeBook(String bookName) => _unimplemented('POST /library/{name}/resume');

  @override
  Future<RetranslatePlan> getRetranslatePlan(String bookName) => _unimplemented('GET /library/{name}/retranslate');

  @override
  Future<CreateTaskResponse> retranslateBook(String bookName) => _unimplemented('POST /library/{name}/retranslate');

  @override
  Future<ResumePlan> getChapterResumePlan(String bookName, int chapterNo) =>
      _unimplemented('GET /library/{book}/chapters/{no}/resume');

  @override
  Future<CreateTaskResponse> resumeChapter(String bookName, int chapterNo) =>
      _unimplemented('POST /library/{book}/chapters/{no}/resume');

  @override
  Future<RetranslatePlan> getChapterRetranslatePlan(String bookName, int chapterNo) =>
      _unimplemented('GET /library/{book}/chapters/{no}/retranslate');

  @override
  Future<CreateTaskResponse> retranslateChapter(String bookName, int chapterNo) =>
      _unimplemented('POST /library/{book}/chapters/{no}/retranslate');

  @override
  Future<void> renumberChapter(String bookName, int chapterNo, {required int newNo}) =>
      _unimplemented('POST /library/{book}/chapters/{no}/renumber');

  @override
  Future<List<int>> getBookFile(String bookName, int seq) => _unimplemented('GET /library/{name}/files/{seq}');

  @override
  Future<List<int>> getChapterFile(String bookName, int chapterNo, int seq) =>
      _unimplemented('GET /library/{book}/chapters/{no}/files/{seq}');

  @override
  Future<TranslateOptions> getTranslateOptions() => _unimplemented('GET /translate/options');

  @override
  Future<void> setTranslateSettings(Map<String, dynamic> settings) => _unimplemented('POST /translate/settings');

  @override
  Future<void> setTranslateCredentials(Map<String, dynamic> credentials) =>
      _unimplemented('POST /translate/credentials');

  @override
  Future<String> translateText({required String text, required String from, required String to}) =>
      _unimplemented('POST /translate/text');

  @override
  Stream<String> translateStream({required String text, required String from, required String to}) =>
      _unimplemented('POST /translate/stream');

  @override
  Future<EngineStatus> getEngineStatus() => _unimplemented('GET /engine/status');

  @override
  Future<RuntimeProbe> getEngineRuntime() => _unimplemented('GET /engine/runtime');

  @override
  Future<Map<String, dynamic>> getEngineOptions() => _unimplemented('GET /engine/options');

  @override
  Future<bool> setEngineSettings(Map<String, dynamic> settings) => _unimplemented('POST /engine/settings');

  @override
  Future<void> unloadEngine() => _unimplemented('POST /engine/unload');

  @override
  Future<EngineStatus> startEngine() => _unimplemented('POST /engine/start');

  @override
  Future<EngineStatus> stopEngine() => _unimplemented('POST /engine/stop');

  @override
  Future<ModelStatus> verifyModels() => _unimplemented('POST /engine/models/verify');

  @override
  Future<ModelDownloadView> downloadModels() => _unimplemented('POST /engine/models/download');

  @override
  Future<ModelDownloadView> pauseModelDownload() => _unimplemented('POST /engine/models/download/pause');
}
