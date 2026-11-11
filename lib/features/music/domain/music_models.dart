import 'package:flutter/widgets.dart';

/// 音乐模块领域模型（design/music/ver1.0 `assets/data.js` 的 Dart 对应物）。
///
/// 数据全部来自 [DemoMusicRepository]（A 级 Fake，D-201）；字段与设计稿
/// 演示数据一一对应，真实音源接入时只换 repository，模型不动。

/// 音乐平台来源。`local` 为本机文件，无平台品牌。
enum MusicPlatform { netease, kugou, qq, migu, local }

/// 播放模式（设计稿 5 档循环：列表循环 → 单曲循环 → 随机 → 顺序 → 心动）。
enum PlayMode { list, one, shuffle, order, heartbeat }

/// 播放器样式 6 种（设计稿 `.skin` 弹层，只换氛围层不动布局）。
enum PlayerStyle { modern, cover, vinyl, spectrum, immersive, glass }

/// 音质档位（设计稿 `.quality`：标准 → 超清母带，含码率与会员标注）。
enum QualityTier {
  standard(128, null),
  high(320, null),
  lossless(1411, false),
  hires(1999, false),
  master(-1, true); // 母带级，码率不标注

  const QualityTier(this.kbps, this.svipRequired);
  final int kbps;

  /// null = 免费；false = 会员；true = SVIP（设计稿 qualities 表）。
  final bool? svipRequired;
}

/// 详情页数据源类型：歌单 / 官方榜单 / 每日推荐（共用一套详情布局）。
enum MusicSourceKind { playlist, chart, daily }

/// 单曲（曲名 / 艺人 / 专辑 / 时长 / 来源 / 音质标注）。
@immutable
class MusicSong {
  const MusicSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.platform,
    this.qualityLabel,
    this.mediaId,
    this.coverUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final MusicPlatform platform;

  /// 行内音质角标文案（如「无损」「320K」）；null = 不显示。
  final String? qualityLabel;

  /// 平台播放所需的第二个标识（QQ 的 media_mid / 咪咕的 contentId）。
  /// 网易云 / 酷狗为空；null = 与 [id] 相同（各客户端自行兜底）。
  final String? mediaId;

  /// 真实封面 URL（第三方接口给的图）。null / 空 = 走设计稿的 seed 渐变封面。
  final String? coverUrl;

  MusicSong copyWith({String? qualityLabel, String? mediaId, String? coverUrl}) => MusicSong(
    id: id,
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    platform: platform,
    qualityLabel: qualityLabel ?? this.qualityLabel,
    mediaId: mediaId ?? this.mediaId,
    coverUrl: coverUrl ?? this.coverUrl,
  );
}

/// 歌单 / 专辑瓦片（封面渐变由 [seed] 决定，播放量文案直接落数）。
@immutable
class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.seed,
    this.playCount,
    this.description,
    this.special = false,
    this.author,
    this.subscribed = false,
  });

  final String id;
  final String name;
  final int trackCount;
  final String seed;
  final String? playCount;

  /// 一句话说明（瓦片副行 / 详情 hero）。
  final String? description;

  /// 「我喜欢的音乐」：心动模式唯一合法队列来源（设计稿 N10/N24）。
  final bool special;

  /// 创建者昵称（我的歌单库卡片副行 / 详情来源行，设计稿 N41/N43）。
  final String? author;

  /// 收藏语义位（对齐 miao-dock `Playlist.subscribed`）：
  /// `true` = 别人的歌单（「收藏的歌单」分组，详情默认已收藏）；
  /// `false` = 自己创建（「创建的歌单」分组）。
  final bool subscribed;

  MusicPlaylist copyWith({bool? special, String? author, bool? subscribed}) => MusicPlaylist(
    id: id,
    name: name,
    trackCount: trackCount,
    seed: seed,
    playCount: playCount,
    description: description,
    special: special ?? this.special,
    author: author ?? this.author,
    subscribed: subscribed ?? this.subscribed,
  );

  MusicPlaylist copyWithSpecial(bool value) => copyWith(special: value);
}

/// 官方榜单卡 Top3 行（设计稿 N38：序号 / 歌名 – 歌手 / 趋势标记）。
enum ChartTrend { up, newEntry, flat }

@immutable
class ChartTopEntry {
  const ChartTopEntry({required this.title, required this.artist, required this.trend});

  final String title;
  final String artist;
  final ChartTrend trend;
}

/// 官方榜单卡（榜单名 + 更新时间 + 叠层封面 + Top3）。
@immutable
class MusicChart {
  const MusicChart({
    required this.id,
    required this.name,
    required this.updateMeta,
    required this.seed,
    required this.top,
  });

  final String id;
  final String name;

  /// 「刚刚更新 / 每周四更新 / 每 30 分钟更新」等原文。
  final String updateMeta;
  final String seed;
  final List<ChartTopEntry> top;
}

