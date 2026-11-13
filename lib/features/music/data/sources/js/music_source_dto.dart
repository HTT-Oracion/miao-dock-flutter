import '../../../domain/music_models.dart';
import '../../../domain/js_music_source.dart';
import '../../../domain/music_source_manifest.dart';

/// 音乐源返回的纯 JSON → 领域模型。UI 永远不直接看到 JS 原始结构。
///
/// 容错口径：单条解析失败**跳过该条**而不是整体失败（上游偶尔会给脏数据）。
class MusicSourceDto {
  const MusicSourceDto({required this.platformId});

  final String platformId;

  // ── 歌曲 ───────────────────────────────────────────────────────────────

  /// 期望 `{songs: [...]}`；也兼容直接给数组。
  List<MusicSong> songs(Object? raw) {
    final list = _listOrSongsField(raw);
    return [
      for (final item in list)
        if (item is Map) _song(Map<String, dynamic>.from(item)),
    ];
  }

  MusicSong? song(Object? raw) {
    if (raw is! Map) return null;
    return _song(Map<String, dynamic>.from(raw));
  }

  /// 契约只认**归一化字段**（title / artist / album / durationMs）：
  /// 平台原始字段（网易云 ar/dt、QQ singerm 等）由 JS 源负责映射，
  /// DTO 层保持平台无关 —— 这是「源作者写一份映射」的边界。
  MusicSong _song(Map<String, dynamic> m) {
    final durationMs = (m['durationMs'] as num?)?.toInt() ?? 0;
    return MusicSong(
      id: _s(m['id']),
      title: _s(m['title']),
      artist: _s(m['artist']),
      album: _s(m['album']),
      duration: Duration(milliseconds: durationMs),
      platformId: platformId,
      qualityLabel: _optS(m['qualityLabel']),
      mediaId: _optS(m['mediaId']),
      coverUrl: _optS(m['coverUrl']),
    );
  }

  // ── 歌单 ───────────────────────────────────────────────────────────────

