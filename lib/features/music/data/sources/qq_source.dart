import '../../domain/music_models.dart';
import '../api/qqmusic_api.dart';
import 'music_source.dart';

/// QQ 音乐音源（`miao-dock/src-tauri/src/music/qqmusic.rs` 的 Dart 版）。
class QqSource implements MusicSource {
  QqSource({QqMusicApi? api}) : _api = api ?? QqMusicApi();

  final QqMusicApi _api;

  @override
  MusicPlatform get platform => MusicPlatform.qq;

  @override
  bool get supportsDailySongs => false;

  @override
  bool get supportsComments => false;

  @override
  bool get supportsRecommendPlaylists => true;

  @override
  Future<List<MusicSong>> searchSongs(String keywords, {int limit = 30, int offset = 0}) =>
      _api.searchSongs(keywords, limit: limit, offset: offset);

  @override
  Future<List<MusicPlaylist>> searchPlaylists(String keywords, {int limit = 12}) =>
      _api.searchPlaylists(keywords, limit: limit);

  @override
  Future<List<MusicPlaylist>> recommendedPlaylists({int limit = 6}) async {
    // 搜索接口按「最热」排序即可当推荐用（上游同样没有匿名推荐歌单接口）。
    final list = await _api.searchPlaylists('', limit: limit);
    return list.take(limit).toList();
  }

  @override
  Future<List<MusicPlaylist>> userPlaylists() => _api.userPlaylists();

  @override
  Future<List<({String id, String name, String updateMeta})>> charts() async {
    return [for (final r in QqMusicApi.rankList) (id: r.id, name: r.name, updateMeta: '')];
  }

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(String id) => _api.playlistDetail(id);

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> chartDetail(String id) => _api.chartDetail(id);

  @override
  Future<List<MusicSong>> dailySongs() async => const [];

  @override
  Future<List<MusicComment>> comments(String songId, {int limit = 20, int offset = 0}) async => const [];

  @override
  Future<SongLyrics> lyrics(MusicSong song) => _api.lyric(mid: song.id, id: song.id);

  @override
  Future<String?> songUrl(MusicSong song, QualityTier quality) =>
      _api.songUrl(song.id, mediaMid: song.mediaId ?? '', quality: quality);
}
