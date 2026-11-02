import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:protocol/protocol.dart';

/// Android 应用私有目录中的远程漫画镜像；卸载应用时由系统一并删除。
class MobileMirrorStore {
  MobileMirrorStore({MethodChannel channel = const MethodChannel('miao_dock/folder_picker'), bool forceEnabled = false})
    // ignore: prefer_initializing_formals
    : _channel = channel,
      _enabled = forceEnabled || Platform.isAndroid || Platform.isIOS;

  final MethodChannel _channel;
  final bool _enabled;
  Future<Directory?>? _rootFuture;

  Future<Directory?> _root() => _rootFuture ??= _resolveRoot();

  Future<Directory?> _resolveRoot() async {
    if (!_enabled) return null;
    if (Platform.isIOS) {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return null;
      return Directory('$home${Platform.pathSeparator}Documents${Platform.pathSeparator}mobile-manga')
        ..createSync(recursive: true);
    }
    try {
      final path = await _channel.invokeMethod<String>('appDataPath');
      if (path == null || path.isEmpty) return null;
      return Directory(path)..createSync(recursive: true);
    } on PlatformException {
      return null;
    }
  }

  Future<void> saveQueue(Map<String, dynamic> json) => _saveJson('queue.json', json);

  Future<Map<String, dynamic>?> loadQueue() => _loadJson('queue.json');

  Future<void> saveLibrary(Map<String, dynamic> json) => _saveJson('library.json', json);

  Future<Map<String, dynamic>?> loadLibrary() => _loadJson('library.json');

  Future<void> _saveJson(String name, Map<String, dynamic> json) async {
    final root = await _root();
    if (root == null) return;
    await File('${root.path}${Platform.pathSeparator}$name').writeAsString(jsonEncode(json), flush: true);
  }

  Future<Map<String, dynamic>?> _loadJson(String name) async {
    final root = await _root();
    if (root == null) return null;
    final file = File('${root.path}${Platform.pathSeparator}$name');
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> savePage(String comicName, int seq, {required bool translated, required List<int> bytes}) async {
    if (bytes.isEmpty) return;
    final root = await _root();
    if (root == null) return;
    final comic = base64Url.encode(utf8.encode(comicName)).replaceAll('=', '');
    final dir = Directory('${root.path}${Platform.pathSeparator}library${Platform.pathSeparator}$comic')
      ..createSync(recursive: true);
    final variant = translated ? 'translated' : 'original';
    await File('${dir.path}${Platform.pathSeparator}${seq.toString().padLeft(4, '0')}.$variant')
        .writeAsBytes(bytes, flush: true);
  }

  Future<List<int>?> loadPage(String comicName, int seq, {required bool translated}) async {
    final root = await _root();
    if (root == null) return null;
    final comic = base64Url.encode(utf8.encode(comicName)).replaceAll('=', '');
    final variant = translated ? 'translated' : 'original';
    final file = File(
      '${root.path}${Platform.pathSeparator}library${Platform.pathSeparator}$comic'
      '${Platform.pathSeparator}${seq.toString().padLeft(4, '0')}.$variant',
    );
    return file.existsSync() ? file.readAsBytes() : null;
  }

  /// 终态任务的原图与译图全部镜像到手机；状态签名避免每秒重复下载。
  Future<void> syncCompletedTasks(
    TaskListResponse response,
    Future<List<int>> Function(String comicName, int seq, bool translated) fetch,
  ) async {
    final root = await _root();
    if (root == null) return;
    final markerDir = Directory('${root.path}${Platform.pathSeparator}synced')..createSync(recursive: true);
    for (final task in response.tasks) {
      if (task.status.occupiesQueue || task.progress.done == 0) continue;
      final marker = File('${markerDir.path}${Platform.pathSeparator}${task.taskId}-${task.progress.done}.done');
      if (marker.existsSync()) continue;
      for (var seq = 1; seq <= task.progress.total; seq++) {
        for (final translated in [false, true]) {
          try {
            final bytes = await fetch(task.dirName, seq, translated);
            await savePage(task.dirName, seq, translated: translated, bytes: bytes);
          } catch (_) {
            // 部分失败任务允许缺译图；下次进度变化后会用新 marker 再同步。
          }
        }
      }
      await marker.writeAsString(DateTime.now().toUtc().toIso8601String(), flush: true);
    }
  }
}
