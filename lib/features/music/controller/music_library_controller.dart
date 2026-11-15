import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/shell_prefs.dart';
import '../../../shared/domain/source_library.dart';

/// 音乐源的「源仓库」持久化：与漫画源**同一模型、不同存储键**。
///
/// 仓库语义完全一致（一个 index.json URL → 若干可安装的源），所以模型与解析
/// 复用 `shared/domain/source_library.dart`；只有落盘键与业务侧解释不同。
class MusicLibraryStore {
  static const keyLibraries = 'miao.music-libraries';

  List<SourceLibrary> loadLibraries() {
    final raw = readRawPref(keyLibraries);
    if (raw == null) return const [];
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
}

/// 音乐源仓库列表（设置页「链接导入」卡片下半部分展示）。
final musicLibrariesProvider = NotifierProvider<MusicLibrariesNotifier, List<SourceLibrary>>(
  MusicLibrariesNotifier.new,
);

class MusicLibrariesNotifier extends Notifier<List<SourceLibrary>> {
  final _store = MusicLibraryStore();

  @override
  List<SourceLibrary> build() => _store.loadLibraries();

  List<SourceLibrary> get _value => state;

  void _commit(List<SourceLibrary> next) {
    state = next;
    _store.saveLibraries(next);
  }

  /// 添加仓库（同 URL 已存在则更新名称，不重复添加）。
  SourceLibrary add(SourceLibrary library) {
    final existing = _value.where((item) => item.id == library.id).toList();
    if (existing.isNotEmpty) {
      final updated = library.copyWith(
        enabled: existing.first.enabled,
        priority: existing.first.priority,
        lastChecked: existing.first.lastChecked,
      );
      _commit([
        for (final item in _value)
          if (item.id == library.id) updated else item,
      ]);
      return updated;
    }
    _commit([..._value, library]);
    return library;
  }

  void markChecked(String id) {
    final now = DateTime.now();
    _commit([
      for (final item in _value)
        if (item.id == id) item.copyWith(lastChecked: now) else item,
    ]);
  }

  void remove(String id) => _commit([
    for (final item in _value)
      if (item.id != id) item,
  ]);

  void setEnabled(String id, bool enabled) => _commit([
    for (final item in _value)
      if (item.id == id) item.copyWith(enabled: enabled) else item,
  ]);

  SourceLibrary? byId(String id) {
    for (final item in _value) {
      if (item.id == id) return item;
    }
    return null;
  }
}
