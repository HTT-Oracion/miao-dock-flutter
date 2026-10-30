/// 漫画翻译任务状态（与设计稿 H 帧 / mangasvc 状态词表一致）。
enum MangaTaskStatus { translating, queued, done, partialFailed, failed, cancelled }

/// 一条漫画翻译任务（队列屏的一行）。
class MangaTask {
  const MangaTask({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.source,
    required this.status,
    required this.pageCount,
    required this.donePages,
    required this.batchNo,
    required this.createdAt,
    this.completedAt,
  });

  final String id;
  final String name;
  final String subtitle;
  final String source;
  final MangaTaskStatus status;
  final int pageCount;
  final int donePages;
  final int batchNo;
  final DateTime createdAt;
  final DateTime? completedAt;

  bool get deletable => status != MangaTaskStatus.translating && status != MangaTaskStatus.queued;

  MangaTask copyWith({MangaTaskStatus? status, int? donePages, DateTime? completedAt}) {
    return MangaTask(
      id: id,
      name: name,
      subtitle: subtitle,
      source: source,
      status: status ?? this.status,
      pageCount: pageCount,
      donePages: donePages ?? this.donePages,
      batchNo: batchNo,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// 一次投放的回执：已提交张数与在队列中的位次。
class SubmitResult {
  const SubmitResult({required this.submitted, required this.position});
  final int submitted;
  final int position;
}