/// 发现页推荐栏竖卡（插画底 + 标题 + 彩色说明带，点卡整组播放）。
@immutable
class MusicRecCard {
  const MusicRecCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.seed,
    required this.icon,
    required this.songIds,
    this.playlistId,
    this.hue,
  });

  final String id;
  final String title;
  final String subtitle;

  /// 说明带底色（设计稿 recs[].tint）。
  final Color tint;
  final String seed;
  final IconData icon;

  /// 整组播放的曲目 id 序列（演示数据直接给定；真实音源为空，改为按 [playlistId] 拉详情）。
  final List<String> songIds;

  /// 真实音源的歌单 id；null = 演示卡（用 [songIds] 直接播）。
  final String? playlistId;

  /// 封面色相（设计稿 `coverBg(seed).h`）。演示数据直接存色相，避免把
  /// 带中文的 seed 字符串写进数据层（D-006 棘轮：数据层也不新增中文）。
  final int? hue;
}

/// 歌曲 / 歌单评论（播放器「评论」页签，设计稿 N20）。
@immutable
class MusicComment {
  const MusicComment({
    required this.id,
    required this.nick,
    required this.content,
    required this.time,
    required this.likes,
    required this.hot,
  });

  final String id;
  final String nick;
  final String content;
  final String time;
  final int likes;
  final bool hot;
}

/// 播放历史条目（按今天 / 昨天 / 更早分组，设计稿 N26）。
@immutable
class MusicHistoryEntry {
  const MusicHistoryEntry({required this.song, required this.playedAt});

  final MusicSong song;
  final DateTime playedAt;
}

/// 逐句歌词行（t = 起唱毫秒；翻译轨可选，设计稿 N18/M05「译」开关）。
@immutable
class LyricLine {
  const LyricLine({required this.t, required this.text, this.translation});

  final int t;
  final String text;
  final String? translation;
}

/// 一首歌的歌词（原文 + 翻译轨 + 逐句时间轴）。
@immutable
class SongLyrics {
  const SongLyrics({required this.lines, this.hasTranslation = false});

  final List<LyricLine> lines;
  final bool hasTranslation;
}

/// 平台品牌（扁平圆底 logo 用：稍浅纯色 + 符号类型，无渐变无高光 —— 设计稿 N40）。
enum BrandGlyph { noteCloud, letterK, note, letterM }

@immutable
class PlatformBrand {
  const PlatformBrand({required this.label, required this.color, required this.glyph});

  final String label;
  final Color color;
  final BrandGlyph glyph;
}

/// 平台品牌表（色值对齐设计稿 icons.js `PLAT_BRANDS` 最终稿：圆底稍浅纯色）。
const Map<MusicPlatform, PlatformBrand> platformBrands = {
  MusicPlatform.netease: PlatformBrand(label: '网易云', color: Color(0xFFE06058), glyph: BrandGlyph.noteCloud),
  MusicPlatform.kugou: PlatformBrand(label: '酷狗', color: Color(0xFF4FA3F0), glyph: BrandGlyph.letterK),
  MusicPlatform.qq: PlatformBrand(label: 'QQ 音乐', color: Color(0xFF3FBF72), glyph: BrandGlyph.note),
  MusicPlatform.migu: PlatformBrand(label: '咪咕', color: Color(0xFFF0668E), glyph: BrandGlyph.letterM),
};

/// 「我喜欢的音乐」封面渐变（设计稿 `.lk-cover`：`linear-gradient(140deg,#C2553F,#7A2C26)`）。
///
/// 属**内容色**（封面图），与 [platformBrands] 同口径放在领域层：
/// 不随深浅主题变化，所以不做成 `AppPalette` 字段。
const List<Color> likedCoverColors = [Color(0xFFC2553F), Color(0xFF7A2C26)];

/// 时长展示（mm:ss；表格与播放条共用同一口径）。
String formatSongDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${d.inHours > 0 ? '${d.inHours}:$m' : m}:$s';
}

/// 封面渐变（app.css `.mp-cov`：`linear-gradient(140deg, acc, #6B4423)`；
/// 榜单 / 歌单瓦片按 seed 换 hue，颜色属于内容不随主题变化）。
List<Color> seedCoverColors(String seed) {
  // 与设计稿 coverBg() 同一 FNV-1a 哈希；此处只取两层渐变色供氛围层 / 推荐卡底使用。
  var hash = 0;
  var h32 = 2166136261;
  for (final c in seed.codeUnits) {
    h32 = ((h32 ^ c) * 16777619) & 0xFFFFFFFF;
  }
  hash = h32 >= 0x80000000 ? h32 - 0x100000000 : h32;
  final h = hash.abs() % 360;
  final h2 = (h + 38) % 360;
  final base = HSLColor.fromAHSL(1, h.toDouble(), 0.48, 0.36).toColor();
  final deep = HSLColor.fromAHSL(1, h2.toDouble(), 0.44, 0.24).toColor();
  return [base, deep];
}
