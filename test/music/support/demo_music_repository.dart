import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/features/music/data/music_repository.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';

/// A 级 Fake 音乐仓库（D-201）：逐条对齐 `design/music/ver1.0/assets/data.js`。
///
/// 🔴 本文件是**数据层**（`data/` 不在 l10n 硬编码中文扫描范围，见
/// `test/l10n_test.dart` 扫描口径）——曲名 / 歌手 / 评论是设计稿的演示内容，
/// 属数据不是 UI 文案；UI 层文案一律走 ARB。
///
/// 故障注入（[setFailScope]）只服务于状态自检（加载 / 失败 / 局部失败截图与测试），
/// 不参与任何正常业务分支。
class DemoMusicRepository implements MusicRepository {
  final Set<FailScope> _fails = {};

  static const Map<FailScope, Set<FailScope>> _scopeMatch = {
    FailScope.recs: {FailScope.recs, FailScope.all},
    FailScope.playlists: {FailScope.playlists, FailScope.all},
    FailScope.charts: {FailScope.charts, FailScope.all},
    FailScope.daily: {FailScope.daily, FailScope.all},
    FailScope.search: {FailScope.search, FailScope.all},
    FailScope.comments: {FailScope.comments, FailScope.all},
    FailScope.history: {FailScope.history, FailScope.all},
    FailScope.local: {FailScope.local, FailScope.all},
  };

  void _guard(FailScope scope) {
    if (_scopeMatch[scope]!.any(_fails.contains)) {
      throw const MusicRepositoryException(MusicRepositoryErrorCode.network);
    }
  }

  @override
  void setFailScope(FailScope scope, bool on) => on ? _fails.add(scope) : _fails.remove(scope);

  @override
  void resetFailScopes() => _fails.clear();

  // ── 曲目（data.js songs s1–s12）───────────────────────────────────────────
  static const _songs = <MusicSong>[
    MusicSong(
      id: 's1',
      title: '夜に駆ける',
      artist: 'YOASOBI',
      album: 'THE BOOK',
      duration: Duration(seconds: 250),
      platformId: 'netease',
      qualityLabel: '无损',
    ),
    MusicSong(
      id: 's2',
      title: '晴天',
      artist: '周杰伦',
      album: '叶惠美',
      duration: Duration(seconds: 269),
      platformId: 'netease',
      qualityLabel: '320K',
    ),
    MusicSong(
      id: 's3',
      title: '起风了',
      artist: '买辣椒也用券',
      album: '起风了',
      duration: Duration(seconds: 313),
      platformId: 'qq',
      qualityLabel: '无损',
    ),
    MusicSong(
      id: 's4',
      title: '光年之外',
      artist: '邓紫棋',
      album: '光年之外',
      duration: Duration(seconds: 235),
      platformId: 'netease',
      qualityLabel: '320K',
    ),
    MusicSong(
      id: 's5',
      title: '平凡之路',
      artist: '朴树',
      album: '猎户星座',
      duration: Duration(seconds: 301),
      platformId: 'kugou',
      qualityLabel: '无损',
    ),
    MusicSong(
      id: 's6',
      title: '稻香',
      artist: '周杰伦',
      album: '魔杰座',
      duration: Duration(seconds: 222),
      platformId: 'netease',
      qualityLabel: '320K',
    ),
    MusicSong(
      id: 's7',
      title: 'Lemon',
      artist: '米津玄師',
      album: 'Lemon',
      duration: Duration(seconds: 256),
      platformId: 'kugou',
      qualityLabel: '无损',
    ),
    MusicSong(
      id: 's8',
      title: '打上花火',
      artist: 'DAOKO × 米津玄師',
      album: '打上花火',
      duration: Duration(seconds: 291),
      platformId: 'netease',
      qualityLabel: '320K',
    ),
    MusicSong(
      id: 's9',
      title: '花に亡霊',
      artist: 'ヨルシカ',
      album: '盗作',
      duration: Duration(seconds: 240),
      platformId: 'netease',
      qualityLabel: '无损',
    ),
    MusicSong(
      id: 's10',
      title: '海阔天空',
      artist: 'Beyond',
      album: '乐与怒',
      duration: Duration(seconds: 325),
      platformId: 'migu',
      qualityLabel: '无损',
    ),
    MusicSong(
      id: 's11',
      title: '反方向的钟',
      artist: '周杰伦',
      album: '范特西',
      duration: Duration(seconds: 256),
      platformId: 'netease',
      qualityLabel: '320K',
    ),
    MusicSong(
      id: 's12',
      title: '孤勇者',
      artist: '陈奕迅',
      album: '孤勇者',
      duration: Duration(seconds: 256),
      platformId: 'qq',
      qualityLabel: '无损',
    ),
  ];

