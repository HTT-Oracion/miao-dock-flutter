import 'dart:io';

import '../../../../core/storage/shell_prefs.dart';
import '../domain/online_models.dart';
import '../domain/online_source.dart';
import '../domain/source_manifest.dart';

/// 导入阶段的结构化问题（code 由 UI 映射 ARB，detail 仅作日志/详情）。
class SourceIssue {
  const SourceIssue(this.code, [this.detail = '']);

  final String code;
  final String detail;

  @override
  String toString() => detail.isEmpty ? code : '$code: $detail';
}

class SourceImportResult {
  const SourceImportResult({this.source, this.errors = const [], this.warnings = const []});

  final OnlineSource? source;
  final List<SourceIssue> errors;
  final List<SourceIssue> warnings;

  bool get ok => source != null && errors.isEmpty;
}

/// `source.json` 包导入器（plan §7.5 四步的前三步）。
///
/// 第四步「写入源列表」由 controller 负责。真正的 JS 执行留给 QuickJS 引擎；
/// 这里做静态校验：字段 → 入口类继承 → 能力函数存在 → 复制到源目录。
class SourceImporter {
  SourceImporter({this.maxJsBytes = 2 * 1024 * 1024});

  final int maxJsBytes;

  Future<SourceImportResult> importManifest(String manifestPath) async {
    final manifestFile = File(manifestPath);
    if (!await manifestFile.exists()) {
      return const SourceImportResult(errors: [SourceIssue('invalidJson')]);
    }

    final errors = <SourceIssue>[];
    final warnings = <SourceIssue>[];

    String raw;
    try {
      raw = await manifestFile.readAsString();
    } catch (_) {
      return const SourceImportResult(errors: [SourceIssue('invalidJson')]);
    }

    SourceManifest manifest;
    try {
      manifest = SourceManifest.fromJsonString(raw);
    } on FormatException catch (e) {
      return SourceImportResult(errors: [SourceIssue('invalidJson', e.message)]);
    }

    final fieldErrors = manifest.validate();
    for (final field in fieldErrors) {
      if (field == 'path') {
        errors.add(const SourceIssue('path'));
      } else {
        errors.add(SourceIssue('field', field));
      }
    }
    if (errors.isNotEmpty) return SourceImportResult(errors: errors);

    final packageDir = manifestFile.parent;
    final sourceFile = File('${packageDir.path}/${manifest.sourceFile}');
    if (!await sourceFile.exists()) {
      return const SourceImportResult(errors: [SourceIssue('sourceMissing')]);
    }
    final jsFile = sourceFile;
    final length = await jsFile.length();
    if (length > maxJsBytes) {
      return SourceImportResult(errors: [const SourceIssue('tooLarge'), SourceIssue('fileSize', '$length')]);
    }

    String js;
    try {
      js = await jsFile.readAsString();
    } catch (_) {
      return const SourceImportResult(errors: [SourceIssue('sourceMissing')]);
    }

    final entryPattern = RegExp(
      'class\\s+${RegExp.escape(manifest.entryClass)}\\s+extends\\s+SourceBase\\b',
      multiLine: true,
    );
    if (!entryPattern.hasMatch(js)) {
      errors.add(SourceIssue('entryClass', manifest.entryClass));
    }

    final capabilities = detectCapabilities(js);
    if (!capabilities.contains('loadComicInfo')) {
      errors.add(SourceIssue('capabilityMissing', 'loadComicInfo'));
    }
    for (final optional in [
      'explore',
      'categories',
      'category',
      'search',
      'loadComicPages',
      'getImageLoadingConfig',
      'init',
    ]) {
      if (!capabilities.contains(optional)) warnings.add(SourceIssue('capabilityOptional', optional));
    }

    if (manifest.icon != null && !await File('${packageDir.path}/${manifest.icon}').exists()) {
      warnings.add(const SourceIssue('iconMissing'));
    }
    if (errors.isNotEmpty) return SourceImportResult(errors: errors, warnings: warnings);

    final installedDir = await _copyPackage(packageDir, manifest, jsFile);
    if (installedDir == null) warnings.add(const SourceIssue('persistFailed'));

    return SourceImportResult(
      source: OnlineSource(manifest: manifest, capabilities: capabilities, importedAt: DateTime.now()),
      warnings: warnings,
    );
  }

