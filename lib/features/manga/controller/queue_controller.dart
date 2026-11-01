import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_controller.dart';

import 'package:protocol/protocol.dart';

import '../data/contract_map.dart';
import '../domain/manga_task.dart';

/// mangasvc 客户端：默认 A 级 Fake；真实现由 bootstrap 按平台注入（AGENTS §3）。
final mangaSvcClientProvider = Provider<MangaSvcClient>((ref) => FakeMangaSvcClient());

/// 队列轮询（D-074）。
///
/// 🔴 之前**没有任何轮询**：任务列表只在投递/取消时刷新一次。
/// 服务端其实在跑，但界面永远停在提交那一刻的快照 —— 看起来就是「一直排队中」，
/// 取消后进度也还在动（实际是界面不会再更新）。
///
/// 用「被 watch 才启动」的 Provider 承载定时器：页面在场才轮询，离开自动停。
/// 翻译日志轮询（D-075）：设置页「模型 → 翻译日志」用；1s 拉一次。
final translateLogProvider = AsyncNotifierProvider<TranslateLogNotifier, List<String>>(TranslateLogNotifier.new);

class TranslateLogNotifier extends AsyncNotifier<List<String>> {
  Timer? _timer;

  @override
  Future<List<String>> build() async {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    ref.onDispose(() => _timer?.cancel());
    final r = await ref.read(mangaSvcClientProvider).getTranslateLog();
    return (r['tail'] as List?)?.cast<String>() ?? const [];
  }

  Future<void> refresh() async {
    try {
      final r = await ref.read(mangaSvcClientProvider).getTranslateLog();
      state = AsyncValue.data((r['tail'] as List?)?.cast<String>() ?? const []);
    } catch (_) {
      // 服务不可达时保留旧日志，不清空。
    }
  }
}

final queuePollerProvider = Provider<void>((ref) {
  var lastSignature = '';
  final timer = Timer.periodic(const Duration(seconds: 1), (_) async {
    await ref.read(queueProvider.notifier).refresh();
    final tasks = ref.read(queueProvider).value ?? const <MangaTask>[];
    // 状态签名：任一条状态/进度变化都算（B.8 任务完成 → 漫画库状态同步）。
    final signature = [for (final t in tasks) '${t.id}:${t.status.name}:${t.donePages}'].join('|');
    if (signature == lastSignature) return;
    final hadTerminalChange = lastSignature.isNotEmpty && signature != lastSignature;
    lastSignature = signature;
    if (hadTerminalChange) {
      // 队列变化时刷新书架：任务落盘后漫画库状态（页数/已译）必须跟着更新。
      await ref.read(libraryProvider.notifier).refresh();
    }
  });
  ref.onDispose(timer.cancel);
});

/// 队列任务列表（串行队列全量）。
final queueProvider = AsyncNotifierProvider<QueueNotifier, List<MangaTask>>(QueueNotifier.new);

class QueueNotifier extends AsyncNotifier<List<MangaTask>> {
  List<MangaTask> _lastGood = const [];

  /// 最近一次成功拉取的任务（错误态时 UI 仍展示它，见设计稿 H Note 07）。
  List<MangaTask> get lastGood => _lastGood;

  /// 首次加载：**返回 Future 让 Riverpod 自己判状态**。
  ///
  /// 🔴 这里不能「catch 后吞掉再 return 空列表」：那样 `build()` 正常完成，
  /// provider 状态是 `AsyncData([])`，UI 会把它当**空态**画 —— 失败被伪装成
  /// 「没有任务」，正是 design.html §07 禁止的。必须让异常抛出去成为 `AsyncError`。
  @override
  Future<List<MangaTask>> build() async {
    final response = await ref.read(mangaSvcClientProvider).listTasks();
    final tasks = response.tasks.map(toMangaTask).toList();
    _lastGood = tasks;
    return tasks;
  }

  /// 重试 / 刷新。
  Future<void> refresh() async {
    state = const AsyncLoading<List<MangaTask>>();
    state = await AsyncValue.guard(() async {
      final response = await ref.read(mangaSvcClientProvider).listTasks();
      final tasks = response.tasks.map(toMangaTask).toList();
      _lastGood = tasks;
      return tasks;
    });
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

  /// 重试/继续任务（D-075）：失败 → 重跑；取消 → 续跑。
  Future<void> retry(String taskId) async {
    await ref.read(mangaSvcClientProvider).retryTask(taskId);
    await refresh();
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
