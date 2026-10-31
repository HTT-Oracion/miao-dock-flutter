import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol/protocol.dart';

import '../data/contract_map.dart';
import '../domain/manga_task.dart';

/// mangasvc 客户端：默认 A 级 Fake；真实现由 bootstrap 按平台注入（AGENTS §3）。
final mangaSvcClientProvider = Provider<MangaSvcClient>((ref) => FakeMangaSvcClient());

/// 队列任务列表（串行队列全量）。
final queueProvider = AsyncNotifierProvider<QueueNotifier, List<MangaTask>>(QueueNotifier.new);

class QueueNotifier extends AsyncNotifier<List<MangaTask>> {
  List<MangaTask> _lastGood = const [];

  /// 最近一次成功拉取的任务（错误态时 UI 仍展示它，见设计稿 H Note 07）。
  List<MangaTask> get lastGood => _lastGood;

  @override
  Future<List<MangaTask>> build() => _fetch();

  Future<void> refresh() async {
    state = const AsyncLoading<List<MangaTask>>();
    await _fetch();
  }

  Future<List<MangaTask>> _fetch() async {
    try {
      final response = await ref.read(mangaSvcClientProvider).listTasks();
      final tasks = response.tasks.map(toMangaTask).toList();
      _lastGood = tasks;
      state = AsyncData(tasks);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
    return _lastGood;
  }

  /// 删除任务记录；ids 为空集表示全量删除可删任务（设计稿 H Note 10）。
  /// 返回实际删除条数（吐司用）。
  Future<int> deleteTasks(Set<String> ids) async {
    final client = ref.read(mangaSvcClientProvider);
    final all = state.value ?? const <MangaTask>[];
    final targets = all.where((t) => t.deletable).toList();
    final affected = ids.isEmpty ? targets : targets.where((t) => ids.contains(t.id)).toList();
    await client.deleteTasks(ids.isEmpty ? null : ids);
    await refresh();
    return affected.length;
  }

  /// 取消任务，返回保留的已落盘张数（吐司用）。
  Future<int> cancelTask(String taskId) async {
    final all = state.value ?? const <MangaTask>[];
    final task = all.firstWhere((t) => t.id == taskId);
    await ref.read(mangaSvcClientProvider).cancelTask(taskId);
    await refresh();
    return task.donePages;
  }

  /// 投放，返回提交结果（吐司用）。
  /// 投放，返回提交结果（吐司用）。
  Future<SubmitOutcome> submit({required String comicName, required List<String> imagePaths}) async {
    final res = await ref.read(mangaSvcClientProvider).createTask(comicName: comicName, imagePaths: imagePaths);
    await refresh();
    return SubmitOutcome(submitted: imagePaths.length, position: res.queuePosition);
  }
}

/// 多选态：enabled = 顶栏进入多选；ids 为勾选集合（空集 = 未勾选）。
typedef SelectionState = ({bool enabled, Set<String> ids});

final selectionProvider = NotifierProvider<SelectionNotifier, SelectionState>(SelectionNotifier.new);

class SelectionNotifier extends Notifier<SelectionState> {
  @override
  SelectionState build() => (enabled: false, ids: const <String>{});

  void toggleMode() => state = (enabled: !state.enabled, ids: state.enabled ? state.ids : const <String>{});

  void toggle(String id) {
    final ids = {...state.ids};
    ids.contains(id) ? ids.remove(id) : ids.add(id);
    state = (enabled: true, ids: ids);
  }

  void selectAllPage(Set<String> deletableIds) => state = (enabled: true, ids: {...deletableIds});

  void clear() => state = (enabled: state.enabled, ids: const <String>{});
}

/// 分页状态（页码从 1 起；页大小 10 / 20 / 50，设计稿 H Note 04）。
typedef PagerState = ({int page, int pageSize});

final pagerProvider = NotifierProvider<PagerNotifier, PagerState>(PagerNotifier.new);

class PagerNotifier extends Notifier<PagerState> {
  @override
  PagerState build() => (page: 1, pageSize: 10);

  void goTo(int page) => state = (page: page, pageSize: state.pageSize);

  /// 切换页大小后按新页大小重算并回到第 1 页（H Note 04）。
  void setPageSize(int size) => state = (page: 1, pageSize: size);
}