  Future<Directory?> _copyPackage(Directory packageDir, SourceManifest manifest, File sourceFile) async {
    final root = onlineStateDirectory();
    if (root == null) return null;
    try {
      final target = Directory('${root.path}/sources/${manifest.id}');
      if (await target.exists()) await target.delete(recursive: true);
      await target.create(recursive: true);
      await File('${target.path}/source.json').writeAsString(manifest.toJsonString(), flush: true);
      await File('${target.path}/${manifest.sourceFile}').writeAsBytes(await sourceFile.readAsBytes(), flush: true);
      final icon = manifest.icon;
      if (icon != null) {
        final iconFile = File('${packageDir.path}/$icon');
        if (await iconFile.exists()) {
          await File('${target.path}/$icon').writeAsBytes(await iconFile.readAsBytes(), flush: true);
        }
      }
      return target;
    } catch (_) {
      return null;
    }
  }

  /// 导出源包到用户选择的目录：`<dir>/<id>/` 下写 json + js + icon。
  ///
  /// 没有源目录的 demo 源生成一份契约完整的 stub `source.js`，便于分享后
  /// 仍能通过字段校验（实际能力由对方的引擎执行）。
  Future<Directory?> exportSource(OnlineSource source, String targetRoot) async {
    try {
      final root = onlineStateDirectory();
      final stored = root == null ? null : Directory('${root.path}/sources/${source.id}');
      final target = Directory('$targetRoot/${source.id}');
      await target.create(recursive: true);
      await File('${target.path}/source.json').writeAsString(source.manifest.toJsonString(), flush: true);
      final storedJs = stored == null ? null : File('${stored.path}/${source.manifest.sourceFile}');
      if (storedJs != null && await storedJs.exists()) {
        await File('${target.path}/${source.manifest.sourceFile}')
            .writeAsBytes(await storedJs.readAsBytes(), flush: true);
      } else {
        await File('${target.path}/${source.manifest.sourceFile}').writeAsString(_stubScript(source), flush: true);
      }
      final iconName = source.manifest.icon;
      if (iconName != null && stored != null) {
        final icon = File('${stored.path}/$iconName');
        if (await icon.exists()) {
          await File('${target.path}/$iconName').writeAsBytes(await icon.readAsBytes(), flush: true);
        }
      }
      return target;
    } catch (_) {
      return null;
    }
  }

  String _stubScript(OnlineSource source) =>
      '''
class ${source.manifest.entryClass} extends SourceBase {
  name = ${_jsString(source.manifest.name)};
  key = ${_jsString(source.manifest.id)};
  version = ${_jsString(source.manifest.version)};

  async explore(ctx) { return { sections: [] }; }
  async categories() { return []; }
  async category(ctx) { return { items: [], page: ctx.page || 1, hasMore: false }; }
  async search(ctx) { return { items: [], page: ctx.page || 1, hasMore: false }; }
  async loadComicInfo(ctx) { return { id: ctx.id, title: '', chapters: [] }; }
  async loadComicPages(ctx) { return []; }
  async getImageLoadingConfig(ctx) { return {}; }
  async init() {}
}
''';

  String _jsString(String value) => "'${value.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";

  /// 在系统文件管理器中打开源目录。
  Future<bool> openDirectory(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      } else {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 源目录（用于「打开源目录」；demo 源没有目录时返回 null）。
  String? sourceDirectoryOf(String sourceId) {
    final root = onlineStateDirectory();
    if (root == null) return null;
    final dir = Directory('${root.path}/sources/$sourceId');
    return dir.existsSync() ? dir.path : null;
  }
}