  MusicSong songById(String id) => _songs.firstWhere((s) => s.id == id, orElse: () => _songs.first);
  List<MusicSong> songsByIds(List<String> ids) => [for (final id in ids) songById(id)];

  // ── 推荐栏（data.js recs r0–r8）───────────────────────────────────────────
  static const _tints = [
    Color(0xFFB08446),
    Color(0xFFB23B2C),
    Color(0xFF7C8490),
    Color(0xFF4E545C),
    Color(0xFFB07A3A),
    Color(0xFF4A5A78),
    Color(0xFF6D7B63),
    Color(0xFF3F5A72),
    Color(0xFF8A5B42),
  ];

  @override
  Future<List<MusicRecCard>> recCards() async {
    _guard(FailScope.recs);
    const icons = [
      LucideIcons.calendarDays,
      LucideIcons.compass,
      LucideIcons.radio,
      LucideIcons.waves,
      LucideIcons.sparkles,
      LucideIcons.moon,
      LucideIcons.music2,
      LucideIcons.headphones,
      LucideIcons.mic,
    ];
    const data = <(String, String, String, int, List<String>)>[
      ('r0', '每日推荐', '每日推荐 | 从「都落」听起', 191, ['s1', 's4', 's7', 's2']),
      ('r1', '私人漫游', '从「equal」开启无限漫游', 253, ['s9', 's11', 's3', 's12']),
      ('r2', '私人雷达', '今天从《tomorrow》听起', 136, ['s7', 's8', 's9', 's1']),
      ('r3', '华语流行日推', '第三个吻痕、泡泡、海底', 174, ['s2', 's6', 's11', 's12']),
      ('r4', '心灵共鸣', '感受着远方的心跳', 355, ['s3', 's5', 's10', 's4']),
      ('r5', '深夜电台', '给还没睡的人，留一盏灯', 194, ['s9', 's4', 's8', 's6']),
      ('r6', '古典晨间', '一杯咖啡时间的钢琴与弦乐', 120, ['s10', 's3', 's5', 's12']),
      ('r7', '城市夜行', '末班地铁后的城市', 210, ['s11', 's2', 's7', 's9']),
      ('r8', '粤语精选', '从《海阔天空》开始', 24, ['s10', 's12', 's6', 's2']),
    ];
    return [
      for (final (i, (id, title, subtitle, hue, ids)) in data.indexed)
        MusicRecCard(
          id: id,
          title: title,
          subtitle: subtitle,
          tint: _tints[i],
          seed: id,
          hue: hue,
          icon: icons[i],
          songIds: ids,
        ),
    ];
  }

