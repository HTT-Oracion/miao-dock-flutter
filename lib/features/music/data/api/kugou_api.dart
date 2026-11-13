import 'dart:convert';
import 'dart:math' show Random;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../domain/music_models.dart';
import 'lrc.dart';
import 'music_cover_url.dart';
import 'music_api_error.dart';
import 'music_http.dart';

/// 酷狗音乐客户端（移植自 `miao-dock/src-tauri/src/music/kugou.rs`）。
///
/// 只移植**免登录**链路：搜索 / 歌单 / 歌词 / 榜单。
/// 播放地址需要 H5 登录态的 userid + mid + token 才能算 `key` 签名
/// （`md5(hash + salt + appid + mid + userid)`），匿名调用网关会回 `privilege:0`，
/// 因此 [songUrl] 只在 [cookie] 含 token 时才尝试，否则直接回 null 让播放器跳过。
class KugouApi {
  KugouApi({MusicHttp? http, this.cookie = ''})
    : _http =
          http ??
          MusicHttp(
            platform: 'kugou',
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Referer': 'https://www.kugou.com/',
            },
          );

  final MusicHttp _http;
  String cookie;

  /// 登录 Cookie（`userid` / `mid` / `token` 三项决定能否取播放地址）。

  static const _search = 'http://songsearch.kugou.com/song_search_v2';
  static const _gateway = 'https://gateway.kugou.com';
  static const _lyricSearch = 'https://krcs.kugou.com/search';
  static const _lyricDownload = 'https://krcs.kugou.com/download';

  static const _webAppId = 1014;
  static const _h5Salt = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
  static const _signSalt = '57ae12eb6890223e355ccfcb74edf70d';

  // ── 二维码登录（对齐 KuGouMusicApi login_qr_key / login_qr_check）──────────

  /// 登录域名（与音乐网关分开，登录走 login-user）。
  static const _loginBase = 'https://login-user.kugou.com';

  /// 登录接口固定参数（`util/config.json`）。
  static const _loginAppid = 1001;
  static const _srcAppid = 2919;
  static const _clientver = 20489;

  /// 登录接口 UA：参考实现 `util/request.js` 的默认 UA（Android 客户端指纹）。
  static const _loginUa = 'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi';

  /// 酷狗 Web 签名：`md5(salt + 按 key 排序的 k=v 串 + data + salt)`。
  static String _webSign(Map<String, dynamic> params) {
    final pairs = params.keys.map((k) => '$k=${params[k]}').toList()..sort();
    return md5.convert(utf8.encode('$_h5Salt${pairs.join()}$_h5Salt')).toString();
  }

  /// 设备 MID：`md5(guid)` 的 16 进制转十进制大整数（参考 `calculateMid`）。
  static String _calcMid(String guid) => BigInt.parse(md5.convert(utf8.encode(guid)).toString(), radix: 16).toString();

  /// 本机稳定设备标识（进程内固定）。
  static final String _deviceGuid = _newGuid();
  static final String _deviceMid = _calcMid(_deviceGuid);

  static String _newGuid() {
    final r = Random.secure();
    const hex = '0123456789abcdef';
    final buf = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buf.write(hex[r.nextInt(16)]);
    }
    final s = buf.toString();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-4${s.substring(13, 16)}-8${s.substring(17, 20)}-${s.substring(20, 32)}';
  }

  Map<String, String> _loginHeaders(int clienttime) => {
    'User-Agent': _loginUa,
    'dfid': '-',
    'clienttime': '$clienttime',
    'mid': _deviceMid,
    // 以下四项是酷狗内部来源标识头，缺了会被判为非官方客户端。
    'kg-rc': '1',
    'kg-thash': '5d816a0',
    'kg-rec': '1',
    'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
  };

  /// 取二维码 key。返回 `qrcode`（轮询用）与 `qrcodeImg`（可直接显示的 base64）。
  Future<({String key, String? imageBase64})> qrKey() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final params = <String, dynamic>{
      'dfid': '-',
      'mid': _deviceMid,
      'uuid': '-',
      'appid': _loginAppid,
      'clientver': _clientver,
      'clienttime': now,
      'type': 1,
      'plat': 4,
      'qrcode_txt': 'https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=1005&',
      'srcappid': _srcAppid,
    };
    params['signature'] = _webSign(params);
    final uri = Uri.parse('$_loginBase/v2/qrcode').replace(queryParameters: params.map((k, v) => MapEntry(k, '$v')));
    final json = await _http.getJson(uri.toString(), headers: _loginHeaders(now));
    final data = _dig(json, ['data']);
    final key = data is Map ? '${data['qrcode'] ?? ''}' : '';
    if (key.isEmpty) {
      throw MusicApiException.business('kugou', 'qr_key_failed');
    }
    final img = data is Map ? '${data['qrcode_img'] ?? ''}' : '';
    return (key: key, imageBase64: img.isEmpty ? null : img);
  }

  /// 轮询扫码状态。
  ///
  /// 状态码（秒懂）：0 过期 / 1 等待扫码 / 2 待确认 / 4 授权成功（返回 token）。
  Future<({int status, String? cookie})> qrCheck(String key) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final params = <String, dynamic>{
      'dfid': '-',
      'mid': _deviceMid,
      'uuid': '-',
      'appid': _loginAppid,
      'clientver': _clientver,
      'clienttime': now,
      'plat': 4,
      'qrcode': key,
      'srcappid': _srcAppid,
    };
    params['signature'] = _webSign(params);
    final uri = Uri.parse('$_loginBase/v2/get_userinfo_qrcode')
        .replace(queryParameters: params.map((k, v) => MapEntry(k, '$v')));
    final json = await _http.getJson(uri.toString(), headers: _loginHeaders(now));
    final data = _dig(json, ['data']);
    final status = data is Map ? (data['status'] as num?)?.toInt() ?? -1 : -1;
    if (status != 4 || data is! Map) return (status: status, cookie: null);
    // 授权成功：token / userid 由响应体给出，与原有 Cookie 合并成登录态。
    final token = '${data['token'] ?? ''}';
    final userid = '${data['userid'] ?? ''}';
    if (token.isEmpty || userid.isEmpty) return (status: status, cookie: null);
    final base = cookie.trim().isEmpty ? '' : '${cookie.trim()}; ';
    return (status: status, cookie: '${base}userid=$userid; token=$token; mid=$_deviceMid');
  }

  // ── 搜索 ────────────────────────────────────────────────────────────────

  Future<List<MusicSong>> searchSongs(String keywords, {int limit = 20, int offset = 0}) async {
    final pageSize = limit.clamp(1, 20);
    final page = offset ~/ pageSize + 1;
    final json = await _http.getJson(
      _search,
      query: {
        'keyword': keywords,
        'page': page,
        'pagesize': pageSize,
        'userid': '-1',
        'clientver': 2000,
        'platform': 'WebFilter',
        'tag': 'em',
        'filter': 2,
        'iscorrection': 1,
        'privilege_filter': 0,
        'filter_ver': 2,
        'appid': _webAppId,
        'mid': '1',
        'token': '',
      },
    );
    final lists = _dig(json, ['data', 'lists']);
    if (lists is! List) return const [];
    return [
      for (final item in lists)
        if (item is Map<String, dynamic>) _songFromSearch(item),
    ];
  }

  /// 歌单搜索（`/api/v3/search/special`）。
  Future<List<MusicPlaylist>> searchPlaylists(String keywords, {int limit = 12}) async {
    final json = await _http.getJson(
      'http://mobilecdn.kugou.com/api/v3/search/special',
      query: {'format': 'json', 'keyword': keywords, 'page': 1, 'pagesize': limit, 'showtype': 1},
    );
    final info = _dig(json, ['data', 'info']);
    if (info is! List) return const [];
    return [
      for (final item in info)
        if (item is Map<String, dynamic>)
          MusicPlaylist(
            id: '${item['specialid'] ?? ''}',
            name: '${item['specialname'] ?? ''}',
            trackCount: (item['songcount'] as num?)?.toInt() ?? 0,
            seed: '${item['specialname'] ?? ''}',
            playCountValue: (item['playcount'] as num?)?.round(),
            description: '${item['nickname'] ?? ''}',
            coverUrl: normalizeCoverUrl(item['imgurl'] ?? item['img']),
          ),
    ];
  }

  // ── 用户歌单（登录态）────────────────────────────────────────────────────

  /// 用户歌单（H5 网关 `/v7/get_all_list`）：对齐 miao-dock `kugou::user_playlists`。
  ///
  /// 网关签名固定为 `md5(salt + 排序后的 key=value + body + salt)`；缺 token 时
  /// 上游回 `status=0`，这里翻译成空集（平台能力位是「需登录」，不是故障）。
  Future<List<MusicPlaylist>> userPlaylists() async {
    final auth = _parseH5Auth(cookie);
    if (auth == null) return const [];
    final body = jsonEncode({
      'userid': int.tryParse(auth.userId) ?? 0,
      'token': auth.token,
      'total_ver': 979,
      'type': 2,
      'page': 1,
      'pagesize': 50,
    });
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    final params = <String, String>{
      'srcappid': '2919',
      'clientver': '20000',
      'clienttime': now,
      'mid': auth.mid,
      'uuid': now,
      'dfid': auth.dfid,
      'appid': '$_webAppId',
      'token': auth.token,
      'userid': auth.userId,
      'plat': '1',
    };
    final sortedKeys = params.keys.toList()..sort();
    final joined = [for (final k in sortedKeys) '$k=${params[k]}'].join();
    params['signature'] = md5.convert(utf8.encode('$_h5Salt$joined$body$_h5Salt')).toString();
    final json = await _http.dio
        .post<String>(
          '$_gateway/v7/get_all_list',
          queryParameters: params,
          data: body,
          options: Options(responseType: ResponseType.plain, headers: {'x-router': 'cloudlist.service.kugou.com'}),
        )
        .then((r) => r.data);
    final decoded = json == null || json.trim().isEmpty ? null : jsonDecode(json);
    if (decoded is! Map) return const [];
    final status = decoded['status'];
    if (status is String ? status.trim() == '0' : status == 0) return const [];
    final data = decoded['data'];
    final rows = _dig(data, ['info']) ?? _dig(data, ['data', 'info']);
    final lists = <Map<String, dynamic>>[];
    if (rows is List) {
      lists.addAll(rows.whereType<Map<String, dynamic>>());
    } else if (data is Map<String, dynamic>) {
      for (final key in const ['collect', 'love', 'self', 'list']) {
        final arr = data[key];
        if (arr is List) lists.addAll(arr.whereType<Map<String, dynamic>>());
      }
    }
    return [
      for (final item in lists)
        if ('${item['global_collection_id'] ?? item['specialid'] ?? item['listid'] ?? item['id'] ?? ''}'.isNotEmpty)
          MusicPlaylist(
            id: '${item['global_collection_id'] ?? item['specialid'] ?? item['listid'] ?? item['id'] ?? ''}',
            name: _stripHtml('${item['name'] ?? item['listname'] ?? item['specialname'] ?? ''}'),
            trackCount:
                ((item['count'] ?? item['song_count'] ?? item['songcount'] ?? item['total'] ?? 0) as num?)?.toInt() ??
                0,
            seed: _stripHtml('${item['name'] ?? item['listname'] ?? item['specialname'] ?? ''}'),
            description: _stripHtml('${item['nickname'] ?? item['username'] ?? item['list_create_username'] ?? ''}'),
            author: _stripHtml('${item['nickname'] ?? item['username'] ?? ''}').isEmpty
                ? null
                : _stripHtml('${item['nickname'] ?? item['username'] ?? ''}'),
          ),
    ];
  }

  ({String userId, String mid, String token, String dfid})? _parseH5Auth(String raw) {
    if (raw.trim().isEmpty) return null;
    final map = <String, String>{};
    for (final part in raw.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) map[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    // 酷狗把登录信息塞在 KuGoo=<urlencoded k=v&k=v> 里。
    final compound = Uri.decodeQueryComponent(map['KuGoo'] ?? map['kugou'] ?? '');
    final inner = <String, String>{};
    for (final part in compound.split('&')) {
      final i = part.indexOf('=');
      if (i > 0) inner[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = inner[k] ?? map[k];
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    final userId = pick(['KugooID', 'kugouID', 'userid', 'UserId']).replaceAll(RegExp(r'[^0-9]'), '');
    final token = pick(['t', 'token', 'T', 'Token']);
    if (userId.isEmpty || token.isEmpty) return null;
    return (userId: userId, mid: pick(['kg_mid', 'KG_MID']), token: token, dfid: pick(['kg_dfid', 'KG_DFID']));
  }

  /// 榜单清单（`/api/v3/rank/list`）。
  Future<List<MusicPlaylist>> rankList({int limit = 12}) async {
    final json = await _http.getJson(
      'http://mobilecdn.kugou.com/api/v3/rank/list',
      query: {'format': 'json', 'page': 1, 'pagesize': limit, 'withsong': 0},
    );
    final info = _dig(json, ['data', 'info']);
    if (info is! List) return const [];
    return [
      for (final item in info)
        if (item is Map<String, dynamic>)
          MusicPlaylist(
            id: '${item['rankid'] ?? ''}',
            name: '${item['rankname'] ?? ''}',
            trackCount: (item['songcount'] as num?)?.toInt() ?? 0,
            seed: '${item['rankname'] ?? ''}',
            playCountValue: (item['playcount'] as num?)?.round(),
            description: '${item['update_frequency'] ?? ''}',
            coverUrl: normalizeCoverUrl(item['banner7url'] ?? item['imgurl']),
          ),
    ];
  }

  // ── 歌单 / 榜单曲目 ──────────────────────────────────────────────────────

  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(String id) async {
    final json = await _http.getJson(
      'http://mobilecdn.kugou.com/api/v3/special/song',
      query: {'format': 'json', 'specialid': id, 'page': 1, 'pagesize': 50, 'version': 8990},
    );
    final info = _dig(json, ['data', 'info']);
    final meta = _dig(json, ['data']);
    return (
      meta: MusicPlaylist(
        id: id,
        name: meta is Map ? '${meta['specialname'] ?? ''}' : '',
        trackCount: info is List ? info.length : 0,
        seed: meta is Map ? '${meta['specialname'] ?? ''}' : '',
        description: meta is Map ? '${meta['intro'] ?? ''}' : '',
      ),
      songs: <MusicSong>[
        if (info is List)
          for (final item in info)
            if (item is Map<String, dynamic>) _songFromV3(item),
      ],
    );
  }

  Future<({MusicPlaylist meta, List<MusicSong> songs})> rankDetail(String id) async {
    final json = await _http.getJson(
      'http://mobilecdn.kugou.com/api/v3/rank/song',
      query: {'format': 'json', 'rankid': id, 'page': 1, 'pagesize': 50, 'version': 8990},
    );
    final info = _dig(json, ['data', 'info']);
    // rank/song 只给曲目，没有榜单名与封面 —— 从 rank/list 里按 id 取回元数据。
    final meta = await _rankMeta(id);
    return (
      meta: MusicPlaylist(
        id: id,
        name: meta?.name ?? '',
        trackCount: info is List ? info.length : 0,
        seed: meta?.name ?? '',
        description: meta?.description ?? '',
        coverUrl: meta?.coverUrl,
      ),
      songs: <MusicSong>[
        if (info is List)
          for (final item in info)
            if (item is Map<String, dynamic>) _songFromV3(item),
      ],
    );
  }

  /// 按 id 从榜单清单里取元数据（名称 / 说明 / 封面）；失败返回 null，不打断详情。
  Future<MusicPlaylist?> _rankMeta(String id) async {
    try {
      final all = await rankList(limit: 100);
      for (final p in all) {
        if (p.id == id) return p;
      }
    } on Object {
      // 榜单清单失败不影响曲目展示，只是没有标题与封面。
    }
    return null;
  }

  // ── 歌词 ────────────────────────────────────────────────────────────────

  /// 歌词（`krcs.kugou.com` 两段式：search 拿候选 id + accesskey，download 取 krc 文本）。
  Future<SongLyrics> lyric({required String hash, required int durationSec}) async {
    if (hash.trim().isEmpty) return const SongLyrics(lines: []);
    final found = await _http.getJson(
      _lyricSearch,
      query: {'ver': 1, 'man': 'yes', 'client': 'pc', 'keyword': '', 'duration': durationSec, 'hash': hash},
    );
    final candidates = _dig(found, ['candidates']);
    if (candidates is! List || candidates.isEmpty) return const SongLyrics(lines: []);
    final first = candidates.first;
    if (first is! Map<String, dynamic>) return const SongLyrics(lines: []);
    final id = '${first['id'] ?? ''}';
    final accesskey = '${first['accesskey'] ?? ''}';
    if (id.isEmpty) return const SongLyrics(lines: []);
    final json = await _http.getJson(
      _lyricDownload,
      query: {'ver': 1, 'client': 'pc', 'id': id, 'accesskey': accesskey, 'fmt': 'lrc', 'charset': 'utf8'},
    );
    final content = _dig(json, ['content']);
    if (content is! String || content.isEmpty) return const SongLyrics(lines: []);
    final text = utf8.decode(base64.decode(content.replaceAll(RegExp(r'\s'), '')));
    return parseLrc(text);
  }

  // ── 播放地址（需要登录态）─────────────────────────────────────────────────

  /// H5 网关 `/v5/url`：需要 userid / mid / token 才能算 key 签名。
  Future<String?> songUrl(String hash, {required String albumId, required String albumAudioId}) async {
    final auth = _parseAuth(cookie);
    if (auth == null || hash.isEmpty) return null;
    final params = <String, String>{
      'appid': '$_webAppId',
      'clientver': '20000',
      'clienttime': '${DateTime.now().millisecondsSinceEpoch}',
      'mid': auth.mid,
      'userid': auth.userId,
      'uuid': '-',
      'dfid': '-',
      'album_id': albumId,
      'area_code': '1',
      'hash': hash.toLowerCase(),
      'ssa_flag': 'is_fromtrack',
      'version': '11430',
      'quality': '128',
      'album_audio_id': albumAudioId,
      'behavior': 'play',
      'pid': '2',
      'cmd': '26',
      'pidversion': '3001',
      'IsFreePart': '1',
      'cdnBackup': '1',
      'module': '',
    };
    params['key'] = md5.convert(utf8.encode('$hash$_signSalt$_webAppId${auth.mid}${auth.userId}')).toString();
    final sigSource =
        '$_h5Salt${(params.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join()}$_h5Salt';
    params['signature'] = md5.convert(utf8.encode(sigSource)).toString();
    final json = await _http.getJson('$_gateway/v5/url', query: params);
    final url = _dig(json, ['url']);
    if (url is List && url.isNotEmpty && url.first is String) {
      final s = url.first as String;
      return s.isEmpty ? null : s;
    }
    return null;
  }

  ({String userId, String mid, String token})? _parseAuth(String raw) {
    if (raw.isEmpty) return null;
    final map = <String, String>{};
    for (final part in raw.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) map[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    final userId = map['userid'] ?? map['UserId'] ?? '';
    final mid = map['mid'] ?? map['KugouID'] ?? '';
    final token = map['token'] ?? map['t'] ?? '';
    if (token.isEmpty || userId.isEmpty) return null;
    return (userId: userId, mid: mid.isEmpty ? '1' : mid, token: token);
  }

  // ── 映射 ────────────────────────────────────────────────────────────────

  MusicSong _songFromSearch(Map<String, dynamic> item) {
    final hash = '${item['FileHash'] ?? ''}'.toLowerCase();
    final durationSec = (item['Duration'] as num?)?.toInt() ?? 0;
    return MusicSong(
      id: hash,
      title: _stripHtml('${item['SongName'] ?? item['FileName'] ?? ''}'),
      artist: _stripHtml('${item['SingerName'] ?? ''}'),
      album: _stripHtml('${item['AlbumName'] ?? ''}'),
      duration: Duration(seconds: durationSec),
      platform: MusicPlatform.kugou,
      qualityLabel: _kugouQuality(item),
      coverUrl: _coverFromItem(item),
      mediaId: '${item['MixSongID'] ?? item['AlbumID'] ?? ''}',
    );
  }

  /// v3 接口的字段是 snake_case（`filename` 形如 `歌手 - 歌名`）。
  MusicSong _songFromV3(Map<String, dynamic> item) {
    final filename = '${item['filename'] ?? ''}';
    final dash = filename.indexOf(' - ');
    final artist = dash > 0 ? filename.substring(0, dash) : '${item['singername'] ?? ''}';
    final title = dash > 0 ? filename.substring(dash + 3) : filename;
    final durationSec = (item['duration'] as num?)?.toInt() ?? 0;
    return MusicSong(
      id: '${item['hash'] ?? ''}'.toLowerCase(),
      title: _stripHtml(title),
      artist: _stripHtml(artist),
      album: _stripHtml('${item['album_name'] ?? ''}'),
      duration: Duration(seconds: durationSec),
      platform: MusicPlatform.kugou,
      qualityLabel: null,
      coverUrl: _coverFromItem(item),
      mediaId: '${item['album_audio_id'] ?? item['album_id'] ?? ''}',
    );
  }

  /// 搜索结果的封面有三个来源（miao-dock 同口径）：
  /// 顶层 `Image` / `AlbumImage` → `albuminfo.img` → `trans_param.union_cover`。
  /// 只取第一处会漏掉相当一部分老歌。
  static String? _coverFromItem(Map<String, dynamic> item) {
    for (final key in const ['Image', 'AlbumImage', 'cover', 'album_cover', 'img']) {
      final v = _coverUrl('${item[key] ?? ''}');
      if (v != null) return v;
    }
    final info = item['albuminfo'];
    if (info is Map) {
      for (final key in const ['img', 'cover', 'sizable_cover']) {
        final v = _coverUrl('${info[key] ?? ''}');
        if (v != null) return v;
      }
    }
    final trans = item['trans_param'];
    if (trans is Map) {
      final v = _coverUrl('${trans['union_cover'] ?? ''}');
      if (v != null) return v;
    }
    return null;
  }

  /// 酷狗封面占位符 `{size}` 替换成 300（接口给的是模板串）。
  static String? _coverUrl(String raw) => normalizeCoverUrl(raw);

  static String? _kugouQuality(Map<String, dynamic> m) {
    final sq = '${m['SQFileHash'] ?? ''}';
    final hq = '${m['HQFileHash'] ?? ''}';
    if (sq.isNotEmpty) return 'lossless';
    if (hq.isNotEmpty) return '320K';
    return null;
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>');

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
