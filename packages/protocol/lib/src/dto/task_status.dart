/// 任务状态 —— 逐字对齐原项目契约（`src/types/index.ts` 的 `TaskStatus`）。
///
/// 🔴 与原实现 `MangaTaskStatus` 的差异：本枚举用契约的**下划线词表**
/// （`partial_failed` / `canceled`），不是驼峰。序列化必须能原样往返，
/// 否则服务端返回 `partial_failed` 时会解析失败。
enum TaskStatus {
  queued('queued'),
  running('running'),
  done('done'),
  partialFailed('partial_failed'),
  failed('failed'),
  canceled('canceled');

  const TaskStatus(this.wire);

  /// 契约中的原始字面量。
  final String wire;

  /// 解析契约字面量；未知值抛错（**不静默降级**，否则新状态会被误显示成别的）。
  static TaskStatus parse(String value) {
    for (final s in TaskStatus.values) {
      if (s.wire == value) return s;
    }
    throw ArgumentError('未知任务状态：$value');
  }

  /// 是否可删除（翻译中 / 排队中不可删）。
  bool get deletable => this != TaskStatus.running && this != TaskStatus.queued;

  /// 是否占用队列（`queueDepth` 口径：运行中 + 排队中）。
  bool get occupiesQueue => this == TaskStatus.running || this == TaskStatus.queued;
}

/// 任务来源归因（服务端按 `X-Box-Client` 判定）。
enum TaskSource {
  extension('extension'),
  desktop('desktop'),
  unknown('unknown');

  const TaskSource(this.wire);

  final String wire;

  static TaskSource parse(String value) {
    for (final s in TaskSource.values) {
      if (s.wire == value) return s;
    }
    return TaskSource.unknown;
  }
}

/// 任务进度。
class TaskProgress {
  const TaskProgress({required this.total, required this.done, required this.failed, required this.current});

  /// 总页数。
  final int total;

  /// 已完成页数。
  final int done;

  /// 失败页数。
  final int failed;

  /// 当前正在翻译的序号；0 = 无。
  final int current;

  double get ratio => total <= 0 ? 0 : done / total;
}
