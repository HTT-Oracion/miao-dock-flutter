import 'dart:convert';
import 'dart:io';

import '../../../../../core/storage/shell_prefs.dart';
import '../../../domain/js_music_source.dart';
import '../../../domain/music_source_manifest.dart';
import 'music_source_dto.dart' show scanMusicSourceCapabilities;

/// 音乐源导入器：**JS 即包**（与漫画源同口径）。
///
/// 清单字段从 JS 类字段推导（name / key / version / baseUrl / platform 是源作者
/// 声明在类里的事实源；hosts 从 JS 实际出现的 URL 扫描）。`music_source.json`
/// 可选且只有两个覆盖项：timeoutMs / headers。
///
/// 三条入口都汇入 [install]：本地目录 / 远程裸 JS / 远程目录（index.json）。
class MusicSourceImporter {
  MusicSourceImporter({this.maxJsBytes = 2 * 1024 * 1024, Directory? Function()? rootResolver})
    : _rootResolver = rootResolver ?? musicSourceStateDirectory;

  final int maxJsBytes;

  /// 状态目录解析器（测试注入临时目录，保证隔离）。
  final Directory? Function() _rootResolver;

  /// 导入裸 JS（本地文件 / 远程脚本）。
  Future<MusicSourceImportResult> importScript(
    String js, {
    String fileName = 'source.js',
    String? catalogKey,
    String? catalogName,
    String? catalogVersion,
    int? timeoutMs,
    Map<String, String> headers = const {},
  }) async {
    if (js.length > maxJsBytes) {
      return const MusicSourceImportResult(errors: [MusicSourceIssue('js_too_large')]);
    }
    final (manifest, issues) = manifestFromScript(
      js,
      fileName,
      catalogKey: catalogKey,
      catalogName: catalogName,
      catalogVersion: catalogVersion,
      timeoutMs: timeoutMs,
      headers: headers,
    );
    if (manifest == null) {
      return MusicSourceImportResult(errors: [for (final i in issues) MusicSourceIssue(i)]);
    }
    final capabilities = scanMusicSourceCapabilities(js);
    if (capabilities.isEmpty) {
      return MusicSourceImportResult(manifest: manifest, errors: const [MusicSourceIssue('no_capability')]);
    }
    final source = JsMusicSource(manifest: manifest, capabilities: capabilities);
    final installed = await install(manifest, js);
    return MusicSourceImportResult(manifest: manifest, source: source, installedAt: installed);
  }

  /// 从本地目录导入：优先裸 JS，兼容旧式 `music_source.json`（只读覆盖项）。
  Future<MusicSourceImportResult> importFromDirectory(Directory dir) async {
    final manifestFile = File('${dir.path}/music_source.json');
    int? timeoutMs;
    Map<String, String> headers = const {};
    if (manifestFile.existsSync()) {
      try {
        final decoded = jsonDecode(manifestFile.readAsStringSync());
        if (decoded is Map) {
          timeoutMs = (decoded['timeoutMs'] as num?)?.toInt();
          headers = {
            for (final e in ((decoded['headers'] as Map?) ?? const {}).entries)
              if (e.key is String && e.value is String) '${e.key}': '${e.value}',
          };
        }
      } catch (_) {
        // 坏 json 当没有覆盖项处理。
      }
    }
    // JS 文件：目录里唯一的 .js；多个同名不可能（manifest 不再承载文件名）。
    final jsFiles = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.js')).toList();
    if (jsFiles.isEmpty) {
      return const MusicSourceImportResult(errors: [MusicSourceIssue('source_file_missing')]);
    }
    return importScript(
      jsFiles.first.readAsStringSync(),
      fileName: jsFiles.first.uri.pathSegments.last,
      timeoutMs: timeoutMs,
      headers: headers,
    );
  }

  /// 落盘 `music-sources/<id>/`。同 id 重复导入 = 覆盖升级。
  Future<Directory> install(MusicSourceManifest manifest, String js) async {
    final root = _rootResolver();
    if (root == null) throw StateError('music source directory unavailable');
    final target = Directory('${root.path}/${manifest.id}');
    if (target.existsSync()) target.deleteSync(recursive: true);
    await target.create(recursive: true);
    await File('${target.path}/${manifest.sourceFile}').writeAsString(js, flush: true);
    return target;
  }

  /// 枚举已安装的源（启动时恢复；坏包跳过）。
  List<JsMusicSource> installedSources() {
    final root = _rootResolver();
    if (root == null) return const [];
    final out = <JsMusicSource>[];
    for (final dir in root.listSync().whereType<Directory>()) {
      try {
        final jsFiles = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.js')).toList();
        if (jsFiles.isEmpty) continue;
        final js = jsFiles.first.readAsStringSync();
        final fileName = jsFiles.first.uri.pathSegments.last;
        int? timeoutMs;
        Map<String, String> headers = const {};
        final mf = File('${dir.path}/music_source.json');
        if (mf.existsSync()) {
          try {
            final decoded = jsonDecode(mf.readAsStringSync());
            if (decoded is Map) {
              timeoutMs = (decoded['timeoutMs'] as num?)?.toInt();
              headers = {
                for (final e in ((decoded['headers'] as Map?) ?? const {}).entries)
                  if (e.key is String && e.value is String) '${e.key}': '${e.value}',
              };
            }
          } catch (_) {}
        }
        final (manifest, _) = manifestFromScript(js, fileName, timeoutMs: timeoutMs, headers: headers);
        if (manifest == null) continue;
        // 启用状态持久化在源目录的 state.json（卸载随目录一起删）。
        var enabled = true;
        final stateFile = File('${dir.path}/state.json');
        if (stateFile.existsSync()) {
          try {
            final decoded = jsonDecode(stateFile.readAsStringSync());
            if (decoded is Map && decoded['enabled'] == false) enabled = false;
          } catch (_) {}
        }
        out.add(JsMusicSource(manifest: manifest, capabilities: scanMusicSourceCapabilities(js), enabled: enabled));
      } catch (_) {
        // 单个坏包不拖垮整体枚举。
      }
    }
    return out;
  }

  Future<void> uninstall(String sourceId) async {
    final root = _rootResolver();
    final dir = root == null ? null : Directory('${root.path}/$sourceId');
    if (dir != null && dir.existsSync()) await dir.delete(recursive: true);
  }

  /// 启用 / 停用某源（停用后不参与仓库装配与平台清单，卸载不丢）。
  Future<void> setEnabled(String sourceId, bool enabled) async {
    final root = _rootResolver();
    final dir = root == null ? null : Directory('${root.path}/$sourceId');
    if (dir == null || !dir.existsSync()) return;
    await File('${dir.path}/state.json').writeAsString(jsonEncode({'enabled': enabled}), flush: true);
  }
}

class MusicSourceImportResult {
  const MusicSourceImportResult({this.manifest, this.source, this.errors = const [], this.installedAt});

  final MusicSourceManifest? manifest;
  final JsMusicSource? source;
  final List<MusicSourceIssue> errors;
  final Directory? installedAt;

  bool get ok => source != null && errors.isEmpty;
}

/// 导入期问题（code 由 UI 映射 ARB，detail 只进日志）。
class MusicSourceIssue {
  const MusicSourceIssue(this.code, [this.detail = '']);

  final String code;
  final String detail;

  @override
  String toString() => detail.isEmpty ? code : '$code: $detail';
}
