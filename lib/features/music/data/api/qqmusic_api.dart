import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../domain/music_models.dart';
import 'lrc.dart';
import 'music_api_error.dart';
import 'music_http.dart';

/// QQ 音乐客户端（移植自 `miao-dock/src-tauri/src/music/qqmusic.rs`）。
///
/// 两个入口：
/// · `u.y.qq.com/cgi-bin/musicu.fcg` —— 正式接口，需 `music.search.SearchCgiService`
///   模块 + `sign`（SHA1 十六位重排 + 异或 + base64，见 [qqSign]）；
/// · `c.y.qq.com/...` 旧版 CGI —— 歌词 / 专辑信息，免签名。
class QqMusicApi {
  QqMusicApi({MusicHttp? http, this.cookie = ''})
    : _http =
          http ??
          MusicHttp(
            platform: 'qqmusic',
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Referer': 'https://y.qq.com/',
            },
          );

  final MusicHttp _http;
  String cookie;

  static const _musicu = 'https://u.y.qq.com/cgi-bin/musicu.fcg';

  // ── 签名 ────────────────────────────────────────────────────────────────

  /// QQ `sign`：`zzc{hash[23,14,6,36,16,40,7,19]}{base64(xor)}{hash[16,1,32,12,19,27,8,5]}`。
  ///
  /// 必须逐字对齐上游：`hash` 是 SHA1 **十六进制字符串**（40 字符），
  /// 取位顺序与异或表都不能改，改一位服务端就回 `sign error`。
  static String qqSign(String text) {
    final hash = sha1.convert(utf8.encode(text)).toString();
    const part1 = [23, 14, 6, 36, 16, 40, 7, 19];
    const part2 = [16, 1, 32, 12, 19, 27, 8, 5];
    const scramble = [89, 39, 179, 150, 218, 82, 58, 252, 177, 52, 186, 123, 120, 64, 242, 133, 143, 161, 121, 179];
    // 越界下标按空串处理（上游 JS 的 `Array.map(hash[i]).join('')` 对 undefined 即如此，
    // Rust 侧用 filter_map 等价跳过）；直接索引会抛 RangeError。
    final p1 = part1.where((i) => i < hash.length).map((i) => hash[i]).join();
    final p2 = part2.where((i) => i < hash.length).map((i) => hash[i]).join();
    final bytes = <int>[
      for (final (i, v) in scramble.indexed) v ^ int.parse(hash.substring(i * 2, i * 2 + 2), radix: 16),
    ];
    final middle = base64.encode(bytes).replaceAll(RegExp(r'[\\/+=]'), '');
    return 'zzc$p1$middle$p2'.toLowerCase();
  }

  // ── 搜索 ────────────────────────────────────────────────────────────────

  /// 搜索单曲（`music.search.SearchCgiService.DoSearchForQQMusicMobile`）。
  Future<List<MusicSong>> searchSongs(String keywords, {int limit = 30, int offset = 0}) async {
    final pageSize = limit.clamp(1, 30);
    final payload = {
      'comm': {
        'ct': '11',
        'cv': '14090508',
        'v': '14090508',
        'tmeAppID': 'qqmusic',
        'phonetype': 'EBG-AN10',
        'os_ver': '12',
        'OpenUDID': '0',
        'QIMEI36': '0',
        'udid': '0',
        'chid': '0',
        'aid': '0',
        'oaid': '0',
        'taid': '0',
        'tid': '0',
        'wid': '0',
        'uid': '0',
        'sid': '0',
        'modeSwitch': '6',
        'teenMode': '0',
        'ui_mode': '2',
        'nettype': '1020',
      },
      'req': {
        'module': 'music.search.SearchCgiService',
        'method': 'DoSearchForQQMusicMobile',
        'param': {
          'search_type': 0,
          'searchid': '${DateTime.now().millisecondsSinceEpoch}000000',
          'query': keywords,
          'page_num': offset ~/ pageSize + 1,
          'num_per_page': pageSize,
          'highlight': 0,
          'nqc_flag': 0,
          'multi_zhida': 0,
          'cat': 2,
          'grp': 1,
          'sin': 0,
          'sem': 0,
        },
      },
    };
    final body = jsonEncode(payload);
    final json = await _http.postJson('$_musicu?sign=${qqSign(body)}', body);
    final bodyNode = _dig(json, ['req', 'data', 'body']);
    final items = bodyNode is Map ? (bodyNode['item_song'] ?? _dig(bodyNode, ['song', 'list'])) : null;
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map<String, dynamic>)
          _songFromTrack(item['track_info'] is Map<String, dynamic> ? item['track_info'] as Map : item),
    ];
  }

  /// 搜索歌单（旧版 `fcg_get_diss_by_tag`，免签名）。
  Future<List<MusicPlaylist>> searchPlaylists(String keywords, {int limit = 12}) async {
    final json = await _http.getJson(
      'https://c.y.qq.com/splcloud/fcgi-bin/fcg_get_diss_by_tag.fcg',
      query: {
        'picmid': 1,
        'rnd': DateTime.now().millisecondsSinceEpoch,
        'g_tk': 5381,
        'loginUin': 0,
        'hostUin': 0,
        'format': 'json',
        'inCharset': 'utf8',
        'outCharset': 'utf-8',
        'notice': 0,
        'platform': 'yqq.json',
        'needNewCode': 0,
        'categoryId': 10000000,
        'sortId': 5,
        'sin': 0,
        'ein': limit,
      },
    );
    final list = _dig(json, ['data', 'list']);
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map<String, dynamic>)
          MusicPlaylist(
            id: '${item['dissid'] ?? ''}',
            name: '${item['dissname'] ?? ''}',
            trackCount: (item['song_count'] as num?)?.toInt() ?? 0,
            seed: '${item['dissname'] ?? ''}',
            playCountValue: (item['listennum'] as num?)?.round(),
            description: '${_dig(item, ['creator', 'name']) ?? ''}',
            coverUrl: '${item['imgurl'] ?? item['logo'] ?? ''}',
          ),
    ];
  }

  /// 推荐歌单（`fcg_get_diss_by_tag` 按「推荐」排序：sortId=5 即最热）。
  Future<List<MusicPlaylist>> recommendedPlaylists({int limit = 6}) => searchPlaylists('', limit: limit);

  // ── 用户歌单（登录态）────────────────────────────────────────────────────

  /// 用户歌单：自建（`fcg_user_created_diss`）+ 收藏（`fcg_get_profile_order_asset`
  /// reqtype=3）。对齐 miao-dock `qqmusic::user_playlists` 的两个入口与字段映射。
  ///
  /// 未登录返回空集（平台能力位为「需登录」，不是故障）。
  Future<List<MusicPlaylist>> userPlaylists() async {
    final auth = _parseQqAuth(cookie);
    if (auth.uin.isEmpty || auth.musicKey.isEmpty) return const [];
    final created = await _createdPlaylists(auth.uin);
    final collected = await _collectedPlaylists(auth.uin);
    final seen = <String>{};
    final out = <MusicPlaylist>[];
    for (final p in [...created, ...collected]) {
      if (p.id.isEmpty || p.name.isEmpty) continue;
      if (!seen.add(p.id)) continue;
      out.add(p);
    }
    return out;
  }

  Future<List<MusicPlaylist>> _createdPlaylists(String uin) async {
    final json = await _http.getJson(
      'https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss',
      query: {
        'hostUin': 0,
        'hostuin': uin,
        'sin': 0,
        'size': 200,
        'g_tk': 5381,
        'loginUin': uin,
        'format': 'json',
        'inCharset': 'utf8',
        'outCharset': 'utf-8',
        'notice': 0,
        'platform': 'yqq.json',
        'needNewCode': 0,
      },
    );
    final rows = _dig(json, ['data', 'disslist']);
    if (rows is! List) return const [];
    return [
      for (final item in rows)
        if (item is Map<String, dynamic>) userPlaylistFromMap(item, subscribed: false),
    ];
  }

  Future<List<MusicPlaylist>> _collectedPlaylists(String uin) async {
    final json = await _http.getJson(
      'https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg',
      query: {'ct': 20, 'cid': 205360956, 'userid': uin, 'reqtype': 3, 'sin': 0, 'ein': 199},
    );
    final rows = _dig(json, ['data', 'cdlist']) ?? _dig(json, ['data', 'v_playlist']);
    if (rows is! List) return const [];
    return [
      for (final item in rows)
        if (item is Map<String, dynamic>) userPlaylistFromMap(item, subscribed: true),
    ];
  }

  /// 用户歌单字段映射（`dissid / diss_name / dirid`；`dirid == 201` 是「我喜欢」）。
  @visibleForTesting
  static MusicPlaylist userPlaylistFromMap(Map<String, dynamic> m, {required bool subscribed}) {
    final dirid = (m['dirid'] as num?)?.toInt() ?? 0;
    final liked = dirid == 201;
    final rawId = '${m['dissid'] ?? m['tid'] ?? m['dirid'] ?? m['id'] ?? ''}';
    final name = _stripHtml('${m['diss_name'] ?? m['dissname'] ?? m['name'] ?? m['title'] ?? ''}');
    final creator = m['creator'] is Map<String, dynamic>
        ? '${(m['creator'] as Map<String, dynamic>)['name'] ?? (m['creator'] as Map<String, dynamic>)['nick'] ?? ''}'
        : '${m['nickname'] ?? m['creator'] ?? ''}';
    final rawCount = m['song_cnt'] ?? m['songnum'] ?? m['song_count'] ?? m['total_song_num'];
    final rawListen = m['listen_num'] ?? m['visitnum'];
    return MusicPlaylist(
      id: liked ? 'liked' : rawId,
      name: name,
      trackCount: rawCount is num ? rawCount.toInt() : 0,
      seed: name,
      playCountValue: rawListen is num ? rawListen.round() : null,
      description: creator.isEmpty ? null : creator,
      // 「我喜欢」歌单没有自己的封面，接口也不给图 —— 用平台官方收藏图兜底，
      // 否则列表里那张卡永远是渐变占位（miao-dock 同口径）。
      coverUrl: liked ? _likedCover : _coalesceCover([m['logo'], m['picurl'], m['diss_cover'], m['cover']]),
      author: creator.isEmpty ? null : creator,
      special: liked,
      subscribed: subscribed && !liked,
    );
  }

  /// Cookie 里的 QQ 登录信息（`uin` + `qm_keyst` 等，对齐 miao-dock `cookie.rs`）。
  static ({String uin, String musicKey}) _parseQqAuth(String raw) {
    final map = <String, String>{};
    for (final part in raw.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) map[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    final loginType = int.tryParse(map['login_type'] ?? '') ?? 0;
    final rawUin = loginType == 2
        ? (map['wxuin'] ?? map['uin'] ?? map['p_uin'] ?? '')
        : (map['uin'] ?? map['qqmusic_uin'] ?? map['wxuin'] ?? map['p_uin'] ?? '');
    final uin = rawUin.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^0+'), '');
    final musicKey =
        map['qm_keyst'] ??
        map['qqmusic_key'] ??
        map['music_key'] ??
        map['p_skey'] ??
        map['skey'] ??
        map['wxskey'] ??
        '';
    return (uin: uin, musicKey: musicKey);
  }

  // ── 歌单 ────────────────────────────────────────────────────────────────

  /// 歌单曲目（`fcg_ucc_getcdinfo_byids_cp.fcg`，免签名）。
  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(String id) async {
    final json = await _http.getJson(
      'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
      query: {
        'type': 1,
        'json': 1,
        'utf8': 1,
        'onlysong': 0,
        'disstid': id,
        'format': 'json',
        'g_tk': 5381,
        'loginUin': 0,
        'hostUin': 0,
        'inCharset': 'utf8',
        'outCharset': 'utf-8',
        'notice': 0,
        'platform': 'yqq.json',
        'needNewCode': 0,
      },
    );
    final cdlist = _dig(json, ['cdlist']);
    if (cdlist is! List || cdlist.isEmpty) {
      throw MusicApiException.business('qqmusic', 'playlist_not_found:$id');
    }
    final cd = cdlist.first as Map;
    final songs = cd['songlist'];
    return (
      meta: MusicPlaylist(
        id: '${cd['disstid'] ?? id}',
        name: '${cd['dissname'] ?? ''}',
        trackCount: (cd['songnum'] as num?)?.toInt() ?? (songs is List ? songs.length : 0),
        seed: '${cd['dissname'] ?? ''}',
        playCountValue: (cd['visitnum'] as num?)?.round(),
        description: '${_dig(cd, ['creator', 'name']) ?? ''}',
      ),
      songs: <MusicSong>[
        if (songs is List)
          for (final s in songs)
            if (s is Map) _songFromTrack(s),
      ],
    );
  }

  /// 榜单曲目（`fcg_v8_toplist_cp.fcg`）。
  Future<({MusicPlaylist meta, List<MusicSong> songs})> chartDetail(String id) async {
    final json = await _http.getJson(
      'https://c.y.qq.com/v8/fcg-bin/fcg_v8_toplist_cp.fcg',
      query: {
        'topid': id,
        'format': 'json',
        'inCharset': 'utf8',
        'outCharset': 'utf-8',
        'notice': 0,
        'platform': 'yqq.json',
        'needNewCode': 0,
        'tpl': 3,
        'page': 'detail',
        'type': 'top',
        'song_begin': 0,
        'song_num': 50,
      },
    );
    final info = _dig(json, ['topinfo']);
    final list = _dig(json, ['songlist']);
    return (
      meta: MusicPlaylist(
        id: id,
        name: info is Map<String, dynamic> ? '${info['ListName'] ?? ''}' : '',
        trackCount: list is List ? list.length : 0,
        seed: info is Map<String, dynamic> ? '${info['ListName'] ?? ''}' : '',
        description: info is Map<String, dynamic> ? '${info['update_time'] ?? ''}' : '',
      ),
      songs: <MusicSong>[
        if (list is List)
          for (final item in list)
            if (item is Map<String, dynamic> && item['data'] is Map<String, dynamic>)
              _songFromTrack(item['data'] as Map),
      ],
    );
  }

  /// 官方榜单清单（内置 9 张，与上游 `QQ_RANK_LIST` 一致）。
  static const rankList = <({String id, String name})>[
    (id: '26', name: 'Hot chart'),
    (id: '27', name: 'New chart'),
    (id: '4', name: 'Pop index'),
    (id: '62', name: 'Rising'),
    (id: '5', name: 'Mainland'),
    (id: '6', name: 'HK/TW'),
    (id: '105', name: 'Oricon'),
    (id: '51', name: 'Rising star'),
    (id: '52', name: 'Original'),
  ];

  // ── 歌词 ────────────────────────────────────────────────────────────────

  /// 歌词（`music.musichallSong.PlayLyricInfo.GetPlayLyricInfo`）。
  Future<SongLyrics> lyric({required String mid, String id = ''}) async {
    final payload = {
      'comm': {'ct': 24, 'cv': 0},
      'lyric': {
        'module': 'music.musichallSong.PlayLyricInfo',
        'method': 'GetPlayLyricInfo',
        'param': {'songMID': mid, if (id.isNotEmpty) 'songID': int.tryParse(id) ?? 0},
      },
    };
    final json = await _http.postJson(_musicu, jsonEncode(payload));
    final data = _dig(json, ['lyric', 'data']);
    if (data is! Map) return const SongLyrics(lines: []);
    final lrc = _decodeLyricText('${data['lyric'] ?? ''}');
    final trans = _decodeLyricText('${data['trans'] ?? ''}');
    return parseLrc(lrc, translation: trans);
  }

  /// 旧版歌词接口（musicu 失败时兜底，`nobase64=1` 直接拿明文）。
  Future<SongLyrics> lyricLegacy(String mid) async {
    final text = await _http.getText(
      'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
      headers: {'Referer': 'https://y.qq.com/portal/player.html'},
    );
    final json = _tryJson(text);
    final lrc = json is Map ? '${json['lyric'] ?? ''}' : '';
    final trans = json is Map ? '${json['trans'] ?? ''}' : '';
    return parseLrc(_decodeLyricText(lrc), translation: _decodeLyricText(trans));
  }

  // ── 播放地址 ────────────────────────────────────────────────────────────

  /// vkey 获取（`vkey.GetVkeyServer.CgiGetVkey`）：按音质模板逐档降级。
  Future<String?> songUrl(String mid, {String mediaMid = '', QualityTier quality = QualityTier.high}) async {
    final songmid = mid.trim();
    if (songmid.isEmpty) return null;
    final media = mediaMid.trim().isEmpty ? songmid : mediaMid;
    final guid = '${10000000 + DateTime.now().millisecondsSinceEpoch % 90000000}';
    final start = _templates.indexWhere((t) => t.level == _levelOf(quality));
    final templates = start < 0 ? _templates : _templates.sublist(start);
    final filenames = <String>[for (final t in templates) '${t.prefix}$media${t.ext}'];
    final payload = {
      'comm': {'uin': '0', 'format': 'json', 'ct': 24, 'cv': 0},
      'req_0': {
        'module': 'vkey.GetVkeyServer',
        'method': 'CgiGetVkey',
        'param': {
          'guid': guid,
          'songmid': [for (final _ in filenames) songmid],
          'songtype': [for (final _ in filenames) 0],
          'uin': '0',
          'loginflag': 1,
          'platform': '20',
          'filename': filenames,
        },
      },
    };
    final json = await _http.postJson(_musicu, jsonEncode(payload));
    final data = _dig(json, ['req_0', 'data']);
    if (data is! Map) return null;
    final infos = data['midurlinfo'];
    final sips = (data['sip'] is List ? data['sip'] as List : const <dynamic>[])
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
    final sip = sips.isEmpty ? 'https://ws.stream.qqmusic.qq.com/' : sips.first;
    if (infos is! List) return null;
    for (final info in infos) {
      if (info is! Map) continue;
      final purl = '${info['purl'] ?? ''}';
      if (purl.isEmpty) continue;
      return '$sip$purl';
    }
    return null;
  }

  static const _templates = <({String prefix, String ext, String level})>[
    (prefix: 'RS01', ext: '.flac', level: 'hires'),
    (prefix: 'F000', ext: '.flac', level: 'lossless'),
    (prefix: 'M800', ext: '.mp3', level: 'exhigh'),
    (prefix: 'M500', ext: '.mp3', level: 'standard'),
    (prefix: 'C400', ext: '.m4a', level: 'aac'),
  ];

  static String _levelOf(QualityTier q) => switch (q) {
    QualityTier.standard => 'standard',
    QualityTier.high => 'exhigh',
    QualityTier.lossless => 'lossless',
    QualityTier.hires || QualityTier.master => 'hires',
  };

  // ── 映射 ────────────────────────────────────────────────────────────────

  MusicSong _songFromTrack(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    final singers = (m['singer'] is List ? m['singer'] as List : const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((s) => '${s['name'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toList();
    final rawAlbum = m['album'];
    final album = rawAlbum is Map<String, dynamic> ? rawAlbum : const <String, dynamic>{};
    final interval = (m['interval'] as num?)?.toInt() ?? 0;
    return MusicSong(
      id: '${m['mid'] ?? m['songmid'] ?? m['id'] ?? ''}',
      title: _stripHtml('${m['name'] ?? m['songname'] ?? ''}'),
      artist: singers.isEmpty ? _stripHtml('${m['singer'] ?? ''}') : singers.join(' / '),
      album: _stripHtml('${album['name'] ?? m['albumname'] ?? ''}'),
      duration: Duration(seconds: interval),
      platform: MusicPlatform.qq,
      qualityLabel: _qqQualityLabel(m),
      coverUrl: _albumCover('${album['mid'] ?? ''}'),
      mediaId:
          '${(m['file'] is Map<String, dynamic> ? (m['file'] as Map<String, dynamic>)['media_mid'] : null) ?? m['media_mid'] ?? ''}',
    );
  }

  /// 「我喜欢」歌单的固定封面（miao-dock 常量）。
  static const _likedCover = 'https://y.gtimg.cn/mediastyle/global/img/cover_like.png';

  static String _coalesceCover(List<Object?> candidates) {
    for (final c in candidates) {
      final v = '${c ?? ''}'.trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// QQ 专辑封面模板：`T002R300x300M000{albumMid}.jpg`。
  static String? _albumCover(String albumMid) {
    if (albumMid.isEmpty) return null;
    return 'https://y.qq.com/music/photo_new/T002R300x300M000$albumMid.jpg?max_age=2592000';
  }

  static String? _qqQualityLabel(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    final rawFile = m['file'];
    final file = rawFile is Map<String, dynamic> ? rawFile : const <String, dynamic>{};
    final sizeHires = (file['size_hires'] as num?)?.toInt() ?? 0;
    final sizeFlac = (file['size_flac'] as num?)?.toInt() ?? 0;
    final size320 = (file['size_320mp3'] as num?)?.toInt() ?? 0;
    if (sizeHires > 0) return 'Hi-Res';
    if (sizeFlac > 0) return 'lossless';
    if (size320 > 0) return '320K';
    return null;
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>');

  static String _decodeLyricText(String text) {
    final raw = _stripHtml(text.trim());
    if (raw.isEmpty) return '';
    final compact = raw.replaceAll(RegExp(r'\s'), '');
    final looksBase64 =
        compact.length >= 8 &&
        compact.length % 4 == 0 &&
        RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(compact) &&
        !raw.startsWith('[');
    if (looksBase64) {
      try {
        final decoded = utf8.decode(base64.decode(compact));
        final trimmed = decoded.replaceFirst('\uFEFF', '');
        if (trimmed.contains('[') || RegExp(r'[\u4e00-\u9fff]').hasMatch(trimmed)) {
          return trimmed.replaceAll('\r\n', '\n').trim();
        }
      } on FormatException {
        // 不是 base64：按原文返回。
      }
    }
    return raw.replaceAll('\r\n', '\n').trim();
  }

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

  static dynamic _tryJson(String text) {
    try {
      return jsonDecode(text.trim());
    } on FormatException {
      return null;
    }
  }
}
