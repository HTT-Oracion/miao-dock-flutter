import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../domain/music_models.dart';
import 'api/music_api_error.dart';
import 'api/netease_api.dart';
import 'api/qqmusic_api.dart';
import 'api/kugou_api.dart';
import 'music_repository.dart';
import 'sources/kugou_source.dart';
import 'sources/migu_source.dart';
import 'sources/music_source.dart';
import 'sources/netease_source.dart';
import 'sources/qq_source.dart';

/// 真实音源仓库：按当前平台把 [MusicRepository] 的方法转给对应 [MusicSource]。
///
/// 真实四平台接口（Dart 移植自 miao-dock 的 Rust 客户端）。
/// 失败一律如实抛错，不静默回退本地演示数据。
///
/// 歌词 / 评论 / 每日推荐三类能力各平台不一致，由 [MusicSource] 的能力位决定：
/// 不支持时返回空集，而不是抛错 —— 空是「这个平台没有该功能」，不是故障。
class PlatformMusicRepository implements MusicRepository {
  PlatformMusicRepository({required this.platformId, MusicSource? source, this.cookie = ''})
    : _source = source ?? _buildSource(platformId, cookie);

  final String platformId;
  final MusicSource _source;
  final String cookie;

  /// 歌词缓存：`{歌曲id: 歌词}`。UI 的 [lyricsFor] 是同步的（构建期读），
  /// 真实音源只能先回空轴再异步补 —— 缓存命中后同一位置自然变成真歌词。
  final Map<String, SongLyrics> _lyricCache = {};

  /// 失败注入（仅自测用，与演示仓库同口径）。
  final Set<FailScope> _fails = {};

  /// 列表页见过的歌单 / 榜单元数据（按 id）。
  ///
  /// 为什么要缓存：部分平台的**详情接口只给曲目**（酷狗 `special/song`、`rank/song`
  /// 的 data 里没有 specialname / 封面），详情页因此拿不到标题与封面。
  /// 列表页本来就有这些字段，记下来在详情时回填，比再猜一个接口可靠。
  final Map<String, MusicPlaylist> _metaCache = {};

  static MusicSource _buildSource(String platformId, String cookie) => switch (platformId) {
    'netease' => NeteaseSource(api: NeteaseApi(cookie: cookie)),
    'qq' => QqSource(api: QqMusicApi(cookie: cookie)),
    'kugou' => KugouSource(api: KugouApi(cookie: cookie)),
    'migu' => MiguSource(),
    _ => throw ArgumentError('platform has no remote source: \$platformId'),
  };

  void _guard(FailScope scope) {
    if (_fails.contains(scope) || _fails.contains(FailScope.all)) {
      throw const MusicRepositoryException(MusicRepositoryErrorCode.network);
    }
  }

  Future<T> _translate<T>(Future<T> Function() run, FailScope scope) async {
    _guard(scope);
    try {
      return await run();
    } on MusicRepositoryException {
      rethrow;
    } on MusicApiException catch (e) {
      throw MusicRepositoryException(_codeOf(e), cause: e);
    } on Object catch (e) {
      throw MusicRepositoryException(MusicRepositoryErrorCode.network, cause: e);
    }
  }

  static MusicRepositoryErrorCode _codeOf(MusicApiException e) => switch (e.kind) {
    MusicApiErrorKind.network || MusicApiErrorKind.http => MusicRepositoryErrorCode.network,
    MusicApiErrorKind.parse => MusicRepositoryErrorCode.network,
    MusicApiErrorKind.business =>
      e.message.contains('login_required') ? MusicRepositoryErrorCode.loginRequired : MusicRepositoryErrorCode.notFound,
  };

  // ── 发现页 ──────────────────────────────────────────────────────────────

