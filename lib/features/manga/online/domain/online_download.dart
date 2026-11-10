import 'online_models.dart';

/// 下载目标：桌面端写入本地漫画库；移动端只做离线缓存（plan §8.4）。
enum DownloadTarget { library, cache }

enum DownloadStatus { queued, downloading, paused, done, partial, canceled, failed }

/// 下载任务（整章为最小调度单位，设计稿 §下载）。
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.sourceId,
    required this.comicId,
    required this.comicTitle,
    required this.coverTone,
    required this.chapterId,
    required this.chapterTitle,
    required this.total,
    required this.done,
    required this.status,
    required this.target,
    this.translate = false,
    this.failed = 0,
    this.updatedAt,
  });

  final String id;
  final String sourceId;
  final String comicId;
  final String comicTitle;
  final CoverTone coverTone;
  final String chapterId;
  final String chapterTitle;
  final int total;
  final int done;
  final int failed;
  final DownloadStatus status;
  final DownloadTarget target;
  final bool translate;
  final DateTime? updatedAt;

  String get key => '$sourceId|$comicId|$chapterId';
  double get fraction => total <= 0 ? 0 : (done / total).clamp(0, 1);
  bool get isActive => status == DownloadStatus.downloading || status == DownloadStatus.queued;
  bool get isPaused => status == DownloadStatus.paused;
  bool get isFinished => status == DownloadStatus.done || status == DownloadStatus.partial;
  bool get canPause => status == DownloadStatus.downloading || status == DownloadStatus.queued;
  bool get canResume =>
      status == DownloadStatus.paused || status == DownloadStatus.canceled || status == DownloadStatus.partial;
  bool get canCancel => status != DownloadStatus.done && status != DownloadStatus.canceled;

  DownloadTask copyWith({int? done, int? failed, DownloadStatus? status, DateTime? updatedAt}) => DownloadTask(
    id: id,
    sourceId: sourceId,
    comicId: comicId,
    comicTitle: comicTitle,
    coverTone: coverTone,
    chapterId: chapterId,
    chapterTitle: chapterTitle,
    total: total,
    done: done ?? this.done,
    failed: failed ?? this.failed,
    status: status ?? this.status,
    target: target,
    translate: translate,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'comicId': comicId,
    'comicTitle': comicTitle,
    'coverTone': coverTone.name,
    'chapterId': chapterId,
    'chapterTitle': chapterTitle,
    'total': total,
    'done': done,
    'failed': failed,
    'status': status.name,
    'target': target.name,
    'translate': translate,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  static DownloadTask? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final sourceId = json['sourceId'];
    final comicId = json['comicId'];
    final chapterId = json['chapterId'];
    if (id is! String || sourceId is! String || comicId is! String || chapterId is! String) return null;
    return DownloadTask(
      id: id,
      sourceId: sourceId,
      comicId: comicId,
      comicTitle: '${json['comicTitle'] ?? ''}',
      coverTone: CoverTone.values.firstWhere((tone) => tone.name == json['coverTone'], orElse: () => CoverTone.blue),
      chapterId: chapterId,
      chapterTitle: '${json['chapterTitle'] ?? ''}',
      total: (json['total'] as num?)?.toInt() ?? 0,
      done: (json['done'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      status: DownloadStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => DownloadStatus.queued,
      ),
      target: DownloadTarget.values.firstWhere(
        (target) => target.name == json['target'],
        orElse: () => DownloadTarget.library,
      ),
      translate: json['translate'] == true,
      updatedAt: DateTime.tryParse('${json['updatedAt']}'),
    );
  }
}

/// 下载快照：队列 + 加载 / 错误状态（三态由 controller 负责）。
class DownloadQueue {
  const DownloadQueue({this.tasks = const [], this.loading = false, this.error});

  final List<DownloadTask> tasks;
  final bool loading;
  final Object? error;

  DownloadQueue copyWith({List<DownloadTask>? tasks, bool? loading, Object? error, bool clearError = false}) =>
      DownloadQueue(
        tasks: tasks ?? this.tasks,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );

  int get activeCount => tasks.where((task) => task.isActive).length;

  DownloadQueue upsert(DownloadTask task) {
    final next = [...tasks];
    final index = next.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      next[index] = task;
    } else {
      next.insert(0, task);
    }
    return copyWith(tasks: next);
  }
}

/// 翻译状态机（设计稿 7 态）。
enum TranslationState { idle, queued, running, done, partial, failed, unavailable }

class TranslationStatus {
  const TranslationStatus({this.state = TranslationState.idle, this.done = 0, this.total = 0, this.failed = 0});

  final TranslationState state;
  final int done;
  final int total;
  final int failed;

  double get fraction => total <= 0 ? 0 : (done / total).clamp(0, 1);
  bool get translatedReady =>
      done > 0 &&
      (state == TranslationState.done || state == TranslationState.partial || state == TranslationState.running);

  TranslationStatus copyWith({TranslationState? state, int? done, int? total, int? failed}) => TranslationStatus(
    state: state ?? this.state,
    done: done ?? this.done,
    total: total ?? this.total,
    failed: failed ?? this.failed,
  );

  Map<String, Object?> toJson() => {'state': state.name, 'done': done, 'total': total, 'failed': failed};

  static TranslationStatus fromJson(Map<String, Object?> json) => TranslationStatus(
    state: TranslationState.values.firstWhere(
      (state) => state.name == json['state'],
      orElse: () => TranslationState.idle,
    ),
    done: (json['done'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
    failed: (json['failed'] as num?)?.toInt() ?? 0,
  );
}
