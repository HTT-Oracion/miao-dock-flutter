import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/domain/music_models.dart';
import 'package:miao_dock_flutter/features/music/data/sources/js/music_source_dto.dart';

/// 音乐源 JSON → 领域模型。字段形状取自真实接口响应（脱敏截取）。
///
/// 破坏点：映射错字段（ar/artists、dt/duration 混淆）→ 列表显示空 / 时长 0。
void main() {
  const dto = MusicSourceDto(platform: MusicPlatform.netease);

  test('搜索歌曲：归一化契约字段映射', () {
    // JS 源负责把平台字段（ar/al/dt）映射成契约字段；DTO 只认契约。
    final raw = {
      'songs': [
        {
          'id': '5257138',
          'title': '屋顶',
          'artist': '周杰伦 / 温岚',
          'album': '有点野',
          'durationMs': 319039,
          'coverUrl': 'http://p1.music.126.net/abc.jpg',
        },
      ],
    };
    final songs = dto.songs(raw);
    expect(songs.length, 1);
    final s = songs.first;
    expect(s.id, '5257138');
    expect(s.title, '屋顶');
    expect(s.artist, '周杰伦 / 温岚');
    expect(s.album, '有点野');
    expect(s.duration.inMilliseconds, 319039);
    expect(s.coverUrl, 'http://p1.music.126.net/abc.jpg');
    expect(s.platform, MusicPlatform.netease);
  });

  test('平台原始字段不进 DTO：映射职责在 JS 源', () {
    // 破坏点：DTO 兼容 ar/dt → 边界失效，源作者会以为不用做映射。
    final raw = {
      'songs': [
        <String, dynamic>{
          'id': 1,
          'name': '旧歌',
          'artists': <Map<String, dynamic>>[],
          'album': <String, dynamic>{},
          'dt': 200000,
        },
      ],
    };
    final songs = dto.songs(raw);
    expect(songs.first.title, isEmpty, reason: 'name/dt 是平台字段，DTO 不认');
  });

  test('脏数据条目跳过不炸整批', () {
    final raw = {
      'songs': [
        <String, dynamic>{'id': 1, 'title': '好歌', 'artist': '甲', 'album': '专辑', 'durationMs': 1},
        'not-a-map',
        <String, dynamic>{'id': 2, 'title': '第二首', 'artist': '乙', 'album': '', 'durationMs': 2},
      ],
    };
    final songs = dto.songs(raw);
    // 破坏点：一条脏数据抛异常 → 整个列表挂掉。
    expect(songs.length, 2);
    expect(songs.first.title, '好歌');
  });

  test('歌单映射：seed 缺省用歌单名', () {
    final raw = {
      'playlists': [
        {
          'id': '9',
          'name': '华语速爆新歌',
          'trackCount': 30,
          'playCountValue': 123456,
          'coverUrl': 'http://x/y.jpg',
          'author': '编辑推荐',
        },
      ],
    };
    final pl = dto.playlists(raw).first;
    expect(pl.id, '9');
    expect(pl.name, '华语速爆新歌');
    expect(pl.trackCount, 30);
    expect(pl.seed, '华语速爆新歌');
    expect(pl.playCountValue, 123456);
    expect(pl.author, '编辑推荐');
  });

  test('榜单映射：top 三态趋势', () {
    final raw = {
      'charts': [
        {
          'id': '1',
          'name': '飙升榜',
          'updateMeta': '每30分钟更新',
          'top': [
            <String, dynamic>{'title': 'A', 'artist': '甲', 'trend': 'up'},
            <String, dynamic>{'title': 'B', 'artist': '乙', 'trend': 'new'},
            <String, dynamic>{'title': 'C', 'artist': '丙'},
          ],
        },
      ],
    };
    final charts = dto.charts(raw);
    expect(charts.first.name, '飙升榜');
    expect(charts.first.top.map((t) => t.trend), [ChartTrend.up, ChartTrend.newEntry, ChartTrend.flat]);
  });

  test('详情：meta + songs', () {
    final raw = {
      'meta': <String, dynamic>{'id': '5', 'name': '歌单名', 'trackCount': 2},
      'songs': [
        <String, dynamic>{
          'id': 1,
          'name': '一',
          'artists': <Map<String, dynamic>>[],
          'album': <String, dynamic>{},
          'dt': 1000,
        },
        <String, dynamic>{
          'id': 2,
          'name': '二',
          'artists': <Map<String, dynamic>>[],
          'album': <String, dynamic>{},
          'dt': 2000,
        },
      ],
    };
    final d = dto.detail(raw);
    expect(d.meta.name, '歌单名');
    expect(d.songs.length, 2);
  });

  test('歌词：原始 LRC 文本 + 翻译轨按时间对齐', () {
    final raw = {
      'lrc': '[00:01.00]第一句\n[00:04.00]第二句\n[00:08.50]第三句',
      'translation': '[00:01.10]line one\n[00:08.60]line three',
    };
    final lyrics = dto.lyrics(raw);
    expect(lyrics.lines.length, 3);
    expect(lyrics.hasTranslation, isTrue);
    expect(lyrics.lines.first.text, '第一句');
    expect(lyrics.lines.first.translation, 'line one');
    // 第三句与翻译轨 8.6s 相差 0.1s，应配上 line three。
    expect(lyrics.lines.last.translation, 'line three');
  });

  test('歌词：结构化 lines 形状直通', () {
    final raw = {
      'lines': [
        {'t': 1500, 'text': '甲'},
        {'t': 500, 'text': '乙'},
      ],
    };
    final lyrics = dto.lyrics(raw);
    expect(lyrics.lines.map((l) => l.text).toList(), ['乙', '甲'], reason: 'lines 应按时间排序');
    expect(lyrics.hasTranslation, isFalse);
  });

  test('评论映射', () {
    final raw = {
      'comments': [
        {
          'commentId': 7,
          'user': {'nickname': '路人'},
          'content': '好听',
          'timeStr': '2026/01/01',
          'likedCount': 88,
        },
      ],
    };
    final comments = dto.comments(raw);
    expect(comments.first.id, '7');
    expect(comments.first.nick, '路人');
    expect(comments.first.likes, 88);
  });
}
