import 'dart:convert';
import 'dart:io';

import '../../../../core/storage/shell_prefs.dart';
import '../domain/online_download.dart';
import '../domain/online_error.dart';
import '../domain/online_models.dart';
import '../domain/online_source.dart';
import '../domain/source_library.dart';

/// 在线漫画的本地持久层。
///
/// 全部落 shell prefs 文件（`FLUTTER_TEST` 下自动隔离），不新增依赖：
/// 源清单 / 阅读进度 / 已读章节 / 下载任务 / 声明状态。
class OnlineStore {
  static const keySources = 'miao.online-sources';
  static const keyProgress = 'miao.online-progress';
  static const keyReadChapters = 'miao.online-read-chapters';
  static const keyDownloads = 'miao.online-downloads';
  static const keyDisclaimer = 'miao.online-disclaimer-seen';
  static const keySelectedSource = 'miao.online-selected-source';
  static const keyLibraries = 'miao.online-libraries';

  /// 读取源清单。**缺键** = 首次启动，写入设计稿的 3 个 demo 源；
  /// 已写入空数组 = 用户删光了，保持空态（不能每次启动又长回来）。
  Future<List<OnlineSource>> loadSources() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final raw = readRawPref(keySources);
    if (raw == null) {
      // 应用不内置任何在线源（设计稿免责声明 / plan §13）：首次启动是空态，
      // 用户必须自己导入 source.json。自测里的 3 个源由测试 store 注入。
      saveSources(const []);
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('sources');
      final sources = <OnlineSource>[];
      for (final item in decoded) {
        if (item is Map) {
          final source = OnlineSource.fromJson(Map<String, Object?>.from(item));
          if (source != null) sources.add(source);
        }
      }
      return sources;
    } catch (_) {
      throw const OnlineException(OnlineErrorCode.parse, 'source list corrupt');
    }
  }

  void saveSources(List<OnlineSource> sources) {
    writeRawPref(keySources, jsonEncode([for (final source in sources) source.toJson()]));
  }

  Future<List<SourceLibrary>> loadLibraries() async {
    final raw = readRawPref(keyLibraries);
    if (raw == null) {
      saveLibraries(const []);
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <SourceLibrary>[];
      for (final item in decoded) {
        if (item is Map) {
          final library = SourceLibrary.fromJson(Map<String, Object?>.from(item));
          if (library != null) result.add(library);
        }
      }
      result.sort((a, b) => a.priority.compareTo(b.priority));
      return result;
    } catch (_) {
      return const [];
    }
  }

  void saveLibraries(List<SourceLibrary> libraries) {
    writeRawPref(keyLibraries, jsonEncode([for (final library in libraries) library.toJson()]));
  }

  Future<List<ReadingProgress>> loadProgress() async {
    final raw = readRawPref(keyProgress);
    if (raw == null) {
      saveProgress(const []);
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <ReadingProgress>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final progress = ReadingProgress.fromJson(Map<String, Object?>.from(item));
        if (progress != null) result.add(progress);
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  void saveProgress(List<ReadingProgress> progress) {
    writeRawPref(keyProgress, jsonEncode([for (final item in progress) item.toJson()]));
  }

  Future<Map<String, Set<String>>> loadReadChapters() async {
    final raw = readRawPref(keyReadChapters);
    if (raw == null) {
      saveReadChapters(const {});
      return const {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is List)
            '${entry.key}': entry.value is List ? (entry.value as List).whereType<String>().toSet() : <String>{},
      };
    } catch (_) {
      return {};
    }
  }

  void saveReadChapters(Map<String, Set<String>> read) {
    writeRawPref(keyReadChapters, jsonEncode({for (final entry in read.entries) entry.key: entry.value.toList()}));
  }

  Future<List<DownloadTask>> loadDownloads() async {
    final raw = readRawPref(keyDownloads);
    if (raw == null) {
      saveDownloads(const []);
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <DownloadTask>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final task = DownloadTask.fromJson(Map<String, Object?>.from(item));
        if (task != null) result.add(task);
      }
      return result;
    } catch (_) {
      throw const OnlineException(OnlineErrorCode.parse, 'download queue corrupt');
    }
  }

  void saveDownloads(List<DownloadTask> tasks) {
    writeRawPref(keyDownloads, jsonEncode([for (final task in tasks) task.toJson()]));
  }

  bool get disclaimerSeen => readRawPref(keyDisclaimer) == '1';

  void markDisclaimerSeen() => writeRawPref(keyDisclaimer, '1');

  String? get selectedSourceId => readRawPref(keySelectedSource);

  void saveSelectedSource(String id) => writeRawPref(keySelectedSource, id);

  /// 测试 / 售后排障用：清掉模块自己的持久化状态。
  void reset() {
    writeRawPref(keySources, '[]');
    writeRawPref(keyProgress, '[]');
    writeRawPref(keyReadChapters, '{}');
    writeRawPref(keyDownloads, '[]');
    writeRawPref(keyDisclaimer, '0');
    writeRawPref(keyLibraries, '[]');
  }

  /// 把某个源的缓存 / Cookie 清掉（删除源时调用）。目前只有图片缓存目录约定。
  Future<void> clearSourceCache(String sourceId) async {
    final root = onlineStateDirectory();
    if (root == null) return;
    final dir = Directory('${root.path}/images/$sourceId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
