/// 一条漫画翻译任务 —— 队列屏使用的 UI 模型。
///
/// 由契约 DTO `TaskRow` 转换而来（见 `data/contract_map.dart`）：
/// 业务屏只认这个模型，不直接依赖协议字段的原始形状。
class MangaTask {
  const MangaTask({
    required this.id,
    required this.name,
    required this.source,
    required this.status,
    required this.pageCount,
    required this.donePages,
    required this.batchNo,
    required this.createdAt,
    this.completedAt,
    this.failedReason,
  });

  /// 任务 id（契约 `taskId`）。
  final String id;

  /// 漫画名。
  final String name;

  /// 行副标所需的原始数值（UI 层拼 ARB 文案）。
  ///
  /// 不在这里拼字符串：文案要可翻译，必须走 ARB 占位符。
  final int batchNo;

  /// 来源（UI 层按枚举取 ARB 文案）。
  final MangaTaskSource source;

  final MangaTaskStatus status;
  final int pageCount;
  final int donePages;

  final DateTime createdAt;
  final DateTime? completedAt;

  /// 失败页的原始原因（只含失败项）。
  final String? failedReason;

  /// 是否可删除（翻译中 / 排队中不可删）。
  bool get deletable => status != MangaTaskStatus.translating && status != MangaTaskStatus.queued;

  /// 是否占用队列（`queueDepth` 口径）。
  bool get occupiesQueue => status == MangaTaskStatus.translating || status == MangaTaskStatus.queued;

  double get progress => pageCount <= 0 ? 0 : donePages / pageCount;
}

/// 任务状态（UI 语义，与设计稿 H Note 09 色表对应）。
enum MangaTaskStatus { translating, queued, done, partialFailed, failed, cancelled }

/// 任务来源（UI 语义）。
///
/// 之所以不直接存中文：`data/` 层没有 `BuildContext`，文案必须由 UI 层经 ARB 取
/// （AGENTS §3 国际化约束：不得在 lib/ 里写死中文字面量）。
/// 任务来源（服务端归一化：`app|mobile → app`、`plugin|extension → plugin`、
/// 其余 `desktop`；`extension` 只出现在旧持久化数据里）。
enum MangaTaskSource { app, plugin, desktop, extension, unknown }

/// 一次投放的结果（吐司用）。
class SubmitOutcome {
  const SubmitOutcome({required this.submitted, required this.position, this.blockedReason});

  /// 已提交张数。
  final int submitted;

  /// 在队列中的位次。
  final int position;

  /// 前置校验不通过的原因（非 null = 任务已建成 failed，未进流水线）。
  ///
  /// 典型场景：选了远程翻译，但 token / 地址没配好。
  final String? blockedReason;

  /// 是否被前置校验拦下。
  bool get blocked => blockedReason != null;
}
