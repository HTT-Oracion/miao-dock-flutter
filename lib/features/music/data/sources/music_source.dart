import '../../domain/music_models.dart';

/// 单个音乐平台的**能力接口**（四平台实现的公共面）。
///
/// 为什么单独一层：UI 只认识 [MusicRepository]，仓库按当前音源选一个 [MusicSource]；
/// 平台差异（哪些接口有、ID 字段叫什么）只在本层表达，不在 UI 里散落 if。
///
/// 能力矩阵与 `miao-dock/src/modules/music/platform.ts` 的 `PLATFORM_CAPS` 对齐：
/// 每日推荐仅网易云、评论仅网易云、歌单推荐网易云 / 咪咕 / QQ。
abstract interface class MusicSource {
  /// 平台 id（字符串身份；内置四平台 = netease/kugou/qq/migu）。
  String get platformId;

  /// 是否具备某能力（UI 据此隐藏入口，而不是给一个点了没反应的按钮）。
  bool get supportsDailySongs;
  bool get supportsComments;
  bool get supportsRecommendPlaylists;
  bool get supportsSimilarSongs;

  Future<List<MusicSong>> searchSongs(String keywords, {int limit, int offset});

  Future<List<MusicPlaylist>> searchPlaylists(String keywords, {int limit});

  /// 发现页「推荐歌单」；平台无此能力时返回空列表（由仓库回退到榜单或搜索热词）。
  Future<List<MusicPlaylist>> recommendedPlaylists({int limit});

  /// 我的歌单库（系统歌单 + 创建 + 收藏）。需登录；未登录返回空集
  /// （平台能力位是「需要账号」，UI 走登录 CTA 而不是空态，N41）。
  Future<List<MusicPlaylist>> userPlaylists();

  /// 榜单清单（id 为平台原始 id）。
  Future<List<({String id, String name, String updateMeta, String? coverUrl})>> charts();

  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(String id);

  Future<({MusicPlaylist meta, List<MusicSong> songs})> chartDetail(String id);

  /// 每日推荐（仅网易云；其余平台抛 [UnsupportedError] 由仓库兜底）。
  Future<List<MusicSong>> dailySongs();

  /// 按种子歌曲取相似歌曲；不支持的平台返回空列表。
  Future<List<MusicSong>> similarSongs(MusicSong seed, {int limit});

  Future<List<MusicComment>> comments(String songId, {int limit, int offset});

  Future<SongLyrics> lyrics(MusicSong song);

  /// 播放地址；null = 平台明确无版权 / 需登录 / 需会员。
  Future<String?> songUrl(MusicSong song, QualityTier quality);
}
