import 'dart:io';

import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';
import 'package:miao_dock_flutter/features/music/domain/js_music_source.dart';
import 'package:miao_dock_flutter/features/music/domain/music_source_manifest.dart';

/// 注册表替身：固定源清单（不走磁盘），供无 QuickJS 的测试注入。
class StubRegistry extends JsMusicSourceRegistry {
  StubRegistry(this.sources);

  final List<JsMusicSource> sources;

  @override
  List<JsMusicSource> build() => sources;
}

/// 按外部仓库 JS 构建网易云源（真实清单推导）。
JsMusicSource neteaseSourceFromRepo() {
  final js = File('../miao-dock-sources/music/netease.js').readAsStringSync();
  final (manifest, issues) = manifestFromScript(js, 'netease.js');
  assert(issues.isEmpty, '$issues');
  return JsMusicSource(manifest: manifest!, capabilities: {'searchSongs', 'loginInfo'});
}

/// 哔哩哔哩源（清单内联，用于新平台 / 排序用例）。
JsMusicSource bilibiliSourceFromJs() {
  final (manifest, issues) = manifestFromScript(
    "class S extends MusicSourceBase {\n  name = '哔哩哔哩';\n  platform = 'bilibili';\n"
        "  key = 'bilibili';\n  version = '1.0.0';\n  baseUrl = 'https://www.bilibili.com';\n"
        "  logo = 'https://www.bilibili.com/favicon.ico';\n  color = '#FB7299';\n}",
    'bilibili.js',
  );
  assert(issues.isEmpty, '$issues');
  return JsMusicSource(manifest: manifest!, capabilities: {'searchSongs'});
}
