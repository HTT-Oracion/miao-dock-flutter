import 'package:flutter_test/flutter_test.dart';

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
    // 没有图就留空，由 UI 回落渐变（不能编造地址）。
    expect(none.coverUrl, isEmpty);
  });
}
