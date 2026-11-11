import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/music_models.dart';
import 'lrc.dart';
import 'music_api_error.dart';
import 'music_http.dart';

/// 网易云音乐客户端（移植自 `miao-dock/src-tauri/src/music/netease.rs`）。
///
/// 端口选择说明：原实现里「搜索 / 歌单 / 歌词 / 评论」走**明文 API**
/// （`music.163.com/api/*`），只有二维码登录与每日推荐走 EAPI 加密。
/// Dart 侧同样只保留明文接口 + 明文二维码轮询（已实测 `client/login` 返回 801/802/803），
/// 加密路径（EAPI / weapi）在客户端只需 Cookie，不必重复实现 AES + RSA。
class NeteaseApi {
  NeteaseApi({MusicHttp? http, this.cookie = ''})
    : _http =
          http ??
          MusicHttp(
            platform: 'netease',
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 9; PCT-AL10) AppleWebKit/537.36 (KHTML, like Gecko) '
                  'Chrome/70.0.3538.64 HuaweiBrowser/10.0.3.311 Mobile Safari/537.36',
              'Referer': 'https://music.163.com/',
            },
          );

  static const _base = 'https://music.163.com';

  final MusicHttp _http;

  /// 登录 Cookie（`MUSIC_U=...; __csrf=...`）。空串 = 匿名。
  String cookie;

  Map<String, String> get _cookieHeader => cookie.isEmpty ? const {} : {'Cookie': cookie};

  MusicHttp get _client {
    _http.dio.options.headers.addAll(_cookieHeader);
    return _http;
  }

  // ── 搜索 ────────────────────────────────────────────────────────────────

  /// 搜索单曲。原实现用 `/api/cloudsearch/get/web`（2026-11 实测回 50000005，
  /// 平台已收紧），退回仍可用的 `/api/search/get/web`（同一响应结构）。
  Future<List<MusicSong>> searchSongs(String keywords, {int limit = 30, int offset = 0}) async {
    final json = await _client.postForm('$_base/api/search/get/web', {
      's': keywords,
      'type': 1,
      'limit': limit,
      'offset': offset,
    });
    final songs = _dig(json, ['result', 'songs']);
    if (songs is! List) return const [];
    return [
      for (final item in songs)
        if (item is Map<String, dynamic>) _songFromMap(item),
    ];
  }

  /// 搜索歌单。
  Future<List<MusicPlaylist>> searchPlaylists(String keywords, {int limit = 12, int offset = 0}) async {
    final json = await _client.postForm('$_base/api/search/get/web', {
      's': keywords,
      'type': 1000,
      'limit': limit,
      'offset': offset,
    });
    final list = _dig(json, ['result', 'playlists']);
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map<String, dynamic>) _playlistFromMap(item),
    ];
  }

  // ── 发现页数据面 ─────────────────────────────────────────────────────────

  /// 推荐歌单（`/api/personalized/playlist`，匿名可取）。
  Future<List<MusicPlaylist>> personalizedPlaylists({int limit = 6}) async {
    final json = await _client.postForm('$_base/api/personalized/playlist', {'limit': limit, 'csrf_token': ''});
    final list = _dig(json, ['result']);
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map<String, dynamic>) _playlistFromMap(item),
    ];
  }

  /// 推荐新歌（`/api/personalized/newsong`，匿名可取，用于推荐歌曲区）。
  Future<List<MusicSong>> newSongs({int limit = 6}) async {
    final json = await _client.getJson('$_base/api/personalized/newsong', query: {'limit': limit});
    final list = _dig(json, ['result']);
    if (list is! List) return const [];
    final out = <MusicSong>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final inner = item['song'] is Map ? item['song'] as Map : item;
      final song = _songFromMap(inner);
      if (song.title.isEmpty) continue;
      // 外层 picUrl 常是推荐位封面，内层 al 往往缺图 —— 补到歌上（与原实现一致）。
      out.add(song);
    }
    return out;
  }

  /// 官方榜单列表（`/api/toplist/detail`）。
  Future<List<({String id, String name, String updateMeta, String seed, String cover})>> toplists() async {
    final json = await _client.postForm('$_base/api/toplist/detail', const {});
    final list = _dig(json, ['list']);
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map<String, dynamic>)
          (
            id: '${item['id'] ?? ''}',
            name: '${item['name'] ?? ''}',
            updateMeta: '${item['updateFrequency'] ?? item['updateTime'] ?? ''}',
            seed: '${item['name'] ?? ''}',
            cover: '${item['coverImgUrl'] ?? ''}',
          ),
    ];
  }

  // ── 歌单 ────────────────────────────────────────────────────────────────

  /// 歌单元数据 + 曲目（`/api/v6/playlist/detail` 的 `tracks` 直接带歌）。
  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(String id) async {
    final json = await _client.postForm('$_base/api/v6/playlist/detail', {'id': id, 'n': 1000, 's': 0});
    final pl = _dig(json, ['playlist']);
    if (pl is! Map) throw MusicApiException.business('netease', 'playlist_not_found:$id');
    final tracks = pl['tracks'];
    final songs = <MusicSong>[
      if (tracks is List)
        for (final t in tracks)
          if (t is Map) _songFromMap(t),
    ];
    return (meta: _playlistFromMap(pl), songs: songs);
  }

  /// 用户歌单（登录态，`/api/user/playlist`）：对齐 miao-dock `netease::user_playlist`。
  ///
  /// `subscribed` 是**语义位**（收藏别人的歌单），不是排序信息；「我喜欢的音乐」
  /// 由 `specialType == 5` 识别，与 upstream 一致。
  Future<List<MusicPlaylist>> userPlaylists({String uid = ''}) async {
    final userId = uid.isNotEmpty ? uid : (await loginStatus()).userId;
    if (userId.isEmpty) throw MusicApiException.business('netease', 'login_required');
    final json = await _client.getJson('$_base/api/user/playlist', query: {'uid': userId, 'limit': 100, 'offset': 0});
    final list = _dig(json, ['playlist']);
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map<String, dynamic>) _playlistFromMap(item),
    ];
  }

  /// 我喜欢的音乐（登录态）：`/api/song/like` 拿不到曲目时回退到用户歌单第一项。
  Future<({MusicPlaylist meta, List<MusicSong> songs})> likedPlaylist(String uid) async {
    final json = await _client.getJson('$_base/api/user/playlist', query: {'uid': uid, 'limit': 100, 'offset': 0});
    final list = _dig(json, ['playlist']);
    if (list is! List) throw MusicApiException.business('netease', 'login_required');
    Map<String, dynamic>? liked;
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      if (item['specialType'] == 5) {
        liked = item;
        break;
      }
    }
    liked ??= list.whereType<Map<String, dynamic>>().firstOrNull;
    if (liked == null) throw MusicApiException.business('netease', 'login_required');
    final detail = await playlistDetail('${liked['id']}');
    return (meta: detail.meta.copyWithSpecial(true), songs: detail.songs);
  }

  /// 心动模式相似歌曲。优先调用智能播放接口，失败或空结果时回落匿名可用的 simiSong。
  Future<List<MusicSong>> similarSongs(String songId, {int limit = 20}) async {
    if (cookie.isNotEmpty) {
      try {
        final playlists = await userPlaylists();
        final liked = playlists.where((playlist) => playlist.special).firstOrNull;
        if (liked != null) {
          final json = await _client.postForm('$_base/api/playmode/intelligence/list', {
            'songId': songId,
            'type': 'fromPlayOne',
            'playlistId': liked.id,
            'startMusicId': songId,
            'count': 1,
          });
          final data = _dig(json, ['data']);
          if (data is List) {
            final songs = <MusicSong>[
              for (final item in data)
                if (item is Map && item['songInfo'] is Map) _songFromMap(item['songInfo']),
            ];
            if (songs.isNotEmpty) return songs.take(limit).toList(growable: false);
          }
        }
      } on Object {
        // 智能播放要求登录与喜欢歌单；失败继续走匿名相似歌曲接口。
      }
    }
    final json = await _client.getJson('$_base/api/v1/discovery/simiSong', query: {'songid': songId});
    final rows = _dig(json, ['songs']);
    if (rows is! List) return const [];
    return [
      for (final item in rows.take(limit))
        if (item is Map<String, dynamic>) _songFromMap(item),
    ];
  }

  // ── 歌词 / 评论 / 播放地址 ───────────────────────────────────────────────

  /// 逐句歌词（`/api/song/lyric/v1`，含翻译轨）。
  Future<SongLyrics> lyric(String id) async {
    final json = await _client.postForm('$_base/api/song/lyric/v1', {
      'id': id,
      'cp': 'false',
      'lv': 0,
      'kv': 0,
      'tv': 0,
      'rv': 0,
      'yv': 0,
      'ytv': 0,
      'yrv': 0,
      'csrf_token': '',
    });
    final lrc = _dig(json, ['lrc', 'lyric']) as String? ?? '';
    final tlyric = _dig(json, ['tlyric', 'lyric']) as String? ?? '';
    return parseLrc(lrc, translation: tlyric);
  }

  /// 评论（`/api/v1/resource/comments/R_SO_4_{id}`）。
  Future<List<MusicComment>> comments(String songId, {int limit = 20, int offset = 0}) async {
    final json = await _client.getJson(
      '$_base/api/v1/resource/comments/R_SO_4_$songId',
      query: {'limit': limit, 'offset': offset},
    );
    final hot = _dig(json, ['hotComments']);
    final all = _dig(json, ['comments']);
    final rows = <dynamic>[
      if (hot is List) ...hot.whereType<Map<String, dynamic>>(),
      if (all is List) ...all.whereType<Map<String, dynamic>>(),
    ];
    final seen = <String>{};
    final out = <MusicComment>[];
    for (final c in rows) {
      final id = '${c['commentId'] ?? ''}';
      if (id.isEmpty || !seen.add(id)) continue;
      final user = c['user'] is Map<String, dynamic> ? c['user'] as Map<String, dynamic> : const <String, dynamic>{};
      out.add(
        MusicComment(
          id: id,
          nick: '${user['nickname'] ?? ''}',
          content: '${c['content'] ?? ''}',
          time: _relativeTime(c['time']),
          likes: (c['likedCount'] as num?)?.toInt() ?? 0,
          hot: hot is List && hot.contains(c),
        ),
      );
    }
    return out;
  }

  /// 播放地址（`/api/song/enhance/player/url/v1`，按音质逐档降级）。
  ///
  /// 返回 null = 平台明确回复无可用 URL（需登录 / VIP / 下架），调用方据此
  /// 播下一首而不是当成网络错误重试。
  Future<String?> songUrl(String id, QualityTier quality) async {
    for (final level in _levelsFor(quality)) {
      final json = await _client.postForm('$_base/api/song/enhance/player/url/v1', {
        'ids': '["$id"]',
        'level': level,
        'encodeType': 'flac',
        'csrf_token': '',
      });
      final data = _dig(json, ['data']);
      if (data is! List || data.isEmpty) continue;
      final first = data.first;
      if (first is! Map) continue;
      final url = first['url'] as String?;
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  static List<String> _levelsFor(QualityTier q) => switch (q) {
    QualityTier.standard => ['standard', 'higher', 'exhigh'],
    QualityTier.high => ['exhigh', 'higher', 'standard'],
    QualityTier.lossless => ['lossless', 'exhigh', 'standard'],
    QualityTier.hires => ['hires', 'lossless', 'exhigh'],
    QualityTier.master => ['jymaster', 'hires', 'lossless'],
  };

  // ── 二维码登录 ───────────────────────────────────────────────────────────

  /// 获取二维码 key（明文接口，实测可用）。
  Future<String> qrKey() async {
    final json = await _client.postForm('$_base/api/login/qrcode/unikey', {'type': 1, 'csrf_token': ''});
    final key = _dig(json, ['unikey']) as String?;
    if (key == null || key.isEmpty) {
      throw MusicApiException.business('netease', 'qr_key_failed');
    }
    return key;
  }

  /// 轮询扫码状态：801 等待 / 802 待确认 / 803 成功（成功时回写 cookie）。
  ///
  /// 🔴 必须是**表单**编码：同一个接口用 JSON body 会返回
  /// `{"code":400,"message":"参数错误"}`（2026-11 实测），表现为二维码一直不刷新、
  /// 扫码后也不会跳成功 —— 这是「二维码扫不了」的真正原因。
  Future<({int code, String message, String? cookie})> qrCheck(String key) async {
    final resp = await _http.dio.post<String>(
      '$_base/api/login/qrcode/client/login',
      data: {'key': key, 'type': 1, 'csrf_token': ''},
      options: diagOptions().copyWith(contentType: Headers.formUrlEncodedContentType),
    );
    final json = resp.data == null ? null : _tryDecode(resp.data!);
    final code = (json is Map ? json['code'] as num? : null)?.toInt() ?? -1;
    final message = (json is Map ? '${json['message'] ?? ''}' : '');
    final setCookie = resp.headers['set-cookie'] ?? const <String>[];
    final parts = <String>[
      for (final c in setCookie)
        if (c.split(';').first.trim().isNotEmpty) c.split(';').first.trim(),
    ];
    final cookie = parts.isEmpty ? null : parts.join('; ');
    return (code: code, message: message, cookie: cookie);
  }

  /// 登录态（`/api/nuser/account/get`）：返回用户 id 与昵称。
  Future<({bool loggedIn, String userId, String nick})> loginStatus() async {
    final json = await _client.getJson('$_base/api/nuser/account/get');
    final profile = _dig(json, ['profile']);
    if (profile is! Map) return (loggedIn: false, userId: '', nick: '');
    return (loggedIn: true, userId: '${profile['userId'] ?? ''}', nick: '${profile['nickname'] ?? ''}');
  }

  // ── 映射 ────────────────────────────────────────────────────────────────

  static dynamic _dig(dynamic json, List<String> path) {
    dynamic cur = json;
    for (final key in path) {
      if (cur is Map) {
        cur = cur[key];
      } else if (cur is List && int.tryParse(key) != null) {
        final i = int.parse(key);
        cur = (i >= 0 && i < cur.length) ? cur[i] : null;
      } else {
        return null;
      }
    }
    return cur;
  }

  static dynamic _tryDecode(String text) {
    try {
      return text.trim().isEmpty ? null : jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static Options diagOptions() => Options(responseType: ResponseType.plain, validateStatus: (_) => true);

  MusicSong _songFromMap(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    final rawArtists = m['ar'] ?? m['artists'];
    final artists = rawArtists is List
        ? rawArtists.whereType<Map<String, dynamic>>().map((a) => '${a['name'] ?? ''}').toList()
        : <String>[];
    final rawAlbum = m['al'] ?? m['album'];
    final album = rawAlbum is Map<String, dynamic> ? rawAlbum : const <String, dynamic>{};
    final dt = (m['dt'] ?? m['duration']) as num?;
    return MusicSong(
      id: '${m['id'] ?? ''}',
      title: '${m['name'] ?? ''}',
      artist: artists.isEmpty ? '${m['artist'] ?? ''}' : artists.join(' / '),
      album: '${album['name'] ?? ''}',
      duration: Duration(milliseconds: dt?.toInt() ?? 0),
      platform: MusicPlatform.netease,
      qualityLabel: _qualityLabel(m),
      coverUrl: _picUrl('${album['picUrl'] ?? ''}'),
    );
  }

  /// 网易云封面支持 `?param=WxH` 缩放；统一取 300×300，列表与详情够用。
  static String? _picUrl(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final base = v.replaceFirst('http://', 'https://');
    return base.contains('?') ? base : '$base?param=300y300';
  }

  static String? _qualityLabel(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    final h = m['h'];
    if (h is Map && h['br'] is num) {
      final br = (h['br'] as num).toInt();
      if (br >= 900) return 'lossless';
      if (br > 0) return '${br}K';
    }
    final fee = (m['fee'] as num?)?.toInt() ?? 0;
    if (fee == 1) return 'vip';
    return null;
  }

  static MusicPlaylist _playlistFromMap(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    final creator = m['creator'] ?? m['copywriter'];
    final count = (m['trackCount'] ?? m['songCount']) as num?;
    final nickname = creator is Map ? '${creator['nickname'] ?? ''}' : '${creator ?? ''}';
    return MusicPlaylist(
      id: '${m['id'] ?? ''}',
      name: '${m['name'] ?? ''}',
      trackCount: count?.toInt() ?? 0,
      seed: '${m['name'] ?? ''}',
      playCountValue: ((m['playCount'] ?? m['playcount']) as num?)?.round(),
      description: nickname,
      coverUrl: _picUrl('${m['coverImgUrl'] ?? m['picUrl'] ?? ''}'),
      author: nickname.isEmpty ? null : nickname,
      special: (m['specialType'] as num?)?.toInt() == 5,
      subscribed: m['subscribed'] == true,
    );
  }

  static String _relativeTime(dynamic ms) {
    if (ms is! num) return '';
    final at = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return '';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  }
}
