import '../../data/sources/music_source.dart';
import '../../domain/music_models.dart';
import '../../domain/js_music_source.dart';
import '../../domain/music_source_engine.dart';

/// JS 音乐源 → Dart [MusicSource] 适配器。
///
/// 仓库层（PlatformMusicRepository）只认识 [MusicSource]；适配器让 JS 源
/// 与内置四平台实现在同一接口下互换 —— UI 与播放链路零改动。
///
/// 🔴 每次调用前都会把会话 Cookie 注入引擎（[_ensureSession]）：miao-dock 的
/// Rust 实现是**每个命令显式传 cookie**，而 JS 源只能靠引擎的 Cookie 罐 /
/// `getSessionCookie()` 拿登录态。此前只在 `userPlaylists` 与昵称回读时注入，
/// 重启恢复后「已登录但酷狗播放/QQ 网关拿不到票据」—— 登录态等于没保存。
class JsMusicSourceAdapter implements MusicSource {
  JsMusicSourceAdapter({required this.source, required this.engine, this.cookie = ''});

  final JsMusicSource source;
  final MusicSourceEngine engine;

  /// 会话 Cookie（WebView 登录落盘的那串）；null / 空串 = 未登录。
  String? cookie;

  /// 已注入引擎的 Cookie（避免每次调用都走一遍宿主桥）。
  String? _injectedCookie;

  @override
  String get platformId => source.platformId;

  @override
  bool get supportsDailySongs => source.capabilities.contains('dailySongs');

  @override
  bool get supportsComments => source.capabilities.contains('comments');

  @override
  bool get supportsRecommendPlaylists =>
      source.capabilities.contains('charts') || source.capabilities.contains('searchPlaylists');

  /// 心动模式能力位：源声明了 `similarSongs` 才可用（对齐 miao-dock
  /// `platform.supportsSimilar`，不硬编码平台名单）。
  @override
  bool get supportsSimilarSongs => source.capabilities.contains('similarSongs');

  /// 把会话 Cookie 注入引擎（只在值变化时注入；未登录直接跳过）。
  Future<void> _ensureSession() async {
    final value = cookie;
    if (value == null || value.isEmpty || value == _injectedCookie) return;
    await engine.setSessionCookie(source, value);
    _injectedCookie = value;
  }

  @override
  Future<List<MusicSong>> searchSongs(String keywords, {int limit = 30, int offset = 0}) async {
    await _ensureSession();
    return engine.searchSongs(source, keyword: keywords, limit: limit, offset: offset);
  }

  @override
  Future<List<MusicPlaylist>> searchPlaylists(String keywords, {int limit = 12}) async {
    await _ensureSession();
    return engine.searchPlaylists(source, keyword: keywords, limit: limit);
  }

  @override
  Future<List<MusicPlaylist>> recommendedPlaylists({int limit = 6}) async {
    await _ensureSession();
    return engine.recommendedPlaylists(source, limit: limit);
  }

  @override
  Future<List<MusicPlaylist>> userPlaylists() async {
    if (cookie == null || cookie!.isEmpty) return const [];
    await _ensureSession();
    return engine.userPlaylists(source);
  }

  @override
  Future<List<({String id, String name, String updateMeta, String? coverUrl})>> charts() async {
    await _ensureSession();
    final charts = await engine.charts(source);
    return [for (final c in charts) (id: c.id, name: c.name, updateMeta: c.updateMeta, coverUrl: c.coverUrl)];
  }

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(String id) async {
    await _ensureSession();
    return engine.playlistDetail(source, id: id);
  }

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> chartDetail(String id) async {
    await _ensureSession();
    return engine.chartDetail(source, id: id);
  }

  @override
  Future<List<MusicSong>> dailySongs() async {
    await _ensureSession();
    return engine.dailySongs(source);
  }

  @override
  Future<List<MusicSong>> similarSongs(MusicSong seed, {int limit = 20}) async => const [];

  @override
  Future<List<MusicComment>> comments(String songId, {int limit = 20, int offset = 0}) async {
    await _ensureSession();
    return engine.comments(source, songId: songId, limit: limit, offset: offset);
  }

  @override
  Future<SongLyrics> lyrics(MusicSong song) async {
    await _ensureSession();
    return engine.lyrics(source, song: song);
  }

  @override
  Future<String?> songUrl(MusicSong song, QualityTier quality) async {
    await _ensureSession();
    return engine.songUrl(source, song: song, quality: quality);
  }
}