  @override
  Future<List<MusicRecCard>> recCards() async {
    // 推荐栏由「榜单 + 推荐歌单 + 每日推荐」拼成 9 张竖卡：真实平台没有这个聚合接口，
    // 三源组合既保留设计稿的 9 卡横向滚动，也保证每张卡点了真能播。
    return _translate(() async {
      final playlists = await _source.recommendedPlaylists(limit: 4);
      final charts = await _source.charts();
      final cards = <MusicRecCard>[];
      for (final (i, pl) in playlists.take(3).indexed) {
        cards.add(
          MusicRecCard(
            id: 'pl-${pl.id}',
            title: pl.name,
            subtitle: pl.description ?? '',
            tint: _tints[i % _tints.length],
            seed: pl.name,
            icon: _recIcons[i % _recIcons.length],
            songIds: const [],
            playlistId: pl.id,
            coverUrl: pl.coverUrl,
          ),
        );
      }
      for (final (i, ch) in charts.take(6).indexed) {
        cards.add(
          MusicRecCard(
            id: 'ch-${ch.id}',
            title: ch.name,
            subtitle: ch.updateMeta,
            tint: _tints[(i + 3) % _tints.length],
            seed: ch.name,
            icon: _recIcons[(i + 3) % _recIcons.length],
            songIds: const [],
            playlistId: ch.id,
            coverUrl: ch.coverUrl,
          ),
        );
      }
      return cards;
    }, FailScope.recs);
  }

  @override
  Future<List<MusicPlaylist>> recommendedPlaylists() => _translate(() async {
    final list = await _source.recommendedPlaylists(limit: 6);
    if (list.isNotEmpty) return _remember(list);
    // 平台无推荐歌单能力（酷狗 / 无 cookie 的 QQ）：退回榜单清单，保证首页有入口。
    final charts = await _source.charts();
    return _remember([
      for (final c in charts.take(6))
        MusicPlaylist(
          id: c.id,
          name: c.name,
          trackCount: 0,
          seed: c.name,
          description: c.updateMeta,
          coverUrl: c.coverUrl,
        ),
    ]);
  }, FailScope.playlists);

  @override
  Future<List<MusicChart>> charts() => _translate(() async {
    final list = await _source.charts();
    final out = <MusicChart>[];
    for (final c in list.take(6)) {
      // 榜单卡要 Top3：逐张取详情（失败的那张跳过，不影响其他卡）。
      List<MusicSong> songs = const [];
      try {
        songs = (await _source.chartDetail(c.id)).songs;
      } on Object {
        songs = const [];
      }
      out.add(
        MusicChart(
          id: c.id,
          name: c.name,
          updateMeta: c.updateMeta,
          seed: c.name,
          coverUrl: c.coverUrl,
          top: [for (final s in songs.take(3)) ChartTopEntry(title: s.title, artist: s.artist, trend: ChartTrend.flat)],
        ),
      );
    }
    return out;
  }, FailScope.charts);

  @override
  Future<List<MusicSong>> dailySongs() => _translate(() async {
    if (!_source.supportsDailySongs) return const [];
    return _source.dailySongs();
  }, FailScope.daily);

  // ── 详情 ────────────────────────────────────────────────────────────────

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> sourceDetail(MusicSourceKind kind, String id) =>
      _translate(() async {
        return switch (kind) {
          // 详情接口可能只给曲目，用列表页记住的元数据补齐标题 / 封面。
          MusicSourceKind.playlist => _mergeMeta(await _source.playlistDetail(id)),
          MusicSourceKind.chart => _mergeMeta(await _source.chartDetail(id)),
          MusicSourceKind.daily => (
            meta: MusicPlaylist(id: 'daily', name: '', trackCount: 0, seed: '', special: true),
            songs: await _source.dailySongs(),
          ),
        };
      }, kind == MusicSourceKind.chart ? FailScope.charts : FailScope.playlists);

  /// 记下列表元数据（只记有名字的，避免用空壳覆盖好数据）。
  List<MusicPlaylist> _remember(List<MusicPlaylist> list) {
    for (final p in list) {
      if (p.id.isNotEmpty && p.name.isNotEmpty) _metaCache[p.id] = p;
    }
    return list;
  }

  /// 用缓存补齐详情元数据：详情给了的字段优先，缺的（尤其封面）从列表补。
  ({MusicPlaylist meta, List<MusicSong> songs}) _mergeMeta(({MusicPlaylist meta, List<MusicSong> songs}) d) {
    final cached = _metaCache[d.meta.id];
    if (cached == null) return d;
    return (
      meta: MusicPlaylist(
        id: d.meta.id,
        name: d.meta.name.isNotEmpty ? d.meta.name : cached.name,
        trackCount: d.meta.trackCount > 0 ? d.meta.trackCount : cached.trackCount,
        seed: d.meta.seed.isNotEmpty ? d.meta.seed : cached.seed,
        playCountValue: d.meta.playCountValue ?? cached.playCountValue,
        description: (d.meta.description ?? '').isNotEmpty ? d.meta.description : cached.description,
        coverUrl: d.meta.coverUrl ?? cached.coverUrl,
        special: d.meta.special,
        author: d.meta.author ?? cached.author,
        subscribed: d.meta.subscribed,
      ),
      songs: d.songs,
    );
  }

