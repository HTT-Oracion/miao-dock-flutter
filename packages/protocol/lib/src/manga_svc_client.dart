import 'dto/engine.dart';
import 'dto/library.dart';
import 'dto/task_row.dart';
import 'dto/task_status.dart';

/// mangasvc 客户端契约 —— 与后端路由表（原项目 `mangasvc/routes.rs` 的 `ROUTES`）一一对应。
///
/// ## 契约原则
/// 1. **不增不减**：方法集合 = 路由表端点集合。新增端点时先改这里，再改实现。
/// 2. **路径即文档**：每个方法注释写明 `METHOD /api/v1/...`，便于与后端对照。
/// 3. **错误统一**：所有方法抛 `MangaSvcException`，不各自定义异常。
/// 4. **不吞错**：拿不到数据就抛，不返回空列表冒充「没有数据」（空态与失败态必须分开）。
/// 5. **不伪造**：未实现的端点抛 `unreachable`，绝不返回假数据。
///
/// ## 本期实现范围
/// P0-A 只落**契约**与传输层；`services/mangasvc` 真实实现在 P0-B。
abstract class MangaSvcClient {
  // ── health ───────────────────────────────────────────────────────────────

  /// `GET /health`（兼容 `GET /api/v1/health`）。
  Future<HealthResponse> health();

  // ── tasks ────────────────────────────────────────────────────────────────

  /// `GET /api/v1/tasks` —— 任务列表（含 `running` / `queued` 汇总）。
  Future<TaskListResponse> listTasks({TaskStatus? status});

  /// `GET /api/v1/tasks/{taskId}` —— 单任务详情。
  Future<TaskRow> getTask(String taskId);

  /// `POST /api/v1/tasks` —— 建单（投放）。服务端按序号分批，每批 20 张。
  Future<CreateTaskResponse> createTask({required String comicName, required List<String> imagePaths});

  /// `POST /api/v1/tasks/{taskId}/batches` —— 向已有任务追加批次（补页）。
  Future<CreateTaskResponse> appendBatch(String taskId, {required List<String> imagePaths});

  /// `POST /api/v1/tasks/delete` —— 批量删除任务记录；`null` = 全部可删任务。
  Future<DeleteTasksResponse> deleteTasks(Set<String>? taskIds);

  /// `POST /api/v1/tasks/{taskId}/cancel` —— 取消任务（保留已落盘译文）。
  ///
  /// 服务端对**执行中**任务会等到安全点才回（最长 30s）：调用方须先把按钮置为
  /// 「取消中…」再 await，不能靠返回值才反馈。
  Future<CancelResponse> cancelTask(String taskId);

  /// `POST /api/v1/tasks/{taskId}/retry` —— 重试失败任务。
  Future<CreateTaskResponse> retryTask(String taskId);

  /// `GET /api/v1/tasks/{taskId}/events` —— SSE 进度流；`isTerminal` 时关闭。
  Stream<TaskEvent> watchTaskEvents(String taskId);

  // ── queue ────────────────────────────────────────────────────────────────

  /// `GET /api/v1/queue` —— 队列快照。
  Future<QueueSnapshot> getQueue();

  // ── library ──────────────────────────────────────────────────────────────

  /// `GET /api/v1/library` —— 扫描落盘根目录。
  Future<LibraryResponse> listLibrary();

  /// `POST /api/v1/library/create` —— 手动新建大类。
  Future<void> createBook(String bookName);

  /// `GET /api/v1/library/{name}/meta` —— 读元信息。
  Future<BookMeta> getBookMeta(String bookName);

  /// `POST /api/v1/library/{name}/meta` —— 写元信息。
  Future<void> setBookMeta(String bookName, BookMeta meta);

  /// `GET /api/v1/library/{name}/cover` —— 取封面字节；无封面返回 null。
  Future<List<int>?> getBookCover(String bookName);

  /// `POST /api/v1/library/{name}/cover` —— 上传封面。
  Future<void> setBookCover(String bookName, {required List<int> bytes, required String filename});

  /// `DELETE /api/v1/library/{name}/cover` —— 删除封面。
  Future<void> deleteBookCover(String bookName);

  /// `POST /api/v1/library/{name}/merge` —— 把若干单话归并进本。
  Future<void> mergeChapters(String bookName, {required List<String> chapterDirs});

  /// `POST /api/v1/library/{name}/reveal` —— 在文件管理器中打开目录（桌面专属）。
  Future<void> revealBook(String bookName);

  /// `POST /api/v1/library/{name}/delete` —— 删除本；`deleteFiles=false` 只从库里隐藏。
  Future<LibraryDeleteResponse> deleteBook(String bookName, {required bool deleteFiles});

  /// `POST /api/v1/library/{name}/unhide` —— 恢复被隐藏的本。
  Future<void> unhideBook(String bookName);

  /// `GET /api/v1/library/{name}/resume` —— 整本补页计划。
  Future<ResumePlan> getResumePlan(String bookName);

  /// `POST /api/v1/library/{name}/resume` —— 执行整本补页（建单）。
  Future<CreateTaskResponse> resumeBook(String bookName);