  // ── 歌单（data.js playlists p0–p8）────────────────────────────────────────
  static const _playlists = <MusicPlaylist>[
    MusicPlaylist(
      id: 'p0',
      name: '我喜欢的音乐',
      trackCount: 46,
      playCountValue: 12000,
      description: '收藏过的歌都在这里',
      coverUrl: 'https://example.test/liked-cover.jpg',
      seed: 'fav',
      special: true,
    ),
    MusicPlaylist(
      id: 'p1',
      name: '日语小甜歌 | 听完想谈恋爱系列',
      trackCount: 24,
      playCountValue: 233000,
      description: '地铁两站刚好一曲',
      seed: 'pl-1',
      author: '云中漫步信箱',
    ),
    MusicPlaylist(
      id: 'p2',
      name: '个人向 Galgame 主题曲集合',
      trackCount: 31,
      playCountValue: 6910000,
      description: '无歌词，纯循环',
      seed: 'pl-2',
      author: '云中漫步信箱',
    ),
    MusicPlaylist(
      id: 'p3',
      name: '日系告白 | 能否让我成为你的太阳',
      trackCount: 48,
      playCountValue: 493000,
      description: '本周新增 6 首',
      seed: 'pl-3',
      author: '云中漫步信箱',
    ),
    MusicPlaylist(
      id: 'p4',
      name: '『日系』二次元 & ACG 精选歌曲',
      trackCount: 12,
      playCountValue: 1227000,
      description: '雨声 · 空调声 · 键盘声',
      seed: 'pl-4',
      author: '云中漫步信箱',
    ),
    MusicPlaylist(
      id: 'p5',
      name: 'CLANNAD 心动神曲',
      trackCount: 36,
      playCountValue: 1287000,
      description: '2000–2010 华语',
      seed: 'pl-5',
      author: '云中漫步信箱',
    ),
    MusicPlaylist(
      id: 'p6',
      name: '【ACG】愿你有一天能和你最重要的人相遇',
      trackCount: 19,
      playCountValue: 18919,
      description: '本周编辑精选',
      seed: 'pl-6',
      author: '云中漫步信箱',
    ),
    MusicPlaylist(
      id: 'p7',
      name: '影视原声收藏',
      trackCount: 27,
      playCountValue: 84000,
      description: '动画 / 日剧 / 电影',
      seed: 'pl-7',
      author: '云中漫步信箱',
    ),
    MusicPlaylist(
      id: 'p8',
      name: '睡眠冥想',
      trackCount: 9,
      playCountValue: 31000,
      description: '30 分钟后自动停止',
      seed: 'pl-8',
      author: '云中漫步信箱',
    ),
    // 收藏的歌单（设计稿 N43：data.js playlists 末尾 sub:true 的 4 条，作者不是当前账号）。
    // 追加在数组末尾，发现页「推荐歌单」取前 6 条时不会混入这批别人的歌单。
    MusicPlaylist(
      id: 'c1',
      name: '华语 City Pop | 夜色霓虹漫游',
      trackCount: 38,
      playCountValue: 762000,
      description: '复古合成器与潮湿的街',
      seed: 'sub-1',
      author: '城市漫游者',
      subscribed: true,
    ),
    MusicPlaylist(
      id: 'c2',
      name: '游戏 OST 钢琴改编精选',
      trackCount: 22,
      playCountValue: 318000,
      description: '存档点前的那一段旋律',
      seed: 'sub-2',
      author: '星轨邮差',
      subscribed: true,
    ),
    MusicPlaylist(
      id: 'c3',
      name: '通勤路上の J-Pop 2010s',
      trackCount: 56,
      playCountValue: 2080000,
      description: '两站地铁刚好两首',
      seed: 'sub-3',
      author: '木漏れ日',
      subscribed: true,
    ),
    MusicPlaylist(
      id: 'c4',
      name: 'Lo-fi 学习用 · 雨天白噪音',
      trackCount: 17,
      playCountValue: 96000,
      description: '专注 45 分钟不打断',
      seed: 'sub-4',
      author: '打烊之后',
      subscribed: true,
    ),
  ];

  /// 歌单首曲偏移（data.js `playlists[].pick`）：决定详情页第一首从哪首歌起。
  /// 不按数组下标推：下标只是排列顺序，pick 才是设计稿给的内容口径。
  static const _playlistPick = <String, int>{
    'p0': 0,
    'p1': 0,
    'p2': 3,
    'p3': 1,
    'p4': 7,
    'p5': 4,
    'p6': 8,
    'p7': 6,
    'p8': 9,
    'c1': 2,
    'c2': 5,
    'c3': 7,
    'c4': 10,
  };

  /// 歌单 → 曲目组装（演示口径：从 pick 起循环取 10 首）。
  List<MusicSong> _playlistSongs(String id) {
    final offset = _playlistPick[id] ?? 0;
    return [for (var i = 0; i < 10; i++) _songs[(offset + i) % _songs.length]];
  }

  @override
  Future<List<MusicPlaylist>> recommendedPlaylists() async {
    _guard(FailScope.playlists);
    // 推荐歌单固定 6 个 = p0–p5（设计稿发现页 `DATA.playlists.slice(0,6)`）。
    // p0 同时是红心歌单（心动模式唯一合法来源，N10/N24），不能因归组而移出首屏。
    return _playlists.sublist(0, 6);
  }