  @override
  Future<List<MusicPlaylist>> userPlaylists() =>
      _translate(() async => _remember(await _source.userPlaylists()), FailScope.playlists);

  @override
  Future<MusicPlaylist> likedPlaylist() => _translate(() async {
    // 「我喜欢的音乐」在四平台的用户歌单里都以 `special`（网易云 specialType=5）
    // 标识，没有独立接口：从已登录的用户歌单里挑出来即可。
    // 未登录时 userPlaylists 会抛 login_required，仓库层转成 loginRequired 供 UI 引导。
    final playlists = await _source.userPlaylists();
    final liked = playlists.where((p) => p.special).firstOrNull;
    if (liked == null) throw const MusicRepositoryException(MusicRepositoryErrorCode.loginRequired);
    return liked;
  }, FailScope.playlists);

  @override
  Future<List<MusicSong>> similarSongs(MusicSong seed, {int limit = 20}) =>
      _translate(() => _source.similarSongs(seed, limit: limit), FailScope.playlists);

  // ── 搜索 ────────────────────────────────────────────────────────────────

  @override
  Future<({List<MusicSong> songs, List<MusicPlaylist> playlists})> search(String keyword) => _translate(() async {
    if (keyword.trim().isEmpty) {
      return (songs: const <MusicSong>[], playlists: const <MusicPlaylist>[]);
    }
    final songs = await _source.searchSongs(keyword.trim(), limit: 30);
    List<MusicPlaylist> playlists = const [];
    try {
      playlists = await _source.searchPlaylists(keyword.trim(), limit: 12);
    } on Object {
      playlists = const [];
    }
    return (songs: songs, playlists: _remember(playlists));
  }, FailScope.search);

  // ── 歌词 / 评论 ─────────────────────────────────────────────────────────

  @override
  SongLyrics lyricsFor(MusicSong song) => _lyricCache[song.id] ?? const SongLyrics(lines: []);

  @override
  Future<SongLyrics> loadLyrics(MusicSong song) async {
    final cached = _lyricCache[song.id];
    if (cached != null) return cached;
    _guard(FailScope.all);
    try {
      final lyrics = await _source.lyrics(song);
      _lyricCache[song.id] = lyrics;
      return lyrics;
    } on MusicApiException catch (e) {
      throw MusicRepositoryException(_codeOf(e), cause: e);
    } on Object catch (e) {
      throw MusicRepositoryException(MusicRepositoryErrorCode.network, cause: e);
    }
  }

  @override
  Future<List<MusicComment>> comments(String songId) => _translate(() async {
    if (!_source.supportsComments) return const [];
    return _source.comments(songId, limit: 20);
  }, FailScope.comments);

  // ── 本地 / 历史（真实音源不做本地文件与跨平台历史；由 UI 的本地仓库承担）──────

  @override
  Future<List<MusicHistoryEntry>> history() async => const [];

  @override
  Future<List<MusicSong>> localTracks() async => const [];

  // ── 自检通道 ────────────────────────────────────────────────────────────

  @override
  void setFailScope(FailScope scope, bool on) => on ? _fails.add(scope) : _fails.remove(scope);

  @override
  void resetFailScopes() => _fails.clear();

  /// 播放地址（供播放器在真实音源下取流；演示仓库返回 null）。
  @override
  Future<String?> resolvePlayUrl(MusicSong song, QualityTier quality) async {
    try {
      return await _source.songUrl(song, quality);
    } on MusicApiException {
      return null;
    }
  }

  static const _tints = [
    Color(0xFFB08446),
    Color(0xFFB23B2C),
    Color(0xFF7C8490),
    Color(0xFF4E545C),
    Color(0xFFB07A3A),
    Color(0xFF4A5A78),
  ];

  static const _recIcons = <IconData>[
    LucideIcons.calendarDays,
    LucideIcons.compass,
    LucideIcons.radio,
    LucideIcons.waves,
    LucideIcons.sparkles,
    LucideIcons.moon,
  ];
}
