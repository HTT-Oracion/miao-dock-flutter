import '../../domain/music_models.dart';
import '../api/netease_api.dart';
import 'music_source.dart';

/// 网易云音源（`miao-dock/src-tauri/src/music/netease.rs` 的 Dart 版）。
class NeteaseSource implements MusicSource {
  NeteaseSource({NeteaseApi? api}) : _api = api ?? NeteaseApi();

  final NeteaseApi _api;

  @override
  String get platformId => 'netease';

  @override
  bool get supportsDailySongs => true;

  @override
  bool get supportsComments => true;

  @override
  bool get supportsRecommendPlaylists => true;

  @override
  bool get supportsSimilarSongs => true;

  @override
  Future<List<MusicSong>> searchSongs(String keywords, {int limit = 30, int offset = 0}) =>
      _api.searchSongs(keywords, limit: limit, offset: offset);

  @override
  Future<List<MusicPlaylist>> searchPlaylists(String keywords, {int limit = 12}) =>
      _api.searchPlaylists(keywords, limit: limit);

  @override
  Future<List<MusicPlaylist>> recommendedPlaylists({int limit = 6}) => _api.personalizedPlaylists(limit: limit);

  @override
  Future<List<MusicPlaylist>> userPlaylists() => _api.userPlaylists();

  @override
  Future<List<({String id, String name, String updateMeta, String? coverUrl})>> charts() async {
    final list = await _api.toplists();
    return [for (final c in list) (id: c.id, name: c.name, updateMeta: c.updateMeta, coverUrl: c.cover)];
  }

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(String id) => _api.playlistDetail(id);

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> chartDetail(String id) => _api.playlistDetail(id);

  @override
  Future<List<MusicSong>> dailySongs() => _api.newSongs(limit: 6);

  @override
  Future<List<MusicSong>> similarSongs(MusicSong seed, {int limit = 20}) => _api.similarSongs(seed.id, limit: limit);

  @override
  Future<List<MusicComment>> comments(String songId, {int limit = 20, int offset = 0}) =>
      _api.comments(songId, limit: limit, offset: offset);

  @override
  Future<SongLyrics> lyrics(MusicSong song) => _api.lyric(song.id);

  @override
  Future<String?> songUrl(MusicSong song, QualityTier quality) => _api.songUrl(song.id, quality);
}
