import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/online_repository.dart';
import '../domain/online_download.dart';
import '../domain/online_models.dart';
import '../domain/online_source.dart';

/// 下载 / 离线缓存队列（整章为最小调度单位）。
final onlineDownloadsProvider = AsyncNotifierProvider<OnlineDownloadsNotifier, List<DownloadTask>>(
  OnlineDownloadsNotifier.new,
  retry: (_, _) => null,
);

class OnlineDownloadsNotifier extends AsyncNotifier<List<DownloadTask>> {
  final Map<String, Timer> _timers = {};

  @override
  Future<List<DownloadTask>> build() async {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return ref.read(onlineRepositoryProvider).store.loadDownloads();
  }

  List<DownloadTask> get _value => state.value ?? const [];

  void _commit(List<DownloadTask> tasks) {
    state = AsyncData(tasks);
    ref.read(onlineRepositoryProvider).store.saveDownloads(tasks);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async => ref.read(onlineRepositoryProvider).store.loadDownloads());
  }

  /// 从详情页发起：先向源要一次页列表拿到真实页数，再建整章任务。
  Future<DownloadTask?> begin({
    required OnlineSource source,
    required OnlineComic comic,
    required OnlineChapter chapter,
    required DownloadTarget target,
    bool translate = false,
  }) async {
    final existing = byComicChapter(sourceId: source.id, comicId: comic.id, chapterId: chapter.id);
    if (existing != null) return existing;
    var pageCount = 26;
    try {
      final pages = await ref.read(onlineRepositoryProvider).pages(source, comic.id, chapter.id);
      pageCount = pages.length;
    } catch (_) {
      // 取页列表失败时按设计稿的 26 页占位创建任务，下载器会逐页重试。
    }
    return start(
      source: OnlineSourceRef(id: source.id, name: source.name),
      comic: comic,
      chapter: chapter,
      pageCount: pageCount,
      target: target,
      translate: translate,
    );
  }

  /// 新建整章任务；已经存在同章任务时不重复建单（幂等）。
  DownloadTask? start({
    required OnlineSourceRef source,
    required OnlineComic comic,
    required OnlineChapter chapter,
    required int pageCount,
    required DownloadTarget target,
    bool translate = false,
  }) {
    final key = '${source.id}|${comic.id}|${chapter.id}';
    for (final task in _value) {
      if (task.key == key) return task;
    }
    final task = DownloadTask(
      id: 'dl-${source.id}-${comic.id}-${chapter.id}',
      sourceId: source.id,
      comicId: comic.id,
      comicTitle: comic.title,
      coverTone: comic.coverTone,
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      total: pageCount,
      done: 0,
      status: DownloadStatus.downloading,
      target: target,
      translate: translate,
      updatedAt: DateTime.now(),
    );
    final next = [task, ..._value];
    _commit(next);
    ref.read(onlineDownloadNoticeProvider.notifier).publish(task, DownloadNoticeKind.started);
    _simulate(task.id);
    return task;
  }

  void _simulate(String taskId) {
    _timers[taskId]?.cancel();
    _timers[taskId] = Timer.periodic(const Duration(milliseconds: 420), (timer) {
      final tasks = _value;
      final index = tasks.indexWhere((task) => task.id == taskId);
      if (index < 0) {
        timer.cancel();
        _timers.remove(taskId);
        return;
      }
      final task = tasks[index];
      if (task.status != DownloadStatus.downloading) {
        timer.cancel();
        _timers.remove(taskId);
        return;
      }
      final done = (task.done + 2).clamp(0, task.total);
      final finished = done >= task.total;
      final nextTask = task.copyWith(
        done: done,
        status: finished ? DownloadStatus.done : DownloadStatus.downloading,
        updatedAt: DateTime.now(),
      );
      _commit([
        for (var i = 0; i < tasks.length; i++)
          if (i == index) nextTask else tasks[i],
      ]);
      if (finished) {
        timer.cancel();
        _timers.remove(taskId);
        ref.read(onlineDownloadNoticeProvider.notifier).publish(nextTask, DownloadNoticeKind.completed);
      }
    });
  }

  void pause(String id) {
    _timers.remove(id)?.cancel();
    _updateTask(id, (task) => task.copyWith(status: DownloadStatus.paused, updatedAt: DateTime.now()));
  }

  void resume(String id) {
    final task = _taskById(id);
    if (task == null) return;
    _updateTask(id, (task) => task.copyWith(status: DownloadStatus.downloading, updatedAt: DateTime.now()));
    _simulate(id);
  }

  void cancel(String id) {
    _timers.remove(id)?.cancel();
    _updateTask(id, (task) => task.copyWith(status: DownloadStatus.canceled, updatedAt: DateTime.now()));
  }

  void pauseAll() {
    for (final task in _value) {
      if (task.canPause) pause(task.id);
    }
  }

  void resumeAll() {
    for (final task in _value) {
      if (task.canResume) resume(task.id);
    }
  }

  void _updateTask(String id, DownloadTask Function(DownloadTask task) update) {
    final tasks = _value;
    final index = tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    _commit([
      for (var i = 0; i < tasks.length; i++)
        if (i == index) update(tasks[i]) else tasks[i],
    ]);
  }

  DownloadTask? _taskById(String id) {
    for (final task in _value) {
      if (task.id == id) return task;
    }
    return null;
  }

  DownloadTask? byComicChapter({required String sourceId, required String comicId, required String chapterId}) {
    for (final task in _value) {
      if (task.sourceId == sourceId && task.comicId == comicId && task.chapterId == chapterId) return task;
    }
    return null;
  }
}

/// 新建任务的最小源信息（避免 controller 依赖 UI 的 OnlineSource 全量字段）。
class OnlineSourceRef {
  const OnlineSourceRef({required this.id, required this.name});

  final String id;
  final String name;
}

enum DownloadNoticeKind { started, completed }

class DownloadNotice {
  const DownloadNotice({required this.task, required this.kind, required this.revision});

  final DownloadTask task;
  final DownloadNoticeKind kind;
  final int revision;
}

final onlineDownloadNoticeProvider = NotifierProvider<OnlineDownloadNoticeNotifier, DownloadNotice?>(
  OnlineDownloadNoticeNotifier.new,
);

class OnlineDownloadNoticeNotifier extends Notifier<DownloadNotice?> {
  int _revision = 0;

  @override
  DownloadNotice? build() => null;

  void publish(DownloadTask task, DownloadNoticeKind kind) {
    state = DownloadNotice(task: task, kind: kind, revision: ++_revision);
  }

  void clear() => state = null;
}
