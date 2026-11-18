import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/data/sources/js_music_source_adapter.dart';
import 'package:miao_dock_flutter/features/music/domain/js_music_source.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';
import 'package:miao_dock_flutter/features/music/domain/music_source_manifest.dart';

import '../../support/stub_engine.dart';

/// 适配器把会话 Cookie 注入引擎：miao-dock 的 Rust 实现是每个命令显式传 cookie，
/// JS 源只能靠引擎 Cookie 罐 / getSessionCookie() 拿登录态。
///
/// 破坏点：只在 userPlaylists 注入 → 重启恢复后酷狗 songUrl / QQ 网关拿不到票据，
/// 「已登录」但播放仍是未登录行为（登录态等于没保存）。
void main() {
  JsMusicSource source() {
    final (manifest, issues) = manifestFromScript(
      "class S extends MusicSourceBase {\n  name = '酷狗';\n  platform = 'kugou';\n  key = 'kugou';\n"
          "  version = '1.0.0';\n  baseUrl = 'https://www.kugou.com';\n"
          "  async searchSongs(args) { return { songs: [] }; }\n"
          "  async songUrl(args) { return { url: null }; }\n}",
      'kugou.js',
    );
    expect(issues, isEmpty, reason: '$issues');
    return JsMusicSource(manifest: manifest!, capabilities: {'searchSongs'});
  }

  test('登录态存在时，任意能力调用前都注入会话 Cookie（且只注入一次）', () async {
    final engine = StubMusicSourceEngine();
    final adapter = JsMusicSourceAdapter(source: source(), engine: engine, cookie: 'token=t; userid=7');

    await adapter.searchSongs('周杰伦');
    expect(engine.injectedCookie, 'token=t; userid=7');

    await adapter.songUrl(
      const MusicSong(id: 'h', title: 'x', artist: '', album: '', duration: Duration.zero, platformId: 'kugou'),
      QualityTier.high,
    );
    // 破坏点：只在 userPlaylists 注入 → 这里 songUrl 前拿不到 Cookie。
    expect(engine.injectedCookie, 'token=t; userid=7');
  });

  test('未登录（cookie 为空）不注入；Cookie 变化后重新注入', () async {
    final engine = StubMusicSourceEngine();
    final adapter = JsMusicSourceAdapter(source: source(), engine: engine);

    await adapter.searchSongs('x');
    expect(engine.injectedCookie, isNull);

    adapter.cookie = 'token=a';
    await adapter.searchSongs('x');
    expect(engine.injectedCookie, 'token=a');

    // 重新登录换了 Cookie：下一次调用必须用新值（否则继续用旧票据）。
    adapter.cookie = 'token=b';
    await adapter.searchSongs('x');
    expect(engine.injectedCookie, 'token=b');
  });
}