  /// `GET /api/v1/library/{name}/retranslate` —— 整本返工计划。
  Future<RetranslatePlan> getRetranslatePlan(String bookName);

  /// `POST /api/v1/library/{name}/retranslate` —— 执行整本返工。
  Future<CreateTaskResponse> retranslateBook(String bookName);

  /// `GET /api/v1/library/{book}/chapters/{no}/resume` —— 单话补页计划。
  Future<ResumePlan> getChapterResumePlan(String bookName, int chapterNo);

  /// `POST /api/v1/library/{book}/chapters/{no}/resume` —— 单话补页。
  Future<CreateTaskResponse> resumeChapter(String bookName, int chapterNo);

  /// `GET /api/v1/library/{book}/chapters/{no}/retranslate` —— 单话返工计划。
  Future<RetranslatePlan> getChapterRetranslatePlan(String bookName, int chapterNo);

  /// `POST /api/v1/library/{book}/chapters/{no}/retranslate` —— 单话返工。
  Future<CreateTaskResponse> retranslateChapter(String bookName, int chapterNo);

  /// `POST /api/v1/library/{book}/chapters/{no}/renumber` —— 改话号。
  Future<void> renumberChapter(String bookName, int chapterNo, {required int newNo});

  /// `GET /api/v1/library/{name}/files/{seq}` —— 取本内原图字节。
  Future<List<int>> getBookFile(String bookName, int seq);

  /// `GET /api/v1/library/{book}/chapters/{no}/files/{seq}` —— 取话内原图字节。
  Future<List<int>> getChapterFile(String bookName, int chapterNo, int seq);

  // ── translate ────────────────────────────────────────────────────────────

  /// `GET /api/v1/translate/options` —— 可选项（方向 / 来源）。
  Future<TranslateOptions> getTranslateOptions();

  /// `POST /api/v1/engine/settings` —— 写引擎设置。
  ///
  /// 返回 `needsRestart`：改 tier / accel 需要重启引擎才生效（C2 契约）。
  /// 🔴 服务端做了**白名单校验**，未知键会被拒绝（`INVALID_SETTING`）。
  Future<bool> setEngineSettings(Map<String, dynamic> settings);
  Future<void> setTranslateSettings(Map<String, dynamic> settings);

  /// `POST /api/v1/translate/credentials` —— 写平台凭据。
  Future<void> setTranslateCredentials(Map<String, dynamic> credentials);

  /// `POST /api/v1/translate/text` —— 文本翻译（诊断用）。
  Future<String> translateText({required String text, required String from, required String to});

  /// `POST /api/v1/translate/stream` —— 流式文本翻译（诊断用）。
  Stream<String> translateStream({required String text, required String from, required String to});

  // ── engine ───────────────────────────────────────────────────────────────

  /// `GET /api/v1/engine/status` —— 引擎 + LLM 进程态 + 模型 + 运行时就绪。
  Future<EngineStatus> getEngineStatus();

  /// `GET /api/v1/engine/runtime` —— 运行时就绪探测。
  Future<RuntimeProbe> getEngineRuntime();

  /// `GET /api/v1/engine/options` —— 引擎可选项。
  Future<Map<String, dynamic>> getEngineOptions();

  /// `POST /api/v1/engine/unload` —— 空闲卸载权重（不停进程）。
  Future<void> unloadEngine();

  /// `POST /api/v1/engine/start` —— 启动引擎 + 大模型（共用一个开关，D-012）。
  Future<EngineStatus> startEngine();

  /// `POST /api/v1/engine/stop` —— 停止引擎 + 大模型。
  Future<EngineStatus> stopEngine();

  /// `POST /api/v1/engine/models/verify` —— 校验模型完整性。
  Future<ModelStatus> verifyModels();

  /// `POST /api/v1/engine/models/download` —— 开始下载模型（支持 Range 续传）。
  Future<ModelDownloadView> downloadModels();

  /// `POST /api/v1/engine/models/download/pause` —— 暂停下载（杀子进程、`.part` 留盘）。
  Future<ModelDownloadView> pauseModelDownload();
}

/// 任务 SSE 事件。
class TaskEvent {
  const TaskEvent({required this.type, required this.taskId, required this.payload});

  /// `progress` / `stage` / `item` / `done` / `failed` / `canceled`。
  final String type;

  final String taskId;
  final Map<String, dynamic> payload;

  bool get isTerminal => type == 'done' || type == 'failed' || type == 'canceled';
}

/// 本元信息（`manifest.json` 的前端视图）。
class BookMeta {
  const BookMeta({required this.title, required this.author, this.coverPath});

  final String title;

  /// 空串 = 未署名（UI 显示「未署名」）。
  final String author;

  /// 封面文件名（**不是** URL）。
  final String? coverPath;
}

/// 翻译可选项。
class TranslateOptions {
  const TranslateOptions({required this.fromLangs, required this.toLangs, required this.sources});

  final List<String> fromLangs;
  final List<String> toLangs;

  /// 翻译来源（本地引擎 / 在线来源）。
  final List<String> sources;
}
