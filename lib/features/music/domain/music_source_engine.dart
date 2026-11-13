import 'music_login_info.dart';
import 'music_models.dart';
import 'js_music_source.dart';

/// JS 音乐源引擎接口。
///
/// 生产实现是 QuickJS（`js/quickjs_music_source_engine.dart`）；测试注入
/// Fake。上层（适配器 / 仓库）只依赖本接口。
///
/// 返回类型直接复用 Dart 侧 `MusicSource` 接口的既有形状（含记录类型），
/// 适配器不需要做二次翻译。
abstract interface class MusicSourceEngine {
  /// 源加载（清单里的 `init` 能力在这里执行一次）。
  Future<void> ensureLoaded(JsMusicSource source);

  /// 注入会话 Cookie（WebView 登录落盘的那串），引擎写入源域名的 Cookie 罐。
  Future<void> setSessionCookie(JsMusicSource source, String cookie);

  Future<List<MusicSong>> searchSongs(JsMusicSource source, {required String keyword, int limit, int offset});

  Future<List<MusicPlaylist>> searchPlaylists(JsMusicSource source, {required String keyword, int limit});

  Future<List<MusicChart>> charts(JsMusicSource source);

  Future<({MusicPlaylist meta, List<MusicSong> songs})> chartDetail(JsMusicSource source, {required String id});

  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(JsMusicSource source, {required String id});

  Future<SongLyrics> lyrics(JsMusicSource source, {required MusicSong song});

  Future<String?> songUrl(JsMusicSource source, {required MusicSong song, required QualityTier quality});

  /// 以下为**能力位方法**：源没实现对应能力时调用方必须先查 `capabilities`。

  Future<List<MusicSong>> dailySongs(JsMusicSource source);

  Future<List<MusicComment>> comments(JsMusicSource source, {required String songId, int limit, int offset});

  /// 账户信息（昵称回读 / 登录态校验）。源未声明 `loginInfo` 能力时返回 null。
  ///
  /// 返回 [MusicLoginInfo.loggedIn] = false 表示 Cookie 已失效（调用方据此撤登录态）。
  Future<MusicLoginInfo?> loginInfo(JsMusicSource source);

  Future<List<MusicPlaylist>> userPlaylists(JsMusicSource source);

  Future<void> unload(String sourceId);

  Future<void> dispose();
}
