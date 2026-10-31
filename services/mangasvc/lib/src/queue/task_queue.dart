import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../server/http.dart';

/// 串行任务队列 —— 原项目硬约束：**同一时刻只跑 1 个**。
///
/// ## 为什么必须串行
/// 翻译引擎（图片检测 / OCR / 抹字 / 排版）是重量级推理，并发跑会抢显存并让
/// 进度不可预测。原项目 `queue/drain.rs` 就是串行 drain；这里保持同一语义。
///
/// ## 状态机
/// ```
/// queued ──开始──→ running ──全部完成──→ done
///                     ├──有失败页──→ partial_failed
///                     ├──全部失败──→ failed
///                     └──被取消────→ canceled
/// ```
class TaskQueue {
  TaskQueue({this.engineMode = 'mock', required this.rootDir, this.translateImage});

  /// 真实翻译（D-057）：引擎就绪时由 `EngineFacade` 注入。
  ///
  /// null = 没有引擎能力，只跑 mock（把原图字节当译文，仅供界面演示）。
  Future<Uint8List> Function(Uint8List bytes)? translateImage;

  final String engineMode;

  /// 落盘根目录（`<root>/<comicName>/<NN_第N话>/`）。
  final String rootDir;
  final List<QueueTask> _tasks = [];

  /// 翻译日志（环形缓冲）：任务级事件与页面级失败都记在这里。
  /// 设置页「模型 → 翻译日志」轮询展示；上限 200 行。
  final List<String> _translateLog = [];

  void _logLine(String line) {
    final ts = DateTime.now().toIso8601String();
    _translateLog.add('$ts $line');
    if (_translateLog.length > 200) _translateLog.removeAt(0);
  }

  /// 翻译日志尾部（新在前）。
  List<String> translateLogTail([int n = 60]) {
    final end = _translateLog.length;
    final start = end - n < 0 ? 0 : end - n;
    return _translateLog.sublist(start, end).reversed.toList();
  }

  int _seq = 0;
  bool _draining = false;
  Timer? _ticker;

  /// 并发上限 —— 契约里 `concurrency` 字段的值。
  static const int concurrency = 1;

  /// 全量任务（新→旧）。
  List<QueueTask> get tasks => List.unmodifiable(_tasks);

  /// 建单：新任务插到队首（与原项目一致，最新提交在最上）。
  Future<Map<String, dynamic>> createTask({
    required String comicName,
    required List<String> imagePaths,
    String source = 'desktop',
  }) async {
    if (imagePaths.isEmpty) {
      throw const ServiceError('INVALID_IMAGES', '没有可用图片');
    }
    final now = DateTime.now().toUtc();
    _logLine('任务创建 ${comicName.trim()}（${imagePaths.length} 张）');
    final task = QueueTask(
      taskId: 't-${DateTime.now().microsecondsSinceEpoch}-${++_seq}',
      comicName: comicName,
      normalizedComicName: comicName,
      outputDir: comicName,
      total: imagePaths.length,
      createdAt: now,
      batches: List.of(imagePaths),
      source: source,
    );
    _tasks.insert(0, task);
    _scheduleDrain();
    return task.toCreateResponse();
  }

  /// 追加批次（补页）。
  Future<Map<String, dynamic>> appendBatch(String taskId, List<String> imagePaths) async {
    final t = _find(taskId);
    if (t == null) throw const ServiceError('NOT_FOUND', '任务不存在', status: 404);
    if (imagePaths.isEmpty) throw const ServiceError('INVALID_IMAGES', '没有可用图片');
    t.batches.addAll(imagePaths);
    t.total += imagePaths.length;
    _scheduleDrain();
    return t.toCreateResponse();
  }

  QueueTask? getTask(String id) => _find(id);

  /// 任务列表视图（契约 `TaskListResponse`）。
  /// 队列视图。
  ///
  /// [source] 用于**来源隔离**（D-046）：插件提交的只回插件，手机端投放的只回手机端。
  /// 两个客户端连的是同一个桌面服务，不区分就会互相看到对方的任务。
  Map<String, dynamic> listView({String? status, String? source}) {
    var rows = status == null ? _tasks : _tasks.where((t) => t.status.wire == status).toList();
    if (source != null && source.isNotEmpty) {
      rows = rows.where((t) => t.source == source).toList();
    }
    return {
      'count': rows.length,
      'total': _tasks.length,
      'running': _tasks.where((t) => t.status == TaskStatus.running).length,
      'queued': _tasks.where((t) => t.status == TaskStatus.queued).length,
      'tasks': rows.map((t) => t.toRow()).toList(),
      'updatedAt': isoNow(),
    };
  }

  /// 队列快照。
  Map<String, dynamic> snapshot() => {
    'running': _tasks.where((t) => t.status == TaskStatus.running).firstOrNull?.taskId,
    'queued': _tasks.where((t) => t.status == TaskStatus.queued).map((t) => t.taskId).toList(),
    'concurrency': concurrency,
  };

