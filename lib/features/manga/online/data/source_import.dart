import 'dart:io';
import 'dart:typed_data';

import '../../../../core/storage/shell_prefs.dart';
import '../../../../shared/domain/source_library.dart';
import '../domain/online_models.dart';
import '../domain/online_source.dart';
import '../domain/source_manifest.dart';
import 'legacy_source_manifest.dart';
import 'source_package.dart';

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

/// 本地仓库（`index.json`）单条导入结果：带上仓库条目里的显示信息，
/// 便于批量导入后按「哪个源失败」汇报。
class SourceCatalogEntryImport {
  const SourceCatalogEntryImport({required this.key, required this.name, required this.result});

  final String key;
  final String name;
  final SourceImportResult result;

  bool get ok => result.ok;
}

/// `source.json` 包导入器：字段校验 → 入口类/能力检查 → 写入源目录。
///
/// 本地文件、远程链接最终都调用 [installPackage]，保证两条入口的校验与落盘
/// 完全一致。符号链接/路径穿越在清单校验阶段拒绝。
class SourceImporter {
  SourceImporter({
    this.maxJsBytes = 2 * 1024 * 1024,
    this.maxIconBytes = 512 * 1024,
    Directory? Function()? rootResolver,
  }) : _rootResolver = rootResolver ?? onlineStateDirectory;

  final int maxJsBytes;
  final int maxIconBytes;

  /// 源包落盘根解析器（测试注入临时目录，避免污染测试进程共享目录）。
  final Directory? Function() _rootResolver;

  Future<SourceImportResult> importManifest(String manifestPath) async {
    final manifestFile = File(manifestPath);
    if (!await manifestFile.exists()) {
      return const SourceImportResult(errors: [SourceIssue('invalidJson')]);
    }
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
    final packageDir = manifestFile.parent;
    final sourceFile = File('${packageDir.path}/${manifest.sourceFile}');
    if (!await sourceFile.exists()) {
      return const SourceImportResult(errors: [SourceIssue('sourceMissing')]);
    }
    String js;
    try {
      js = await sourceFile.readAsString();
    } catch (_) {
      return const SourceImportResult(errors: [SourceIssue('sourceMissing')]);
    }
    List<int>? icon;
    final iconName = manifest.icon;
    if (iconName != null) {
      try {
        final file = File('${packageDir.path}/$iconName');
        if (await file.exists()) icon = await file.readAsBytes();
      } catch (_) {}
    }
    return installPackage(
      SourcePackageData(manifest: manifest, js: js, icon: icon == null ? null : Uint8List.fromList(icon)),
    );
  }

  /// 读取本地源仓库（`index.json`）并解析条目（**只解析、不安装**）。
  ///
  /// 本地仓库的条目按 `file://` 相对解析 —— 与链接导入的仓库同一套字段
  /// （`key` / `name` / `version` / `fileName`），只是基址是本地文件路径。
  Future<SourceCatalog> loadLocalCatalog(String catalogPath) async {
    final file = File(catalogPath);
    final raw = await file.readAsString();
    // 用绝对 file URI 作基址：相对路径在 Uri.resolve 下会退化成相对地址，
    // 条目会被 isValidSourceUrl/file 校验过滤掉（测试里传相对路径时踩过）。
    return parseSourceCatalog(raw, file.absolute.uri.toString(), allowLocalFile: true);
  }

  /// 安装本地仓库中的一条源：裸 `.js`（上游 `ComicSource` 脚本）或 `source.json` 包。
  ///
  /// 本地仓库里两种形态共存：音乐源仓库是裸 JS，漫画源仓库同样是裸 JS；
  /// 旧式导出包则是 `source.json + source.js` 目录。
  Future<SourceImportResult> importCatalogEntry(SourceCatalogEntry entry) async {
    final uri = Uri.tryParse(entry.manifestUrl);
    if (uri == null || !uri.isScheme('file')) {
      return const SourceImportResult(errors: [SourceIssue('catalogEntryMissing')]);
    }
    final String path;
    try {
      path = uri.toFilePath();
    } catch (_) {
      return const SourceImportResult(errors: [SourceIssue('catalogEntryMissing')]);
    }
    if (!path.toLowerCase().endsWith('.js')) return importManifest(path);
    String js;
    try {
      js = await File(path).readAsString();
    } catch (_) {
      return const SourceImportResult(errors: [SourceIssue('catalogEntryMissing')]);
    }
    SourceManifest manifest;
    try {
      manifest = legacyManifestFromScript(
        js,
        scriptUri: uri,
        catalogKey: entry.key,
        catalogName: entry.name,
        catalogVersion: entry.version,
        catalogDescription: entry.description,
      );
    } on FormatException {
      // 例如仓库里混入了非 ComicSource 脚本（_venera_ 依赖等）。
      return const SourceImportResult(errors: [SourceIssue('notComicSource')]);
    }
    return installPackage(SourcePackageData(manifest: manifest, js: js, sourceUrl: entry.manifestUrl));
  }

