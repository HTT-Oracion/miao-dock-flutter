import '../../domain/music_models.dart';
import '../api/migu_api.dart';
import 'music_source.dart';

/// 咪咕音源（`miao-dock/src-tauri/src/music/migu.rs` 的 Dart 版）。
class MiguSource implements MusicSource {
  MiguSource({MiguApi? api}) : _api = api ?? MiguApi();

  final MiguApi _api;

  @override
  MusicPlatform get platform => MusicPlatform.migu;

  @override
  bool get supportsDailySongs => false;

  @override
  bool get supportsComments => false;

  @override
  bool get supportsRecommendPlaylists => true;

  @override
  bool get supportsSimilarSongs => false;

  @override
  Future<List<MusicSong>> searchSongs(String keywords, {int limit = 30, int offset = 0}) =>
      _api.searchSongs(keywords, limit: limit, offset: offset);

  @override
  Future<List<MusicPlaylist>> searchPlaylists(String keywords, {int limit = 12}) async => const [];

  @override
  Future<List<MusicPlaylist>> recommendedPlaylists({int limit = 6}) => _api.recommendedPlaylists(limit: limit);

  @override
  Future<List<MusicPlaylist>> userPlaylists() => _api.userPlaylists();

  @override
  Future<List<({String id, String name, String updateMeta, String? coverUrl})>> charts() async => const [
    (id: MiguApi.rankHot, name: '', updateMeta: '', coverUrl: null),
    (id: MiguApi.rankNew, name: '', updateMeta: '', coverUrl: null),
    (id: MiguApi.rankOriginal, name: '', updateMeta: '', coverUrl: null),
  ];

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(String id) => _api.playlistDetail(id);

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> chartDetail(String id) => _api.rankDetail(id);

  @override
  Future<List<MusicSong>> dailySongs() async => const [];

  @override
  Future<List<MusicSong>> similarSongs(MusicSong seed, {int limit = 20}) async => const [];

  @override
  Future<List<MusicComment>> comments(String songId, {int limit = 20, int offset = 0}) async => const [];

  @override
  Future<SongLyrics> lyrics(MusicSong song) => _api.lyric(song.mediaId ?? song.id, copyrightId: song.id);

  @override
  Future<String?> songUrl(MusicSong song, QualityTier quality) =>
      _api.songUrl(song.mediaId ?? song.id, copyrightId: song.id, quality: quality);
}