  /// 批量删除：逐条回报，不整批失败。
  Map<String, dynamic> deleteTasks(Set<String>? ids) {
    final deleted = <String>[];
    final skipped = <Map<String, dynamic>>[];
    for (final t in List.of(_tasks)) {
      if (ids != null && !ids.contains(t.taskId)) continue;
      if (!t.status.deletable) {
        skipped.add({'taskId': t.taskId, 'reason': 'not_deletable', 'status': t.status.wire});
        continue;
      }
      deleted.add(t.taskId);
      _tasks.remove(t);
    }
    return {'deleted': deleted, 'skipped': skipped, 'deletedCount': deleted.length, 'skippedCount': skipped.length};
  }

  /// 取消：保留已落盘张数，状态改 canceled。
  Future<Map<String, dynamic>> cancelTask(String taskId) async {
    final t = _find(taskId);
    if (t == null) throw const ServiceError('NOT_FOUND', '任务不存在', status: 404);
    t.cancelRequested = true;
    t.status = TaskStatus.canceled;
    t.subscription?.cancel();
    return {'taskId': t.taskId, 'status': 'canceled', 'keptItems': t.done, 'outputDir': t.outputDir};
  }

  /// 重试：复用原任务，重置进度。
  Future<Map<String, dynamic>> retryTask(String taskId) async {
    final t = _find(taskId);
    if (t == null) throw const ServiceError('NOT_FOUND', '任务不存在', status: 404);
    if (t.status == TaskStatus.running || t.status == TaskStatus.queued) {
      throw const ServiceError('ALREADY_ACTIVE', '任务已在队列中', status: 409);
    }
    _logLine('重试任务 ${t.comicName}（此前 ${t.status.wire}，${t.done}/${t.total}）');
    t
      ..status = TaskStatus.queued
      ..done = 0
      ..failed = 0
      ..current = 0
      ..lastError = null
      ..finishedAt = null
      ..cancelRequested = false;
    t.failedReasons.clear();
    _scheduleDrain();
    return t.toCreateResponse();
  }

  /// 单任务 SSE 事件流。
  Stream<Map<String, String>> events(String taskId) {
    final t = _find(taskId);
    if (t == null) throw const ServiceError('NOT_FOUND', '任务不存在', status: 404);
    final controller = StreamController<Map<String, String>>();
    void emit() {
      if (controller.isClosed) return;
      controller.add({
        'type': t.status.isTerminal ? (t.status == TaskStatus.canceled ? 'canceled' : 'done') : 'progress',
        'data':
            '{"taskId":"${t.taskId}","status":"${t.status.wire}",'
            '"progress":{"total":${t.total},"done":${t.done},"failed":${t.failed}}}',
      });
      if (t.status.isTerminal) controller.close();
    }

    emit();
    if (!t.status.isTerminal) {
      final sub = t.progressStream.listen((_) => emit(), onDone: emit);
      controller.onCancel = sub.cancel;
    }
    return controller.stream;
  }

  void _scheduleDrain() {
    if (_draining) return;
    _draining = true;
    _ticker = Timer(const Duration(milliseconds: 10), () async {
      try {
        await _drain();
      } finally {
        // 🔴 必须放 finally：中途抛异常若不复位，后续任务**永远不会被取出**，
        // 表现就是「一直排队中」。
        _draining = false;
      }
    });
  }

  /// 串行执行：一次只取一个 queued 任务。
  Future<void> _drain() async {
    while (true) {
      final next = _tasks.where((t) => t.status == TaskStatus.queued).lastOrNull;
      if (next == null) return;
      await _runOne(next);
    }
  }