  /// 统一安装入口：File 与 URL 都走这里。
  Future<SourceImportResult> installPackage(SourcePackageData package) async {
    final manifest = package.manifest;
    final errors = <SourceIssue>[];
    final warnings = <SourceIssue>[];
    for (final field in manifest.validate()) {
      errors.add(field == 'path' ? const SourceIssue('path') : SourceIssue('field', field));
    }
    if (errors.isNotEmpty) return SourceImportResult(errors: errors);
    if (package.js.length > maxJsBytes) {
      return const SourceImportResult(errors: [SourceIssue('tooLarge')]);
    }
    final extendsBase = manifest.runtime == SourceRuntime.comicSource ? 'ComicSource' : 'SourceBase';
    final entryPattern = RegExp(
      'class\\s+${RegExp.escape(manifest.entryClass)}\\s+extends\\s+$extendsBase\\b',
      multiLine: true,
    );
    if (!entryPattern.hasMatch(package.js)) {
      errors.add(SourceIssue('entryClass', manifest.entryClass));
    }
    final capabilities = manifest.runtime == SourceRuntime.comicSource
        ? {
            'explore',
            'categories',
            'category',
            'search',
            'loadComicInfo',
            'loadComicPages',
            'getImageLoadingConfig',
            'init',
            if (manifest.hasRank) 'rank',
          }
        : detectCapabilities(package.js);
    if (!capabilities.contains('loadComicInfo')) {
      errors.add(const SourceIssue('capabilityMissing', 'loadComicInfo'));
    }
    if (manifest.runtime == SourceRuntime.contract) {
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
    }
    final icon = package.icon;
    if (manifest.icon != null && icon == null) warnings.add(const SourceIssue('iconMissing'));
    if (icon != null && icon.length > maxIconBytes) warnings.add(const SourceIssue('iconTooLarge'));
    if (errors.isNotEmpty) return SourceImportResult(errors: errors, warnings: warnings);

    final installed = await _writePackage(package);
    if (!installed) {
      errors.add(const SourceIssue('persistFailed'));
      return SourceImportResult(errors: errors, warnings: warnings);
    }
    return SourceImportResult(
      source: OnlineSource(
        manifest: manifest,
        capabilities: capabilities,
        importedAt: DateTime.now(),
        sourceUrl: package.sourceUrl,
        libraryId: package.libraryId,
      ),
      warnings: warnings,
    );
  }

  Future<bool> _writePackage(SourcePackageData package) async {
    final root = _rootResolver();
    if (root == null) return false;
    final manifest = package.manifest;
    try {
      final target = Directory('${root.path}/sources/${manifest.id}');
      if (await target.exists()) await target.delete(recursive: true);
      await target.create(recursive: true);
      await File('${target.path}/source.json').writeAsString(manifest.toJsonString(), flush: true);
      await File('${target.path}/${manifest.sourceFile}').writeAsString(package.js, flush: true);
      final icon = package.icon;
      if (icon != null && manifest.icon != null) {
        await File('${target.path}/${manifest.icon}').writeAsBytes(icon, flush: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> removePackage(String sourceId) async {
    final root = _rootResolver();
    if (root == null) return;
    final dir = Directory('${root.path}/sources/$sourceId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// 导出源包到用户选择的目录：`<dir>/<id>/` 下写 json + js + icon。
  Future<Directory?> exportSource(OnlineSource source, String targetRoot) async {
    try {
      final root = _rootResolver();
      final stored = root == null ? null : Directory('${root.path}/sources/${source.id}');
      final storedJs = stored == null ? null : File('${stored.path}/${source.manifest.sourceFile}');
      if (storedJs == null || !await storedJs.exists()) return null;
      final target = Directory('$targetRoot/${source.id}');
      await target.create(recursive: true);
      await File('${target.path}/source.json').writeAsString(source.manifest.toJsonString(), flush: true);
      await File('${target.path}/${source.manifest.sourceFile}')
          .writeAsBytes(await storedJs.readAsBytes(), flush: true);
      final iconName = source.manifest.icon;
      if (iconName != null) {
        final icon = File('${stored?.path}/$iconName');
        if (await icon.exists()) {
          await File('${target.path}/$iconName').writeAsBytes(await icon.readAsBytes(), flush: true);
        }
      }
      return target;
    } catch (_) {
      return null;
    }
  }

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

  String? sourceDirectoryOf(String sourceId) {
    final root = _rootResolver();
    if (root == null) return null;
    final dir = Directory('${root.path}/sources/$sourceId');
    return dir.existsSync() ? dir.path : null;
  }
}
