import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/online_repository.dart';
import '../data/online_store.dart';
import '../data/source_import.dart';
import '../domain/online_models.dart';
import '../data/demo_online_data.dart';
import '../domain/online_source.dart';
import '../domain/source_manifest.dart';

/// 已导入的漫画源（平台列表三态由 AsyncValue 承担）。
final onlineSourcesProvider = AsyncNotifierProvider<OnlineSourcesNotifier, List<OnlineSource>>(
  OnlineSourcesNotifier.new,
  retry: (_, _) => null,
);

class OnlineSourcesNotifier extends AsyncNotifier<List<OnlineSource>> {
  OnlineStore get _store => ref.read(onlineRepositoryProvider).store;

  @override
  Future<List<OnlineSource>> build() => _store.loadSources();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_store.loadSources);
  }

  List<OnlineSource> get _value => state.value ?? const [];

  void _commit(List<OnlineSource> next) {
    state = AsyncData(next);
    _store.saveSources(next);
  }

  /// 导入结果写入源列表（同名 id 覆盖；调用方负责二次确认）。
  Future<OnlineSource> addOrReplace(OnlineSource source) async {
    final next = [..._value];
    final index = next.indexWhere((item) => item.id == source.id);
    final withTimestamp = source.copyWith(importedAt: DateTime.now());
    if (index >= 0) {
      next[index] = withTimestamp;
    } else {
      next.add(withTimestamp);
    }
    _commit(next);
    ref.read(onlineSourceSelectionProvider.notifier).select(source.id);
    return withTimestamp;
  }

  Future<void> toggle(String id, bool enabled) async {
    _commit([
      for (final source in _value)
        if (source.id == id) source.copyWith(enabled: enabled) else source,
    ]);
    if (!enabled) {
      final active = ref.read(onlineSourceSelectionProvider);
      if (active == id) ref.read(onlineSourceSelectionProvider.notifier).select(null);
    }
  }

  Future<void> remove(String id) async {
    _commit(_value.where((source) => source.id != id).toList());
    await _store.clearSourceCache(id);
    if (ref.read(onlineSourceSelectionProvider) == id) {
      ref.read(onlineSourceSelectionProvider.notifier).select(null);
    }
  }

  void markUsed(String id) {
    _commit([
      for (final source in _value)
        if (source.id == id) source.copyWith(lastUsedAt: DateTime.now(), consecutiveFailures: 0) else source,
    ]);
  }

  /// 引擎调用失败时累计；连续 3 次由 UI 标红并熔断。
  void markFailure(String id) {
    _commit([
      for (final source in _value)
        if (source.id == id) source.copyWith(consecutiveFailures: source.consecutiveFailures + 1) else source,
    ]);
  }

  void markSuccess(String id) {
    OnlineSource? source;
    for (final item in _value) {
      if (item.id == id) {
        source = item;
        break;
      }
    }
    if (source == null || source.consecutiveFailures == 0) return;
    _commit([
      for (final item in _value)
        if (item.id == id) item.copyWith(consecutiveFailures: 0) else item,
    ]);
  }

  OnlineSource? byId(String? id) {
    if (id == null) return null;
    for (final source in _value) {
      if (source.id == id) return source;
    }
    return null;
  }
}

/// 当前选中的源 id；null = 自动取第一个可用源。
final onlineSourceSelectionProvider = NotifierProvider<OnlineSourceSelectionNotifier, String?>(
  OnlineSourceSelectionNotifier.new,
);

class OnlineSourceSelectionNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(onlineRepositoryProvider).store.selectedSourceId;

  void select(String? id) {
    state = id;
    if (id != null) ref.read(onlineRepositoryProvider).store.saveSelectedSource(id);
  }
}

/// 当前生效的源：选中且启用 > 第一个启用的源 > 第一个源。
final activeOnlineSourceProvider = Provider<OnlineSource?>((ref) {
  final sources = ref.watch(onlineSourcesProvider).value;
  if (sources == null || sources.isEmpty) return null;
  final wanted = ref.watch(onlineSourceSelectionProvider);
  if (wanted != null) {
    for (final source in sources) {
      if (source.id == wanted && source.enabled) return source;
    }
  }
  for (final source in sources) {
    if (source.enabled) return source;
  }
  for (final source in sources) {
    if (source.id == wanted) return source;
  }
  return sources.first;
});

/// 导入源包（供设置页 / 移动端源 sheet 共用）。
final sourceImporterProvider = Provider<SourceImporter>((ref) => SourceImporter());

/// 最近一次导入结果（用于设置页分级提示）。
final onlineImportResultProvider = NotifierProvider<OnlineImportResultNotifier, SourceImportResult?>(
  OnlineImportResultNotifier.new,
);

class OnlineImportResultNotifier extends Notifier<SourceImportResult?> {
  @override
  SourceImportResult? build() => null;

  void set(SourceImportResult? value) => state = value;

  void clear() => state = null;
}

/// 第一次进入在线漫画时的合规声明。
final onlineDisclaimerProvider = NotifierProvider<OnlineDisclaimerNotifier, bool>(OnlineDisclaimerNotifier.new);

class OnlineDisclaimerNotifier extends Notifier<bool> {
  @override
  bool build() => !ref.read(onlineRepositoryProvider).store.disclaimerSeen;

  void accept() {
    ref.read(onlineRepositoryProvider).store.markDisclaimerSeen();
    state = false;
  }
}

/// 分类兜底标记：categories 请求失败时仍渲染常用题材。
final onlineCategoriesFallbackProvider = NotifierProvider<CategoriesFallbackNotifier, bool>(
  CategoriesFallbackNotifier.new,
);

class CategoriesFallbackNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// 源 id 是否已存在（导入覆盖确认用）。
bool sourceIdExists(List<OnlineSource> sources, SourceManifest manifest) =>
    sources.any((source) => source.id == manifest.id);

/// 分类兜底数据：请求失败时 UI 仍能展示常用题材（设计稿 §分类边界）。
List<CategoryGroup> categoriesFallback() => DemoOnlineData.categoryGroups;
