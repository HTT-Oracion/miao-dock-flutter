// 从原项目清单生成 Dart 常量（避免运行时依赖外部文件 / 打包丢失）。
//
// 用法：dart run tool/gen_engine_manifests.dart <原项目 engine 目录>
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final src = args.isEmpty ? '../miao-dock/engine' : args.first;
  final out = StringBuffer()
    ..writeln('// 生成物，勿手改：dart run tool/gen_engine_manifests.dart')
    ..writeln('// 来源：miao-dock/engine/{runtime,models}.manifest.json')
    ..writeln("import 'engine_manifest_entry.dart';")
    ..writeln()
    ..writeln('/// 运行时清单（python / 源码 / llama）。')
    ..writeln('const List<EngineManifestEntry> kRuntimeManifest = [');

  void emit(String path) {
    final d = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    for (final e in (d['files'] as List).cast<Map<String, dynamic>>()) {
      final sources = (e['sources'] as List?)?.cast<String>() ?? const <String>[];
      out.writeln('  EngineManifestEntry(');
      out.writeln("    id: '${e['id']}',");
      out.writeln("    set: '${e['set'] ?? ''}',");
      if (e['platform'] != null) out.writeln("    platform: '${e['platform']}',");
      out.writeln("    url: '${e['url'] ?? (sources.isEmpty ? '' : sources.first)}',");
      if (sources.isNotEmpty) out.writeln("    sources: ${jsonEncode(sources).replaceAll('"', "'")},");
      out.writeln("    dest: '${e['dest']}',");
      if (e['sha256'] != null) out.writeln("    sha256: '${e['sha256']}',");
      if (e['sizeBytes'] != null) out.writeln('    sizeBytes: ${e['sizeBytes']},');
      if (e['extractTo'] != null) out.writeln("    extractTo: '${e['extractTo']}',");
      if (e['extractStrip'] != null) out.writeln('    extractStrip: ${e['extractStrip']},');
      if (e['stage'] != null) out.writeln('    stage: ${e['stage']},');
      out.writeln('  ),');
    }
  }

  emit('$src/runtime.manifest.json');
  out
    ..writeln('];')
    ..writeln()
    ..writeln('/// 模型清单（视觉栈 / LLM / 可选 nllb）。')
    ..writeln('const List<EngineManifestEntry> kModelManifest = [');
  emit('$src/models.manifest.json');
  out.writeln('];');

  final target = File('services/mangasvc/lib/src/engine/engine_manifests.dart');
  target.writeAsStringSync(out.toString());
  stdout.writeln('written: ${target.path} (${out.length} chars)');
}