  /// 跑一个任务 —— **真的落盘**。
  ///
  /// 落盘结构（与原项目一致）：
  /// ```
  /// <root>/<comicName>/01_第1话/001.png              原图
  /// <root>/<comicName>/01_第1话/001_translated.png   译文
  /// ```
  ///
  /// **mock 引擎**：原图原样拷贝，译文写成同内容占位 —— 只是把管道跑通，
  /// 不假装做了翻译（文件内容是原图字节，`_translated` 后缀标明位置）。
  /// **real 引擎**：P0-C 接入，当前显式失败，绝不假装成功。
  Future<void> _runOne(QueueTask t) async {
    final translator = translateImage;
    final real = engineMode != 'mock';
    // 非 mock 模式必须有真实翻译能力，否则如实失败（不偷偷写成 mock）。
    if (real && translator == null) {
      t.status = TaskStatus.failed;
      t.failAll('引擎未接入（缺少翻译能力）');
      return;
    }
    t.status = TaskStatus.running;
    try {
      final bookDir = Directory('$rootDir/${t.comicName}');
      final chapterDir = Directory('${bookDir.path}/01_第1话');
      chapterDir.createSync(recursive: true);
      // 建 manifest：没有它，书架子目录会被当成「未归并单话」而不是「本」。
      final manifest = File('${bookDir.path}/manifest.json');
      if (!manifest.existsSync()) {
        manifest.writeAsStringSync(
          jsonEncode({'title': t.comicName, 'author': '', 'createdAt': DateTime.now().toUtc().toIso8601String()}),
        );
      }

      for (var i = 0; i < t.batches.length; i++) {
        if (t.cancelRequested) {
          t.status = TaskStatus.canceled;
          return;
        }
        final src = t.batches[i];
        final seq = i + 1;
        final ext = src.contains('.') ? src.split('.').last.toLowerCase() : 'png';
        final original = File('${chapterDir.path}/${_pad(seq)}.$ext');
        // 引擎一律回 PNG（实测 1 301 295 字节的 PNG 被写成了 .jpg），
        // 扩展名必须跟真实格式一致，否则部分查看器会解不出来。
        final translated = File('${chapterDir.path}/${_pad(seq)}_translated.png');

        // 原图：源文件存在就拷贝；测试里常见「路径不存在」，则写占位（不失败）。
        final srcFile = File(src);
        if (srcFile.existsSync()) {
          srcFile.copySync(original.path);
        } else {
          original.writeAsBytesSync([0]);
        }
        if (real) {
          // 真实翻译：引擎出图；失败只让**这一页**失败，不拖垮整本。
          try {
            final out = await translator!(original.readAsBytesSync());
            translated.writeAsBytesSync(out);
          } catch (e) {
            t.failed++;
            t.lastError = '$e';
            // 进 failedReasons：任务行的 failedItems 才会带出原因，
            // 否则「部分失败」之后用户看不到任何解释（D-075）。
            t.failedReasons.add('第 ${_pad(seq)} 页：$e');
            continue;
          }
        } else {
          // mock 译文 = 原图字节（位置正确，内容不是真翻译）。
          translated.writeAsBytesSync(original.readAsBytesSync());
        }

        await Future<void>.delayed(const Duration(milliseconds: 10));
        t.done++;
        t.progressController.add(t.done);
      }
      t.finishedAt = DateTime.now().toUtc();
      t.status = t.failed > 0 ? TaskStatus.partialFailed : TaskStatus.done;
    } catch (e) {
      t.status = TaskStatus.failed;
      t.failAll('落盘失败：$e');
    }
  }

  /// 三位补零（`001`）。
  String _pad(int n) => n.toString().padLeft(3, '0');

  QueueTask? _find(String id) => _tasks.where((t) => t.taskId == id).firstOrNull;

  Future<void> dispose() async {
    _ticker?.cancel();
    for (final t in _tasks) {
      await t.subscription?.cancel();
      await t.progressController.close();
    }
  }
}

/// 任务状态（服务端词表，与契约 `TaskStatus.wire` 一致）。
enum TaskStatus {
  queued('queued'),
  running('running'),
  done('done'),
  partialFailed('partial_failed'),
  failed('failed'),
  canceled('canceled');

  const TaskStatus(this.wire);

  final String wire;

  bool get deletable => this != running && this != queued;
  bool get isTerminal => this == done || this == partialFailed || this == failed || this == canceled;
}

/// 队列内的一个任务。
class QueueTask {
  QueueTask({
    required this.taskId,
    required this.comicName,
    required this.normalizedComicName,
    required this.outputDir,
    required this.total,
    required this.createdAt,
    required this.batches,
    this.source = 'desktop',
  });

  final String taskId;
  final String comicName;
  final String normalizedComicName;
  final String outputDir;
  final DateTime createdAt;

  /// 待处理的原图路径（按序号）。
  final List<String> batches;

  /// 来源归因（`extension` / `desktop`），由 `X-Box-Client` 决定。
  final String source;

  /// 最近一次页面级失败原因（真实翻译时逐页记录，不中断整本）。
  String? lastError;

  int total;
  int done = 0;
  int failed = 0;
  int current = 0;
  TaskStatus status = TaskStatus.queued;
  DateTime? finishedAt;
  bool cancelRequested = false;

  final List<String> failedReasons = [];
  final StreamController<int> progressController = StreamController<int>.broadcast();
  StreamSubscription<int>? subscription;

  /// 进度流（SSE 与内部 drain 共用）。
  Stream<int> get progressStream => progressController.stream;

  void failAll(String reason) {
    failed = total;
    failedReasons.add(reason);
    finishedAt = DateTime.now().toUtc();
  }

  /// 契约 `TaskRow`。
  Map<String, dynamic> toRow() => {
    'taskId': taskId,
    'comicName': comicName,
    'normalizedComicName': normalizedComicName,
    'source': source,
    'status': status.wire,
    'queuePosition': 0,
    'progress': {'total': total, 'done': done, 'failed': failed, 'current': current},
    'outputDir': outputDir,
    'createdAt': createdAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    if (failedReasons.isNotEmpty)
      'failedItems': [
        for (var i = 0; i < failedReasons.length; i++)
          {'seq': i + 1, 'reason': 'ENGINE_ERROR', 'errorMessage': failedReasons[i]},
      ],
  };

  /// 契约 `CreateTaskResponse`。
  Map<String, dynamic> toCreateResponse() => {
    'taskId': taskId,
    'comicName': comicName,
    'normalizedComicName': normalizedComicName,
    'outputDir': outputDir,
    'status': status.wire,
    'queuePosition': 0,
    'eta': null,
    'createdAt': createdAt.toIso8601String(),
  };
}
