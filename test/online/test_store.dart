import 'test_data.dart';

import 'package:miao_dock_flutter/features/manga/online/data/online_store.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_download.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_models.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_source.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/source_library.dart';

/// 测试用 store：不回写真实偏好，直接返回设计稿同构的 3 个源。
class MemoryStore extends OnlineStore {
  MemoryStore({this.sources, this.emptySources = false, List<SourceLibrary> libraries = const []})
    : _libraries = List.of(libraries);

  final List<OnlineSource>? sources;
  final bool emptySources;
  final List<SourceLibrary> _libraries;

  @override
  bool get disclaimerSeen => true;

  @override
  Future<List<OnlineSource>> loadSources() async =>
      emptySources ? const [] : (sources ?? OnlineTestData.seedSources(DateTime.now()));

  @override
  Future<List<SourceLibrary>> loadLibraries() async => List.of(_libraries);

  @override
  void saveLibraries(List<SourceLibrary> libraries) {
    _libraries
      ..clear()
      ..addAll(libraries);
  }

  @override
  Future<List<ReadingProgress>> loadProgress() async => OnlineTestData.seedProgress(DateTime.now());

  @override
  Future<Map<String, Set<String>>> loadReadChapters() async => {
    readChaptersKey(sourceId: 'manhuagui', comicId: 'kimetsu'): {'ep-203', 'ep-202', 'ep-201', 'vol-20'},
  };

  @override
  Future<List<DownloadTask>> loadDownloads() async => OnlineTestData.seedDownloads(DateTime.now());

  @override
  void saveSources(List<OnlineSource> sources) {}

  @override
  void saveProgress(List<ReadingProgress> progress) {}

  @override
  void saveReadChapters(Map<String, Set<String>> read) {}

  @override
  void saveDownloads(List<DownloadTask> tasks) {}

  @override
  void saveSelectedSource(String id) {}

  @override
  String? get selectedSourceId => null;
}
