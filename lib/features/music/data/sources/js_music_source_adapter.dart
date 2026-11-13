import '../../data/sources/music_source.dart';
import '../../domain/music_models.dart';
import '../../domain/js_music_source.dart';
import '../../domain/music_source_engine.dart';

/// JS 音乐源 → Dart [MusicSource] 适配器。
///
/// 仓库层（PlatformMusicRepository）只认识 [MusicSource]；适配器让 JS 源
/// 与内置四平台实现在同一接口下互换 —— UI 与播放链路零改动。
class JsMusicSourceAdapter implements MusicSource {
  JsMusicSourceAdapter({required this.source, required this.engine, this.cookie = ''});

  final JsMusicSource source;
  final MusicSourceEngine engine;

  /// 会话 Cookie（WebView 登录落盘的那串）；null = 未登录。
  String? cookie;

  @override
  String get platformId => source.platformId;

  @override
  bool get supportsDailySongs => source.capabilities.contains('dailySongs');

  @override
  bool get supportsComments => source.capabilities.contains('comments');

  @override
  bool get supportsRecommendPlaylists =>
      source.capabilities.contains('charts') || source.capabilities.contains('searchPlaylists');

  @override
  bool get supportsSimilarSongs => false;

  @override
  Future<List<MusicSong>> searchSongs(String keywords, {int limit = 30, int offset = 0}) =>
      engine.searchSongs(source, keyword: keywords, limit: limit, offset: offset);

  @override
  Future<List<MusicPlaylist>> searchPlaylists(String keywords, {int limit = 12}) =>
      engine.searchPlaylists(source, keyword: keywords, limit: limit);

  @override
  Future<List<MusicPlaylist>> recommendedPlaylists({int limit = 6}) =>
      engine.recommendedPlaylists(source, limit: limit);

  @override
  Future<List<MusicPlaylist>> userPlaylists() async {
    if (cookie == null || cookie!.isEmpty) return const [];
    await engine.setSessionCookie(source, cookie!);
    return engine.userPlaylists(source);
  }

  @override
  Future<List<({String id, String name, String updateMeta, String? coverUrl})>> charts() async {
    final charts = await engine.charts(source);
    return [for (final c in charts) (id: c.id, name: c.name, updateMeta: c.updateMeta, coverUrl: c.coverUrl)];
  }

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(String id) =>
      engine.playlistDetail(source, id: id);

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> chartDetail(String id) => engine.chartDetail(source, id: id);

  @override
  Future<List<MusicSong>> dailySongs() => engine.dailySongs(source);

  @override
  Future<List<MusicSong>> similarSongs(MusicSong seed, {int limit = 20}) async => const [];

  @override
  Future<List<MusicComment>> comments(String songId, {int limit = 20, int offset = 0}) =>
      engine.comments(source, songId: songId, limit: limit, offset: offset);

  @override
  Future<SongLyrics> lyrics(MusicSong song) => engine.lyrics(source, song: song);

  @override
  Future<String?> songUrl(MusicSong song, QualityTier quality) => engine.songUrl(source, song: song, quality: quality);
}