  /// 期望 `{playlists: [...]}`；也兼容直接给数组。
  List<MusicPlaylist> playlists(Object? raw) {
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['playlists'] as List<dynamic>? ?? const <dynamic>[]) : const <dynamic>[]);
    return [
      for (final item in list)
        if (item is Map) _playlist(Map<String, dynamic>.from(item)),
    ];
  }

  MusicPlaylist _playlist(Map<String, dynamic> m) {
    final name = _s(m['name']);
    return MusicPlaylist(
      id: _s(m['id']),
      name: name,
      trackCount: (m['trackCount'] as num?)?.toInt() ?? 0,
      // seed 用于 seed 封面兜底：没给就用歌单名。
      seed: _optS(m['seed']) ?? name,
      playCountValue: (m['playCountValue'] as num?)?.toInt(),
      description: _optS(m['description']),
      coverUrl: _optS(m['coverUrl']),
      special: m['special'] == true,
      author: _optS(m['author']),
      subscribed: m['subscribed'] == true,
    );
  }

  // ── 榜单 ───────────────────────────────────────────────────────────────

  /// 期望 `{charts: [...]}`；也兼容直接给数组。
  List<MusicChart> charts(Object? raw) {
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['charts'] as List<dynamic>? ?? const <dynamic>[]) : const <dynamic>[]);
    return [
      for (final item in list)
        if (item is Map) _chart(Map<String, dynamic>.from(item)),
    ];
  }

  MusicChart _chart(Map<String, dynamic> m) {
    final name = _s(m['name']);
    final top = <ChartTopEntry>[];
    for (final dynamic entry in (m['top'] as List<dynamic>? ?? const <dynamic>[])) {
      if (entry is! Map) continue;
      top.add(
        ChartTopEntry(
          title: _s(entry['title']),
          artist: _s(entry['artist']),
          trend: switch (_s(entry['trend'])) {
            'up' => ChartTrend.up,
            'new' => ChartTrend.newEntry,
            _ => ChartTrend.flat,
          },
        ),
      );
    }
    return MusicChart(
      id: _s(m['id']),
      name: name,
      updateMeta: _s(m['updateMeta']),
      seed: _optS(m['seed']) ?? name,
      top: top,
      coverUrl: _optS(m['coverUrl']),
    );
  }

  /// 榜单 / 歌单详情：`{meta: {...}, songs: [...]}`。
  ({MusicPlaylist meta, List<MusicSong> songs}) detail(Object? raw) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final meta = _playlist(Map<String, dynamic>.from((map['meta'] as Map?) ?? const {}));
    return (meta: meta, songs: songs(map['songs']));
  }

  // ── 歌词 ───────────────────────────────────────────────────────────────

  /// 期望 `{lines: [{t, text, translation?}], hasTranslation?}`。
  /// 源也可以给**原始 LRC 文本**（`{lrc: "[00:01.0]..."}`），这里顺手解析。
  SongLyrics lyrics(Object? raw) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final lrc = map['lrc'];
      if (lrc is String && lrc.isNotEmpty) {
        return _parseLrc(lrc, map['translation'] is String ? map['translation'] as String : null);
      }
      final lines = <LyricLine>[];
      for (final item in (map['lines'] as List? ?? const [])) {
        if (item is! Map) continue;
        final t = (item['t'] as num?)?.toInt() ?? 0;
        final text = '${item['text'] ?? ''}';
        if (text.isEmpty) continue;
        lines.add(LyricLine(t: t, text: text, translation: _optS(item['translation'])));
      }
      lines.sort((a, b) => a.t.compareTo(b.t));
      return SongLyrics(lines: lines, hasTranslation: lines.any((l) => l.translation != null));
    }
    return const SongLyrics(lines: []);
  }

  /// 极简 LRC：`[mm:ss.xx]` / `[mm:ss]` 行。
  SongLyrics _parseLrc(String lrc, String? translation) {
    final lines = <LyricLine>[];
    final pattern = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]\s*(.*)');
    for (final raw in lrc.split('\n')) {
      final m = pattern.firstMatch(raw);
      if (m == null) continue;
      final t =
          int.parse(m.group(1)!) * 60000 +
          int.parse(m.group(2)!) * 1000 +
          (m.group(3) != null ? int.parse(m.group(3)!.padRight(3, '0')) : 0);
      final text = m.group(4)?.trim() ?? '';
      if (text.isEmpty) continue;
      lines.add(LyricLine(t: t, text: text));
    }
    lines.sort((a, b) => a.t.compareTo(b.t));
    if (translation == null || translation.isEmpty) return SongLyrics(lines: lines, hasTranslation: false);
    final translated = _parseLrc(translation, null);
    if (translated.lines.isEmpty) return SongLyrics(lines: lines, hasTranslation: false);
    // 按时间就近对齐翻译轨。
    final merged = <LyricLine>[];
    for (final line in lines) {
      LyricLine? best;
      for (final cur in translated.lines) {
        if (best == null || (cur.t - line.t).abs() < (best.t - line.t).abs()) best = cur;
      }
      merged.add(LyricLine(t: line.t, text: line.text, translation: best?.text));
    }
    return SongLyrics(lines: merged, hasTranslation: true);
  }

  // ── 评论 ───────────────────────────────────────────────────────────────

  /// 期望 `{comments: [...], total?}`；也兼容直接给数组。
  List<MusicComment> comments(Object? raw) {
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['comments'] as List<dynamic>? ?? const <dynamic>[]) : const <dynamic>[]);
    return [
      for (final item in list)
        if (item is Map)
          MusicComment(
            id: _s(item['commentId'] ?? item['id']),
            nick: _s(item['nick'] ?? ((item['user'] is Map) ? (item['user'] as Map)['nickname'] : null)),
            content: _s(item['content']),
            time: _s(item['time']),
            likes: ((item['likes'] ?? item['likedCount']) as num?)?.toInt() ?? 0,
            hot: item['hot'] == true,
          ),
    ];
  }

  // ── 工具 ───────────────────────────────────────────────────────────────

  List<dynamic> _listOrSongsField(Object? raw) {
    if (raw is List) return raw;
    if (raw is Map) return (raw['songs'] as List? ?? const []);
    return const [];
  }

  String _s(Object? v) => '${v ?? ''}'.trim();

  String? _optS(Object? v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty ? null : s;
  }
}

/// 源 id → 能力集合的静态扫描（导入期）。
///
/// 扫描源 JS 里出现的方法名（`async name(` 或 `name: async` / `name: function`），
/// 只认契约白名单内的名字 —— 既当能力位，也防白名单外的方法被调用。
const musicSourceCapabilityNames = {
  'loginInfo',
  'searchSongs',
  'searchPlaylists',
  'charts',
  'chartDetail',
  'playlistDetail',
  'lyrics',
  'songUrl',
  'dailySongs',
  'comments',
  'userPlaylists',
  'init',
};

/// 从源 JS 文本扫描能力（导入期静态检查，不做语法解析）。
Set<String> scanMusicSourceCapabilities(String js) {
  final found = <String>{};
  for (final name in musicSourceCapabilityNames) {
    final patterns = [
      RegExp(r'(?:async\s+)?' + name + r'\s*\('),
      RegExp(r'(?:async\s+)?' + name + r'\s*:\s*(?:async\s+)?(?:function\b)?'),
    ];
    if (patterns.any((p) => p.hasMatch(js))) found.add(name);
  }
  return found;
}

/// 从已导入清单构造源对象。
JsMusicSource buildJsMusicSource(MusicSourceManifest manifest, {required String js}) =>
    JsMusicSource(manifest: manifest, capabilities: scanMusicSourceCapabilities(js));