  @override
  Future<MusicPlaylist> likedPlaylist() async => _playlistSongsOf('p0');

  /// 我的歌单库：p0 系统歌单置顶 + p1–p8 创建 + c1–c4 收藏（设计稿 N41/N43）。
  @override
  Future<List<MusicPlaylist>> userPlaylists() async {
    _guard(FailScope.playlists);
    return _playlists;
  }

  MusicPlaylist _playlistSongsOf(String id) => _playlists.firstWhere((p) => p.id == id);

  // ── 官方榜单（data.js charts c1–c6）───────────────────────────────────────
  static const _charts = <MusicChart>[
    MusicChart(
      id: 'c1',
      name: '飙升榜',
      updateMeta: '刚刚更新',
      seed: 'chart-rising',
      top: [
        ChartTopEntry(title: '烂奇迹', artist: '不小心惹了上帝', trend: ChartTrend.up),
        ChartTopEntry(title: '特效药', artist: '江辰', trend: ChartTrend.newEntry),
        ChartTopEntry(title: '爱而不得 (Live)', artist: '薛之谦 / 黄龄', trend: ChartTrend.up),
      ],
    ),
    MusicChart(
      id: 'c2',
      name: '新歌榜',
      updateMeta: '刚刚更新',
      seed: 'chart-new',
      top: [
        ChartTopEntry(title: 'Hong Kong', artist: 'feat. 王菲季候风', trend: ChartTrend.flat),
        ChartTopEntry(title: '茉茉', artist: 'Nzwin 黄跃成', trend: ChartTrend.flat),
        ChartTopEntry(title: '无意', artist: '加木 / Demxntia', trend: ChartTrend.flat),
      ],
    ),
    MusicChart(
      id: 'c3',
      name: '热歌榜',
      updateMeta: '更新 22 首',
      seed: 'chart-hot',
      top: [
        ChartTopEntry(title: 'Hong Kong', artist: 'feat. 王菲季候风', trend: ChartTrend.flat),
        ChartTopEntry(title: '海屿你', artist: '马也_Crabbit', trend: ChartTrend.up),
        ChartTopEntry(title: '如果呢', artist: '郑润泽', trend: ChartTrend.up),
      ],
    ),
    MusicChart(
      id: 'c4',
      name: '原创榜',
      updateMeta: '每周四更新',
      seed: 'chart-original',
      top: [
        ChartTopEntry(title: '最重要的听众', artist: '法老 / 冷风', trend: ChartTrend.newEntry),
        ChartTopEntry(title: '无意', artist: '加木 / Demxntia', trend: ChartTrend.newEntry),
        ChartTopEntry(title: '罗马议事会', artist: 'THE FORUM', trend: ChartTrend.newEntry),
      ],
    ),
    MusicChart(
      id: 'c5',
      name: '数字专辑畅销榜',
      updateMeta: '每 30 分钟更新',
      seed: 'chart-digital',
      top: [
        ChartTopEntry(title: '二十七 (27)', artist: '宋雨琦', trend: ChartTrend.flat),
        ChartTopEntry(title: '希忘 Hope', artist: '华晨宇', trend: ChartTrend.flat),
        ChartTopEntry(title: '冀西南林路行', artist: '万能青年旅店', trend: ChartTrend.flat),
      ],
    ),
    MusicChart(
      id: 'c6',
      name: '歌曲畅销指数榜',
      updateMeta: '每 1 小时更新',
      seed: 'chart-sales',
      top: [
        ChartTopEntry(title: '天龙八部之宿敌', artist: '许嵩', trend: ChartTrend.flat),
        ChartTopEntry(title: 'Call your name <Gv>', artist: '澤野弘之', trend: ChartTrend.flat),
        ChartTopEntry(title: '无梦镇', artist: '魏晨', trend: ChartTrend.flat),
      ],
    ),
  ];

  @override
  Future<List<MusicChart>> charts() async {
    _guard(FailScope.charts);
    return _charts;
  }

