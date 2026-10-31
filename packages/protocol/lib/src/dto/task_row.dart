import 'task_status.dart';

/// `GET /api/v1/tasks` 的一行 —— 逐字对齐原项目 `TaskRow`。
class TaskRow {
  const TaskRow({
    required this.taskId,
    required this.comicName,
    required this.source,
    required this.status,
    required this.queuePosition,
    required this.progress,
    required this.outputDir,
    required this.createdAt,
    this.normalizedComicName,
    this.finishedAt,
    this.failedItems = const [],
  });

  final String taskId;
  final String comicName;

  /// 归一化目录名；**可选** —— 旧任务快照没有它，消费方须用 [comicName] 兜底。
  final String? normalizedComicName;

  final TaskSource source;
  final TaskStatus status;

  /// 队列位次。
  final int queuePosition;

  final TaskProgress progress;
  final String outputDir;
  final DateTime createdAt;
  final DateTime? finishedAt;

  /// 失败页的原始原因（只含失败项）；**可选**，旧快照没有。
  final List<FailedItem> failedItems;

  /// 与漫画库对齐用的目录名（后端优先，缺失时回落 `comicName`）。
  String get dirName => normalizedComicName ?? comicName;

  /// 已落盘张数（取消时用于吐司「保留了 N 张」）。
  int get donePages => progress.done;

  /// 总张数。
  int get pageCount => progress.total;
}

/// 失败页原因。
class FailedItem {
  const FailedItem({required this.seq, this.reason, this.errorMessage});

  final int seq;
  final String? reason;
  final String? errorMessage;
}

/// `GET /api/v1/tasks` 的响应。
class TaskListResponse {
  const TaskListResponse({
    required this.count,
    required this.total,
    required this.running,
    required this.queued,
    required this.tasks,
    required this.updatedAt,
  });

  /// 本页 / 本次返回条数。
  final int count;

  /// 总条数（含历史）。
  final int total;

  /// 运行中条数。
  final int running;

  /// 排队中条数。
  final int queued;

  final List<TaskRow> tasks;
  final DateTime updatedAt;

  /// 队列待办数 —— 原项目 `queueDepth = running + queued`，侧栏徽标口径。
  int get queueDepth => running + queued;
}

/// `POST /api/v1/tasks` 的建单响应。
class CreateTaskResponse {
  const CreateTaskResponse({
    required this.taskId,
    required this.comicName,
    required this.normalizedComicName,
    required this.outputDir,
    required this.status,
    required this.queuePosition,
    required this.createdAt,
    this.eta,
  });

  final String taskId;
  final String comicName;
  final String normalizedComicName;
  final String outputDir;
  final TaskStatus status;
  final int queuePosition;
  final DateTime createdAt;

  /// 预计耗时；null = 服务端不给估计（**不要编造**）。
  final Eta? eta;
}

/// 预计耗时区间。
class Eta {
  const Eta({required this.minSeconds, required this.maxSeconds, required this.text});

  final int minSeconds;
  final int maxSeconds;
  final String text;
}

/// `POST /api/v1/tasks/{id}/cancel` 的响应。
class CancelResponse {
  const CancelResponse({required this.taskId, required this.keptItems, required this.outputDir});

  final String taskId;

  /// 保留的已落盘张数。
  final int keptItems;

  final String outputDir;
}

/// `POST /api/v1/tasks/delete` 的响应 —— 逐条回报，不整批失败。
class DeleteTasksResponse {
  const DeleteTasksResponse({
    required this.deleted,
    required this.skipped,
    required this.deletedCount,
    required this.skippedCount,
  });

  final List<String> deleted;
  final List<SkippedTask> skipped;
  final int deletedCount;
  final int skippedCount;
}

/// 未删除的任务及原因。
class SkippedTask {
  const SkippedTask({required this.taskId, required this.reason, this.status});

  final String taskId;

  /// `not_found`（已被别处删掉）/ `not_deletable`（翻译中或排队中）。
  final String reason;

  final TaskStatus? status;
}

/// `GET /api/v1/queue` 的响应。
class QueueSnapshot {
  const QueueSnapshot({required this.running, required this.queued, required this.concurrency});

  /// 正在执行的任务 id；null = 空转。
  final String? running;

  /// 排队中的任务 id（按位次）。
  final List<String> queued;

  /// 并发上限 —— 原项目硬约束为 1（同一时刻只跑 1 个）。
  final int concurrency;
}
