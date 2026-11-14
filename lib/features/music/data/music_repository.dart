import '../domain/music_models.dart';

/// 音乐数据仓库抽象（D-201）。
///
/// UI / controller 只面向本接口；运行时实现连接当前选择的真实音乐平台。
abstract interface class MusicRepository {
  /// 心动模式能力位（= 当前源是否提供相似歌曲）。
  ///
  /// UI 的心动档、播放器的 `canUseHeartbeat` 都只认这一个来源（对齐 miao-dock
  /// `platform.supportsSimilar`）—— 判据分散会「按钮显示心动、实际按随机播」。
  bool get supportsSimilarSongs;

  /// 发现页推荐栏（9 张竖卡）。
  Future<List<MusicRecCard>> recCards();

  /// 推荐歌单瓦片（6 个，含播放量角标）。
  Future<List<MusicPlaylist>> recommendedPlaylists();

  /// 官方榜单卡（6 张，含 Top3 与更新时间）。
  Future<List<MusicChart>> charts();

  /// 每日推荐歌曲（未登录由 session 层拦截出 CTA，仓库层不做登录判断）。
  Future<List<MusicSong>> dailySongs();

  /// 详情数据（歌单 / 榜单 / 每日推荐共用详情布局）。
  Future<({MusicPlaylist meta, List<MusicSong> songs})> sourceDetail(MusicSourceKind kind, String id);

  /// 搜索：单曲分组 + 歌单分组（设计稿 N06）。
  Future<({List<MusicSong> songs, List<MusicPlaylist> playlists})> search(String keyword);

  /// 歌词同步读（演示仓库 / 已缓存的真实音源）；未命中返回空时间轴，不阻塞构建。
  SongLyrics lyricsFor(MusicSong song);

  /// 歌词异步取（真实音源必须走这里，结果回填 [lyricsFor] 的缓存）。
  Future<SongLyrics> loadLyrics(MusicSong song);

  /// 当前音质下的真实播放地址；null 表示平台明确不可播放。
  Future<String?> resolvePlayUrl(MusicSong song, QualityTier quality);

  /// 评论（播放器「评论」页签，N20）。
  Future<List<MusicComment>> comments(String songId);

  /// 播放历史（应用启动时灌入内存态；新增条目由播放器追加）。
  Future<List<MusicHistoryEntry>> history();

  /// 本地音乐（设计稿「本地」视图；文件导入走系统选择器后交给本层登记）。
  Future<List<MusicSong>> localTracks();

  /// 「我喜欢的音乐」歌单曲目（心动模式合法队列来源）。
  Future<MusicPlaylist> likedPlaylist();

  /// 以当前歌曲为种子生成心动模式队列；仅网易云有真实接口。
  Future<List<MusicSong>> similarSongs(MusicSong seed, {int limit = 20});

  /// 我的歌单库（设计稿 N41/N43）：系统歌单（`special`）+ 自己创建 + 收藏的歌单。
  ///
  /// 返回顺序即分组顺序，`subscribed` 语义位由数据层给出，UI 不靠下标猜。
  /// 未登录由 UI 拦截（不落空态），平台无此能力返回空列表（不是故障）。
  Future<List<MusicPlaylist>> userPlaylists();

  /// 故障注入（A 级 Fake 自检通道）：指定 scope 的后续读取抛 [MusicRepositoryException]。
  void setFailScope(FailScope scope, bool on);

  /// 清空全部故障注入，回到演示初始态。
  void resetFailScopes();
}

/// 仓库层错误（错误码走 UI 层 ARB 映射，不透传 message，AGENTS §3）。
enum MusicRepositoryErrorCode { network, loginRequired, notFound }

class MusicRepositoryException implements Exception {
  const MusicRepositoryException(this.code, {this.cause});
  final MusicRepositoryErrorCode code;
  final Object? cause;
}

/// 故障注入范围（与视图一一对应，另有「全部」）。
enum FailScope { recs, playlists, charts, daily, search, comments, history, local, all }
