import 'package:miao_dock_flutter/features/manga/online/data/demo_online_data.dart';
import 'package:miao_dock_flutter/features/manga/online/data/online_store.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_download.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_models.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_source.dart';

/// 测试用 store：不回写真实偏好，直接返回设计稿同构的 3 个源。
class MemoryStore extends OnlineStore {
  MemoryStore({this.sources = const []});

  final List<OnlineSource> sources;

  @override
  bool get disclaimerSeen => true;

  @override
  Future<List<OnlineSource>> loadSources() async =>
      sources.isEmpty ? DemoOnlineData.seedSources(DateTime.now()) : sources;

  @override
  Future<List<ReadingProgress>> loadProgress() async => DemoOnlineData.seedProgress(DateTime.now());

  @override
  Future<Map<String, Set<String>>> loadReadChapters() async => {
    readChaptersKey(sourceId: 'manhuagui', comicId: 'kimetsu'): {'ep-203', 'ep-202', 'ep-201', 'vol-20'},
  };

  @override
  Future<List<DownloadTask>> loadDownloads() async => DemoOnlineData.seedDownloads(DateTime.now());

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
