import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/online_repository.dart';
import '../domain/online_models.dart';

/// 最近阅读（按更新时间倒序）。
final onlineRecentProvider = AsyncNotifierProvider<OnlineRecentNotifier, List<ReadingProgress>>(
  OnlineRecentNotifier.new,
  retry: (_, _) => null,
);

class OnlineRecentNotifier extends AsyncNotifier<List<ReadingProgress>> {
  @override
  Future<List<ReadingProgress>> build() async {
    final list = await ref.read(onlineRepositoryProvider).store.loadProgress();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// 记录进度：同 `sourceId + comicId + chapterId` 覆盖，否则插入；保留最多 30 条。
  Future<void> record(ReadingProgress progress) async {
    final current = state.value ?? const <ReadingProgress>[];
    final next = [...current];
    final index = next.indexWhere((item) => item.key == progress.key);
    if (index >= 0) {
      next[index] = progress;
    } else {
      next.insert(0, progress);
    }
    next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final trimmed = next.take(30).toList();
    state = AsyncData(trimmed);
    ref.read(onlineRepositoryProvider).store.saveProgress(trimmed);
  }

  ReadingProgress? findByComic(String sourceId, String comicId) {
    for (final item in state.value ?? const <ReadingProgress>[]) {
      if (item.sourceId == sourceId && item.comicId == comicId) return item;
    }
    return null;
  }

  ReadingProgress? byKey(String key) {
    for (final item in state.value ?? const <ReadingProgress>[]) {
      if (item.key == key) return item;
    }
    return null;
  }
}

/// 已读章节（详情页对勾）。
final onlineReadChaptersProvider = AsyncNotifierProvider<OnlineReadChaptersNotifier, Map<String, Set<String>>>(
  OnlineReadChaptersNotifier.new,
  retry: (_, _) => null,
);

class OnlineReadChaptersNotifier extends AsyncNotifier<Map<String, Set<String>>> {
  @override
  Future<Map<String, Set<String>>> build() => ref.read(onlineRepositoryProvider).store.loadReadChapters();

  bool isRead({required String sourceId, required String comicId, required String chapterId}) {
    final map = state.value;
    if (map == null) return false;
    return map[readChaptersKey(sourceId: sourceId, comicId: comicId)]?.contains(chapterId) ?? false;
  }

  Future<void> markRead({required String sourceId, required String comicId, required String chapterId}) async {
    final current = state.value ?? <String, Set<String>>{};
    final key = readChaptersKey(sourceId: sourceId, comicId: comicId);
    final set = {...(current[key] ?? const <String>{})};
    if (!set.add(chapterId)) return;
    final next = {...current, key: set};
    state = AsyncData(next);
    ref.read(onlineRepositoryProvider).store.saveReadChapters(next);
  }
}
