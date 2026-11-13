import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../domain/music_models.dart';
import 'lrc.dart';
import 'music_cover_url.dart';
import 'music_http.dart';

/// 咪咕音乐客户端（移植自 `miao-dock/src-tauri/src/music/migu.rs`）。
///
/// 所有接口明文 GET；唯一特殊处是 `strategy/pc/listen/v2.0` 的响应体是
/// **逐字节偏移混淆流**：前 4 字节是头部，其后每字节 `+ offset - key[i]`。
/// 这个解码在 [decodeListenBody] 中实现，必须有对应单测（错一位就整段乱码）。
class MiguApi {
  MiguApi({MusicHttp? http})
    : _http =
          http ??
          MusicHttp(
            platform: 'migu',
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36',
              'Referer': 'https://music.migu.cn/',
            },
          );

  final MusicHttp _http;

  static const _songSearch = 'https://app.u.nf.migu.cn/pc/resource/song/item/search/v1.0';
  static const _playlistDetail = 'https://app.c.nf.migu.cn/resource/playlist/v2.0';
  static const _playlistSongs = 'https://app.c.nf.migu.cn/MIGUM3.0/resource/playlist/song/v2.0';
  static const _listen = 'https://app.c.nf.migu.cn/strategy/pc/listen/v2.0';
  static const _rankSongs = 'https://app.c.nf.migu.cn/MIGUM3.0/column/rank/h5/v1.0';
  static const _recommend = 'https://app.c.nf.migu.cn/pc/bmw/page-data/playlist-square-recommend/v1.0';

  /// 播放地址混淆流解码密钥（31 字节，与上游逐字节一致）。
  static const listenKey = 'Jk8qzuePiJ1qE3mDYhLQ3T73DtDoAhLP';

  /// 榜单 columnId（热歌 / 新歌 / 原创）。
  static const rankHot = '27186466';
  static const rankNew = '27553319';
  static const rankOriginal = '27553408';

  // ── 搜索 ────────────────────────────────────────────────────────────────

  Future<List<MusicSong>> searchSongs(String keywords, {int limit = 30, int offset = 0}) async {
    final pageSize = limit.clamp(1, 50);
    final page = offset ~/ pageSize + 1;
    final json = await _http.getJson(_songSearch, query: {'text': keywords, 'pageNo': page, 'pageSize': pageSize});
    if (json is! List) return const [];
    return [
      for (final item in json)
        if (item is Map<String, dynamic>) _songFromItem(item),
    ];
  }

  /// 歌单广场推荐（`playlist-square-recommend`）。
  Future<List<MusicPlaylist>> recommendedPlaylists({int limit = 6}) async {
    final json = await _http.getJson(
      _recommend,
      query: {'templateVersion': 2, '_t': DateTime.now().millisecondsSinceEpoch},
    );
    final list = _findPlaylists(json);
    return list.take(limit).toList();
  }

  /// 用户歌单（`pc/user/home-page/v2.0`）：对齐 miao-dock `migu::user_playlists`。
  ///
  /// 三块语义位：`userPrivateItems`（官方歌单）、`myCreatedMusicLists`（自建）、
  /// `myCollectedMusicLists`（收藏）。缺 Cookie 时接口回登录页结构 → 返回空集。
  Future<List<MusicPlaylist>> userPlaylists() async {
    final json = await _http.getJson(
      'https://app.c.nf.migu.cn/pc/user/home-page/v2.0',
      query: {'_t': DateTime.now().millisecondsSinceEpoch},
    );
    final data = _dig(json, ['data']);
    if (data is! Map<String, dynamic>) return const [];
    final out = <MusicPlaylist>[];

    void add(dynamic node, {required bool subscribed}) {
      if (node is! List) return;
      for (final item in node) {
        if (item is! Map<String, dynamic>) continue;
        final id = _miguPlaylistId(item);
        if (id.isEmpty) continue;
        final name = '${item['title'] ?? item['name'] ?? ''}';
        if (name.isEmpty) continue;
        out.add(
          MusicPlaylist(
            id: id,
            name: name,
            trackCount: _miguPlaylistCount(item),
            seed: name,
            description: '${item['summary'] ?? item['desc'] ?? ''}',
            coverUrl: normalizeCoverUrl(item['img'] ?? item['image'] ?? item['cover']),
            subscribed: subscribed,
          ),
        );
      }
    }

    add(data['userPrivateItems'], subscribed: false);
    add(_dig(data, ['myCreatedMusicLists', 'createdMusicLists']), subscribed: false);
    add(_dig(data, ['myCollectedMusicLists', 'collectMusicLists']), subscribed: true);
    return out;
  }

  static String _miguPlaylistId(Map<String, dynamic> item) {
    final direct = item['musicListId'];
    if (direct != null && '$direct'.trim().isNotEmpty) return '$direct'.trim();
    final action = '${item['actionUrl'] ?? ''}';
    final match = RegExp(r'musicListId=([0-9A-Za-z_]+)').firstMatch(action);
    return match?.group(1) ?? '';
  }

  static int _miguPlaylistCount(Map<String, dynamic> item) {
    final raw = item['musicNum'] ?? item['songCount'] ?? item['count'];
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}') ?? 0;
  }

  // ── 歌单 ────────────────────────────────────────────────────────────────

  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(String id) async {
    final json = await _http.getJson(_playlistDetail, query: {'playlistId': id});
    final data = _dig(json, ['data']) ?? json;
    final name = data is Map ? '${data['title'] ?? data['name'] ?? ''}' : '';
    final list = await _http.getJson(_playlistSongs, query: {'pageNo': 1, 'pageSize': 60, 'playlistId': id});
    final songs = _findSongs(list);
    return (
      meta: MusicPlaylist(
        id: id,
        name: name,
        trackCount: songs.length,
        seed: name,
        description: data is Map ? '${data['summary'] ?? data['desc'] ?? ''}' : '',
        // 详情页 hero / 封面色块取这里；漏掉就是整个歌单详情没有封面。
        // 字段口径与列表一致（img / image / cover），另兼容歌单详情特有的
        // coverUrl / picUrl —— 不同接口版本命名不统一。
        coverUrl: data is Map
            ? normalizeCoverUrl(data['img'] ?? data['image'] ?? data['cover'] ?? data['coverUrl'] ?? data['picUrl'])
            : null,
      ),
      songs: songs,
    );
  }

  /// 榜单曲目（`column/rank/h5`：`data.columnInfo.contents[].objectInfo`）。
  Future<({MusicPlaylist meta, List<MusicSong> songs})> rankDetail(String id) async {
    final json = await _http.getJson(_rankSongs, query: {'pageSize': 50, 'columnId': id});
    final contents = _dig(json, ['data', 'columnInfo', 'contents']);
    final songs = <MusicSong>[
      if (contents is List)
        for (final item in contents)
          if (item is Map<String, dynamic> && item['objectInfo'] is Map<String, dynamic>)
            _songFromItem(item['objectInfo'] as Map<String, dynamic>),
    ];
    final name = _dig(json, ['data', 'columnInfo', 'columnName']);
    return (
      meta: MusicPlaylist(
        id: id,
        name: name is String && name.isNotEmpty ? name : '',
        trackCount: songs.length,
        seed: name is String && name.isNotEmpty ? name : '',
        coverUrl: normalizeCoverUrl(
          _dig(json, ['data', 'columnInfo', 'columnPicUrl']) ?? _dig(json, ['data', 'columnInfo', 'columnSmallpicUrl']),
        ),
      ),
      songs: songs,
    );
  }

  // ── 播放地址 / 歌词 ──────────────────────────────────────────────────────

  /// 取 `listen/v2.0` 混淆流并解码成 JSON（播放 URL + 歌词 URL）。
  Future<Map<String, dynamic>> listen({
    required String contentId,
    String copyrightId = '',
    QualityTier quality = QualityTier.lossless,
  }) async {
    final bytes = await _http.getBytes(
      _listen,
      query: {
        'contentId': contentId,
        'copyrightId': copyrightId,
        'scene': '',
        'netType': '01',
        'resourceType': 2,
        'toneFlag': _toneFlag(quality),
      },
    );
    return decodeListenBody(bytes);
  }

  Future<String?> songUrl(
    String contentId, {
    String copyrightId = '',
    QualityTier quality = QualityTier.lossless,
  }) async {
    for (final q in _degradeOrder(quality)) {
      final json = await listen(contentId: contentId, copyrightId: copyrightId, quality: q);
      final url = _findAudioUrl(json);
      if (url != null && url.isNotEmpty) return url.replaceFirst('http://', 'https://');
    }
    return null;
  }

  Future<SongLyrics> lyric(String contentId, {String copyrightId = ''}) async {
    final json = await listen(contentId: contentId, copyrightId: copyrightId, quality: QualityTier.standard);
    final lrcUrl = _findLrcUrl(json);
    if (lrcUrl == null || lrcUrl.isEmpty) return const SongLyrics(lines: []);
    final text = await _http.getText(lrcUrl);
    return parseLrc(text);
  }

  /// 混淆流解码：`out[i] = body[i+4] + offset - key[i % key.length]`（逐字节取模 256）。
  ///
  /// 🔴 `offset` 是**响应的第 4 个字节**（前 4 字节里只有它参与运算），
  /// 改成常量 0 或漏掉 `+offset` 都会让整段正文错位成乱码。
  static Map<String, dynamic> decodeListenBody(List<int> body) {
    if (body.length <= 4) return const {};
    final offset = body[3];
    final key = utf8.encode(listenKey);
    final out = <int>[for (var i = 0; i < body.length - 4; i++) (body[i + 4] + offset - key[i % key.length]) & 0xFF];
    final text = utf8.decode(out, allowMalformed: true);
    final json = jsonDecode(text);
    return json is Map<String, dynamic> ? json : const {};
  }

  static String _toneFlag(QualityTier q) => switch (q) {
    QualityTier.standard => 'PQ',
    QualityTier.high => 'HQ',
    QualityTier.lossless => 'SQ',
    QualityTier.hires || QualityTier.master => 'ZQ',
  };

  static List<QualityTier> _degradeOrder(QualityTier q) => switch (q) {
    QualityTier.master || QualityTier.hires => [QualityTier.hires, QualityTier.lossless, QualityTier.high],
    QualityTier.lossless => [QualityTier.lossless, QualityTier.high, QualityTier.standard],
    QualityTier.high => [QualityTier.high, QualityTier.standard],
    QualityTier.standard => [QualityTier.standard],
  };

  // ── 映射 ────────────────────────────────────────────────────────────────

  MusicSong _songFromItem(Map<String, dynamic> item) {
    final singers = (item['singerList'] is List ? item['singerList'] as List : const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((s) => '${s['name'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toList();
    // 咪咕 `duration` 是**秒**（其它平台多为毫秒）：直接乘 1000，别当毫秒用。
    final durationSec = (item['duration'] as num?)?.toInt() ?? 0;
    return MusicSong(
      id: '${item['copyrightId'] ?? item['songId'] ?? item['contentId'] ?? ''}',
      title: '${item['songName'] ?? item['name'] ?? ''}',
      artist: singers.isEmpty ? '${item['singerName'] ?? ''}' : singers.join(' / '),
      album: '${item['album'] ?? item['albumName'] ?? ''}',
      duration: Duration(seconds: durationSec),
      platformId: 'migu',
      qualityLabel: _miguQuality(item),
      mediaId: '${item['contentId'] ?? item['copyrightId'] ?? ''}',
      coverUrl: _miguCover(item),
    );
  }

  /// 封面：新版 `img3/img2/img1`；旧版只有 `albumImgs[]`（按 03→02→01 取最优）。
  /// 两条链路都要走，否则老歌单 / 老榜单一整片退化成渐变占位。
  static String? _miguCover(Map<String, dynamic> item) {
    for (final key in const ['img3', 'img2', 'img1']) {
      final v = _padImage('${item[key] ?? ''}');
      if (v != null) return v;
    }
    final imgs = item['albumImgs'];
    if (imgs is List) {
      for (final type in const ['03', '02', '01']) {
        for (final row in imgs) {
          if (row is! Map) continue;
          if ('${row['imgSizeType'] ?? ''}' != type) continue;
          final v = _padImage('${row['img'] ?? ''}');
          if (v != null) return v;
        }
      }
    }
    return null;
  }

  static String? _miguQuality(Map<String, dynamic> item) {
    final tags = item['audioFormats'];
    if (tags is List) {
      final names = tags.whereType<Map<String, dynamic>>().map((t) => '${t['formatType'] ?? ''}').toSet();
      if (names.contains('ZQ')) return 'hires';
      if (names.contains('SQ')) return 'lossless';
      if (names.contains('HQ')) return '320K';
    }
    return null;
  }

  /// 任意层级的歌曲数组（咪咕各接口的包裹层不统一，按结构找而不是按路径写死）。
  List<MusicSong> _findSongs(dynamic json) {
    final out = <MusicSong>[];
    void walk(dynamic node) {
      if (node is List) {
        for (final item in node) {
          if (item is Map<String, dynamic> &&
              (item['songName'] != null || item['name'] != null) &&
              item['copyrightId'] != null) {
            out.add(_songFromItem(item));
          } else {
            walk(item);
          }
        }
      } else if (node is Map<String, dynamic>) {
        for (final v in node.values) {
          walk(v);
        }
      }
    }

    walk(json);
    return out;
  }

  List<MusicPlaylist> _findPlaylists(dynamic json) {
    final out = <MusicPlaylist>[];
    final seen = <String>{};

    void walk(dynamic node) {
      if (node is List) {
        for (final item in node) {
          walk(item);
        }
        return;
      }
      if (node is! Map<String, dynamic>) return;

      final parsed = _playlistFromNode(node);
      if (parsed != null && seen.add(parsed.id)) {
        out.add(parsed);
        return; // 命中歌单节点后不再下钻，避免把内部字段当新歌单
      }
      for (final v in node.values) {
        walk(v);
      }
    }

    walk(json);
    return out;
  }

  /// 歌单广场的节点有两套命名：
  /// · 老口径 `playlistId` / `playlistName`；
  /// · 现网 `ZJ-SongList-Item` 卡片：标题在 `txt`、封面在 `img`、
  ///   id 在 `logEvent.resourceId`（`contentType=2021` 才是歌单）。
  /// 只认老口径会整块漏掉，表现为「推荐歌单有卡片但没有封面」。
  @visibleForTesting
  static MusicPlaylist? playlistFromNode(Map<String, dynamic> node) => _playlistFromNode(node);

  static MusicPlaylist? _playlistFromNode(Map<String, dynamic> node) {
    final logEvent = node['logEvent'];
    final resourceType = logEvent is Map ? '${logEvent['contentType'] ?? ''}' : '';
    final isCard = resourceType == '2021' || '${node['view'] ?? ''}' == 'ZJ-SongList-Item';

    final id =
        node['playlistId'] ??
        (isCard && logEvent is Map ? logEvent['contentId'] ?? logEvent['resourceId'] : null) ??
        node['id'];
    final name = node['playlistName'] ?? node['name'] ?? (isCard ? node['txt'] : null);
    if (id == null || name is! String || name.isEmpty) return null;

    return MusicPlaylist(
      id: '$id',
      name: name,
      trackCount: (node['songCount'] as num?)?.toInt() ?? 0,
      seed: name,
      playCountValue: (node['playCount'] as num?)?.round(),
      description: '${node['summary'] ?? node['desc'] ?? ''}',
      coverUrl: normalizeCoverUrl(node['img'] ?? node['img2'] ?? node['image'] ?? node['cover']),
    );
  }

  static String? _findAudioUrl(dynamic json) {
    String? found;
    void walk(dynamic node) {
      if (found != null) return;
      if (node is Map<String, dynamic>) {
        for (final entry in node.entries) {
          final v = entry.value;
          if (v is String && (v.startsWith('http://') || v.startsWith('https://')) && _audioExt.hasMatch(v)) {
            found = v;
            return;
          }
          walk(v);
        }
      } else if (node is List) {
        for (final v in node) {
          walk(v);
        }
      }
    }

    walk(json);
    return found;
  }

  static String? _findLrcUrl(dynamic json) {
    String? found;
    void walk(dynamic node) {
      if (found != null) return;
      if (node is Map<String, dynamic>) {
        for (final entry in node.entries) {
          final v = entry.value;
          if (v is String && v.contains('lrc') && v.startsWith('http')) {
            found = v;
            return;
          }
          walk(v);
        }
      } else if (node is List) {
        for (final v in node) {
          walk(v);
        }
      }
    }

    walk(json);
    return found;
  }

  /// 相对封面路径补全（`/data/oss/...` → `https://d.musicapp.migu.cn/...`）。
  static String? _padImage(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('//')) return 'https:$v';
    if (v.startsWith('http')) return v.replaceFirst('http://', 'https://');
    return 'https://d.musicapp.migu.cn${v.startsWith('/') ? '' : '/'}$v';
  }

  static final _audioExt = RegExp(r'\.(mp3|flac|m4a|wav|aac|ogg)(\?|$)', caseSensitive: false);

  static dynamic _dig(dynamic json, List<String> path) {
    dynamic cur = json;
    for (final key in path) {
      if (cur is Map) {
        cur = cur[key];
      } else {
        return null;
      }
    }
    return cur;
  }
}