  // ── 每日推荐（设计稿「推荐歌曲」4 行起，登录后可见）─────────────────────────
  @override
  Future<List<MusicSong>> dailySongs() async {
    _guard(FailScope.daily);
    return songsByIds(['s1', 's4', 's7', 's2', 's9', 's11']);
  }

  // ── 详情（歌单 / 榜单 / 每日推荐）──────────────────────────────────────────
  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> sourceDetail(MusicSourceKind kind, String id) async {
    switch (kind) {
      case MusicSourceKind.playlist:
        _guard(FailScope.playlists);
        // 未知 id 回落第一张歌单，但曲目仍按请求 id 组装会错位 —— 统一用回落后的 id。
        final meta = _playlists.firstWhere((p) => p.id == id, orElse: () => _playlists.first);
        return (meta: meta, songs: _playlistSongs(meta.id));
      case MusicSourceKind.chart:
        _guard(FailScope.charts);
        final chart = _charts.firstWhere((c) => c.id == id, orElse: () => _charts.first);
        final meta = MusicPlaylist(
          id: chart.id,
          name: chart.name,
          trackCount: 30,
          seed: chart.seed,
          description: chart.updateMeta,
        );
        return (meta: meta, songs: songsByIds(['s12', 's3', 's1', 's7', 's4', 's9', 's5', 's10']));
      case MusicSourceKind.daily:
        _guard(FailScope.daily);
        final meta = MusicPlaylist(
          id: 'daily',
          name: '每日推荐',
          trackCount: 6,
          seed: 'daily',
          special: true,
          description: '按你的口味每天换一份',
        );
        return (meta: meta, songs: await dailySongs());
    }
  }

  // ── 搜索（分组返回：单曲 / 歌单，N06）──────────────────────────────────────

  /// 空关键词时的「最近搜索」演示词（设计稿 N06；内容属演示数据，非 UI 文案）。
  static const recentSearches = <String>['夜に駆ける', '周杰伦', '深夜写代码', 'Lemon'];

  @override
  Future<({List<MusicSong> songs, List<MusicPlaylist> playlists})> search(String keyword) async {
    _guard(FailScope.search);
    if (keyword.trim().isEmpty) {
      return (songs: <MusicSong>[], playlists: <MusicPlaylist>[]);
    }
    final k = keyword.trim().toLowerCase();
    final songs = _songs.where((s) => '${s.title}${s.artist}${s.album}'.toLowerCase().contains(k)).toList();
    final playlists = _playlists.where((p) => p.name.toLowerCase().contains(k)).toList();
    return (songs: songs, playlists: playlists);
  }

  @override
  Future<List<MusicSong>> similarSongs(MusicSong seed, {int limit = 20}) async =>
      _songs.where((song) => song.id != seed.id).take(limit).toList(growable: false);

  // ── 歌词（s1 为设计稿逐句数据；其余生成简单时间轴）──────────────────────────
  static const _yozoraLyrics = <(int, String, String)>[
    (0, '沈むように溶けてゆくように', '缓缓下沉，仿佛消融一般'),
    (16000, '二人だけの空が広がる夜', '只属于两人的夜空铺展开'),
    (33000, '「さよなら」だけだった', '一句「再见」之后再无别话'),
    (49000, 'その一言で全てが分かった', '那一句话 让我明白了一切'),
    (66000, '日が沈み出した空と星々', '日落的天空与满天星辰'),
    (82000, '切ないほど澄み渡る青い液みたい', '澄澈得令人心颤的蓝'),
    (99000, '駆けて行った 君と二人分の夜を', '奔跑而过 与你共赴两人的夜'),
    (116000, '夜の匂いとすれ違う', '与夜的气息擦肩而过'),
    (133000, '風が連れてきた予感', '微风捎来的预感'),
    (150000, '響く音に包まれて', '被回响的乐声包裹'),
    (168000, '言葉にできないまま', '始终没能说出口'),
    (186000, '朝が来るまで踊ろう', '就跳到天亮吧'),
  ];

  @override
  @override
  Future<SongLyrics> loadLyrics(MusicSong song) async => lyricsFor(song);

