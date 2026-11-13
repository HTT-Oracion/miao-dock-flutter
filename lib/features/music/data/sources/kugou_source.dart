import '../../domain/music_models.dart';
import '../api/kugou_api.dart';
import 'music_source.dart';

/// 酷狗音源（`miao-dock/src-tauri/src/music/kugou.rs` 的 Dart 版）。
class KugouSource implements MusicSource {
  KugouSource({KugouApi? api}) : _api = api ?? KugouApi();

  final KugouApi _api;

  @override
  String get platformId => 'kugou';

  @override
  bool get supportsDailySongs => false;

  @override
  bool get supportsComments => false;

  @override
  bool get supportsRecommendPlaylists => false;

  @override
  bool get supportsSimilarSongs => false;

  @override
  Future<List<MusicSong>> searchSongs(String keywords, {int limit = 20, int offset = 0}) =>
      _api.searchSongs(keywords, limit: limit, offset: offset);

  @override
  Future<List<MusicPlaylist>> searchPlaylists(String keywords, {int limit = 12}) =>
      _api.searchPlaylists(keywords, limit: limit);

  /// 酷狗无匿名推荐歌单接口：用榜单清单顶替（设计稿只要求「推荐歌单」区有内容）。
  @override
  Future<List<MusicPlaylist>> recommendedPlaylists({int limit = 6}) async {
    final list = await _api.rankList(limit: limit);
    return list.take(limit).toList();
  }

  @override
  Future<List<MusicPlaylist>> userPlaylists() => _api.userPlaylists();

  @override
  Future<List<({String id, String name, String updateMeta, String? coverUrl})>> charts() async {
    final list = await _api.rankList(limit: 6);
    return [for (final r in list) (id: r.id, name: r.name, updateMeta: r.description ?? '', coverUrl: r.coverUrl)];
  }

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
  Future<SongLyrics> lyrics(MusicSong song) => _api.lyric(hash: song.id, durationSec: song.duration.inSeconds);

  @override
  Future<String?> songUrl(MusicSong song, QualityTier quality) =>
      _api.songUrl(song.id, albumId: '', albumAudioId: song.mediaId ?? '');
}
