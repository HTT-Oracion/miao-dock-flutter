import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../domain/music_models.dart';
import '../../../domain/music_source_engine.dart';
import 'music_source_import.dart';

/// 开发期端到端探针：从外部源目录（`--dart-define=MIAO_MUSIC_SOURCES_DIR`）导入 →
/// 真实搜索 / 播放地址。
///
/// 应用**不再内置**任何 JS 源（assets/online/sources 已移除）；探针只在提供了
/// 源目录的 debug 运行中生效，结果落 `/tmp/music_source_probe.log` 供自动化读取。
/// 探针失败不影响应用启动。
Future<void> runMusicSourceProbe(MusicSourceEngine engine) async {
  final buffer = StringBuffer();
  void report(String label, Object detail) {
    final line = '[$label] $detail';
    debugPrint('[music.source.probe] $line');
    buffer.writeln(line);
  }

  const dirPath = String.fromEnvironment('MIAO_MUSIC_SOURCES_DIR');
  if (dirPath.isEmpty) {
    report('skip', 'MIAO_MUSIC_SOURCES_DIR not set');
    return;
  }
  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    report('skip', 'dir missing: $dirPath');
    return;
  }

  try {
    final importer = MusicSourceImporter();
    final jsFiles = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.js')).toList();
    report('dir', '${dir.path} js=${jsFiles.length}');
    for (final f in jsFiles) {
      final result = await importer.importScript(await f.readAsString(), fileName: f.uri.pathSegments.last);
      report(
        '${f.uri.pathSegments.last}.import',
        result.ok ? 'ok id=${result.source!.id} caps=${result.source!.capabilities.length}' : 'failed ${result.errors}',
      );
    }

    final catalogFile = File('${dir.path}/index.json');
    if (catalogFile.existsSync()) {
      report('catalog', 'present (${catalogFile.lengthSync()} bytes)');
    }

    // 逐源验证：加载 → 搜索 → songUrl（VIP 遍历降级）→ 歌词 → 榜单。
    for (final source in importer.installedSources()) {
      try {
        await engine.ensureLoaded(source);
        final songs = await engine.searchSongs(source, keyword: '周杰伦', limit: 5);
        report('${source.id}.search', '${songs.length} songs');
        for (final s in songs.take(2)) {
          report('${source.id}.hit', '${s.id} ${s.title} - ${s.artist} (${s.duration.inMilliseconds}ms)');
        }
        if (songs.isNotEmpty) {
          // VIP 歌未登录拿不到播放地址：遍历到第一首可播的歌为止。
          String? url;
          MusicSong? playable;
          for (final song in songs) {
            url = await engine.songUrl(source, song: song, quality: QualityTier.standard);
            if (url != null) {
              playable = song;
              break;
            }
          }
          report(
            '${source.id}.songUrl',
            url == null
                ? 'null (all vip / needs login)'
                : 'ok song=${playable!.id} head=${url.substring(0, url.length.clamp(0, 60))}',
          );
          final lyrics = await engine.lyrics(source, song: songs.first);
          report('${source.id}.lyrics', '${lyrics.lines.length} lines translation=${lyrics.hasTranslation}');
        }
        final charts = await engine.charts(source);
        report('${source.id}.charts', '${charts.length} charts first=${charts.isEmpty ? '-' : charts.first.name}');
      } catch (e) {
        report('${source.id}.error', '$e');
      }
    }
  } catch (e, st) {
    report('error', '$e\n$st');
  } finally {
    try {
      final file = File('${Directory.systemTemp.path}/music_source_probe.log');
      await file.writeAsString(buffer.toString(), flush: true);
      debugPrint('[music.source.probe] log file=${file.path}');
    } catch (_) {}
  }
}
