import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/online_repository.dart';
import '../data/source_remote.dart';
import '../domain/source_library.dart';

/// 远程源仓库列表（用户手动添加的 `index.json`）。
final onlineLibrariesProvider = AsyncNotifierProvider<OnlineLibrariesNotifier, List<SourceLibrary>>(
  OnlineLibrariesNotifier.new,
  retry: (_, _) => null,
);

class OnlineLibrariesNotifier extends AsyncNotifier<List<SourceLibrary>> {
  @override
  Future<List<SourceLibrary>> build() => ref.read(onlineRepositoryProvider).store.loadLibraries();

  List<SourceLibrary> get _value => state.value ?? const [];

  void _commit(List<SourceLibrary> next) {
    final sorted = [...next]..sort((a, b) => a.priority.compareTo(b.priority));
    for (var i = 0; i < sorted.length; i++) {
      // priority 只表达顺序，落盘前重新致密化。
      final item = sorted[i];
      sorted[i] = item.copyWith(priority: i);
    }
    state = AsyncData(sorted);
    ref.read(onlineRepositoryProvider).store.saveLibraries(sorted);
  }

  SourceLibrary add(SourceLibrary library) {
    final next = [..._value];
    final index = next.indexWhere(
      (item) => item.id == library.id || canonicalSourceUrl(item.url) == canonicalSourceUrl(library.url),
    );
    if (index >= 0) {
      next[index] = library.copyWith(priority: next[index].priority);
      _commit(next);
      return next[index];
    }
    final created = library.copyWith(priority: next.length);
    next.add(created);
    _commit(next);
    return created;
  }

  Future<void> remove(String id) async {
    _commit(_value.where((item) => item.id != id).toList());
  }

  void toggle(String id, bool enabled) {
    _commit([
      for (final item in _value)
        if (item.id == id) item.copyWith(enabled: enabled) else item,
    ]);
  }

  void markChecked(String id) {
    _commit([
      for (final item in _value)
        if (item.id == id) item.copyWith(lastChecked: DateTime.now()) else item,
    ]);
  }

  SourceLibrary? byId(String id) {
    for (final item in _value) {
      if (item.id == id) return item;
    }
    return null;
  }
}

final sourceRemoteLoaderProvider = Provider<SourceRemoteLoader>((ref) => SourceRemoteLoader());
