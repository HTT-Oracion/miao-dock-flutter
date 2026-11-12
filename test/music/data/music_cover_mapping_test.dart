import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/data/api/migu_api.dart';
import 'package:miao_dock_flutter/features/music/data/api/qqmusic_api.dart';

/// 封面字段映射：真实接口的图字段散落在多处，只取第一处会漏掉大量老数据。
///
/// 破坏点：
/// · 「我喜欢」不返回固定封面 → 列表里那张卡永远渐变占位；
/// · 只认 `logo` 不认 `diss_cover` / `picurl` → 部分歌单没图。
void main() {
  test('QQ「我喜欢」歌单用平台固定封面', () {
    final p = QqMusicApi.userPlaylistFromMap({
      'dirid': 201,
      'diss_name': '我喜欢',
      'dissid': '201',
      'logo': '',
      'song_cnt': 12,
    }, subscribed: false);

    expect(p.special, isTrue);
    // 破坏点：改为透传空串 → 这条失败。
    expect(p.coverUrl, contains('cover_like.png'));
  });

  test('QQ 普通歌单按 logo → picurl → diss_cover 顺序取封面', () {
    final onlyCover = QqMusicApi.userPlaylistFromMap({
      'dirid': 5,
      'diss_name': '某歌单',
      'dissid': '77',
      'diss_cover': 'https://example.invalid/d.jpg',
    }, subscribed: false);
    expect(onlyCover.coverUrl, 'https://example.invalid/d.jpg');

    final none = QqMusicApi.userPlaylistFromMap({'dirid': 6, 'diss_name': '无图歌单', 'dissid': '78'}, subscribed: false);
    // 没有图就是 null（规范化后空串归一为 null），由 UI 回落渐变，不编造地址。
    expect(none.coverUrl, isNull);
  });

  test('咪咕歌单广场卡片：txt / img / logEvent.contentId 能解析出封面', () {
    final p = MiguApi.playlistFromNode({
      'txt': '欧美精选：播放即心动',
      'img': 'https://d.musicapp.migu.cn/data/oss/x.jpeg',
      'view': 'ZJ-SongList-Item',
      'logEvent': {'contentId': '237306957', 'contentType': '2021'},
    });

    // 破坏点：只认旧的 playlistId / playlistName → 解析为 null，推荐歌单整块没封面。
    expect(p, isNotNull);
    expect(p!.id, '237306957');
    expect(p.name, '欧美精选：播放即心动');
    expect(p.coverUrl, 'https://d.musicapp.migu.cn/data/oss/x.jpeg');
  });
}