  /// 测试替身的播放地址：只用来驱动「已加载」分支，不会被真的请求
  /// （测试进程用 SilentAudioEngine，见 music_audio_engine.dart）。
  @override
  Future<String?> resolvePlayUrl(MusicSong song, QualityTier quality) async => 'https://example.invalid/${song.id}.mp3';

  @override
  SongLyrics lyricsFor(MusicSong song) {
    if (song.id == 's1') {
      return SongLyrics(
        lines: [for (final (t, jp, cn) in _yozoraLyrics) LyricLine(t: t, text: jp, translation: cn)],
        hasTranslation: true,
      );
    }
    // 其余曲目：按时长均分 6 行的占位时间轴（演示数据）。
    final total = song.duration.inMilliseconds;
    final step = total ~/ 7;
    final lines = [for (var i = 1; i <= 6; i++) LyricLine(t: step * i, text: '${song.title} — 第 $i 句歌词（演示）')];
    return SongLyrics(lines: lines);
  }

  // ── 评论（data.js comments，N20）──────────────────────────────────────────
  @override
  Future<List<MusicComment>> comments(String songId) async {
    _guard(FailScope.comments);
    return const [
      MusicComment(
        id: 'cm1',
        nick: '云中漫步信箱',
        content: '每次前奏响起都会起鸡皮疙瘩，夜曲一响全场安静。',
        time: '2 小时前',
        likes: 12000,
        hot: true,
      ),
      MusicComment(id: 'cm2', nick: '打烊之后', content: '写代码循环了一整晚，波形跟着节奏跳动的那一刻绝了。', time: '昨天', likes: 8634, hot: true),
      MusicComment(id: 'cm3', nick: '深夜写代码', content: '「留在后台」的提示和这段旋律很配。', time: '3 小时前', likes: 421, hot: false),
      MusicComment(id: 'cm4', nick: '星轨邮差', content: '求歌手其他歌，已经加入歌单了。', time: '5 小时前', likes: 158, hot: false),
      MusicComment(id: 'cm5', nick: '麦田里的猫', content: '通勤必备，已经单曲循环一周。', time: '6 小时前', likes: 96, hot: false),
    ];
  }

  // ── 播放历史（data.js history 8 条 → 相对时间落今/昨/更早）─────────────────
  @override
  Future<List<MusicHistoryEntry>> history() async {
    _guard(FailScope.history);
    final now = DateTime.now();
    DateTime day(int d, int hh, int mm) => DateTime(now.year, now.month, now.day - d, hh, mm);
    final ids = <(String, int, int, int)>[
      ('s1', 0, 14, 32),
      ('s2', 0, 13, 58),
      ('s3', 0, 9, 12),
      ('s7', 1, 21, 47),
      ('s4', 1, 20, 33),
      ('s8', 1, 19, 4),
      ('s5', 3, 22, 15),
      ('s10', 4, 8, 41),
    ];
    return [for (final (id, d, hh, mm) in ids) MusicHistoryEntry(song: songById(id), playedAt: day(d, hh, mm))];
  }

  // ── 本地音乐（localSeed 8 首；导入后按文件名登记）──────────────────────────
  final List<MusicSong> _local = [
    for (final (i, name) in ['夜曲', '千本樱', '红莲华', '前前前世', '打上花火', 'Lemon', '孤勇者', '稻香'].indexed)
      MusicSong(
        id: 'local-$i',
        title: name,
        artist: '本地文件',
        album: '本机',
        duration: Duration(seconds: 200 + 17 * i),
        platformId: 'local',
      ),
  ];

  @override
  Future<List<MusicSong>> localTracks() async {
    _guard(FailScope.local);
    return List.unmodifiable(_local);
  }

  /// 本地导入（拖放 / 文件选择器的落点）：登记进列表（演示口径，不校验音频格式）。
  void addLocalTracks(List<String> names) {
    var i = 0;
    for (final name in names) {
      _local.add(
        MusicSong(
          id: 'local-import-${DateTime.now().microsecondsSinceEpoch}-$i',
          title: name,
          artist: '本地文件',
          album: '本机',
          duration: const Duration(seconds: 210),
          platformId: 'local',
        ),
      );
      i++;
    }
  }

  void clearLocal() => _local.clear();
}
