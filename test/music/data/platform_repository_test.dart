import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/controller/music_auth.dart';
import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';
import 'package:miao_dock_flutter/features/music/data/music_repository.dart';
import 'package:miao_dock_flutter/features/music/data/platform_music_repository.dart';
import 'package:miao_dock_flutter/features/music/data/sources/music_source.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';

/// 线上仓库的**路由与降级**（不联网：用内存 Fake 音源替换平台客户端）。
///
/// 破坏点：
/// · 能力位判断被删 → 「不支持每日推荐」的断言失败；
/// · 推荐歌单为空时没有回退榜单 → 首页空区块断言失败；
/// · 平台异常没有映射成 [MusicRepositoryException] → 错误码断言失败。
MusicSong _song(String id, {String? mid}) => MusicSong(
  id: id,
  title: 't-$id',
  artist: 'a',
  album: 'al',
  duration: const Duration(seconds: 100),
  platform: MusicPlatform.netease,
  mediaId: mid,
);

void main() {
  test('运行时音乐仓库固定装配真实平台实现', () {
    final container = ProviderContainer(overrides: [musicAuthProvider.overrideWith(_NoAuth.new)]);
    addTearDown(container.dispose);
    expect(container.read(musicRepositoryProvider), isA<PlatformMusicRepository>());
  });

  test('详情缺封面时用列表元数据回填（酷狗/QQ 详情只给曲目）', () async {
    final source = _FakeSource(chartCount: 2);
    final repo = PlatformMusicRepository(platform: MusicPlatform.kugou, source: source);

    // 先走列表（缓存元数据），再取详情。
    await repo.recommendedPlaylists();
    final detail = await repo.sourceDetail(MusicSourceKind.chart, 'c0');

    // 破坏点：不做回填 → 详情 meta.coverUrl 为 null，详情页整页没有封面。
    expect(detail.meta.coverUrl, source.chartCover);
    expect(detail.meta.name, isNotEmpty);
  });

  test('推荐歌单走平台实现；空结果回退榜单清单', () async {
    final source = _FakeSource(recommend: const [], chartCount: 3);
    final repo = PlatformMusicRepository(platform: MusicPlatform.kugou, source: source);
    final list = await repo.recommendedPlaylists();
    expect(list.length, 3);
    expect(list.first.id, 'c0');
  });

  test('每日推荐：平台不支持时返回空集而不是抛错', () async {
    final repo = PlatformMusicRepository(platform: MusicPlatform.qq, source: _FakeSource());
    expect(await repo.dailySongs(), isEmpty);
  });

  test('评论：平台不支持时返回空集', () async {
    final repo = PlatformMusicRepository(platform: MusicPlatform.migu, source: _FakeSource());
    expect(await repo.comments('x'), isEmpty);
  });

  test('榜单卡组装 Top3；单张取详情失败只丢该卡 Top3，不影响其他卡', () async {
    final source = _FakeSource(chartCount: 2, failingChartId: 'c1');
    final repo = PlatformMusicRepository(platform: MusicPlatform.netease, source: source);
    final charts = await repo.charts();
    expect(charts.length, 2);
    expect(charts.first.top.length, 3);
    expect(charts.last.top, isEmpty);
  });

  test('平台异常映射成仓库错误（网络类 → network）', () async {
    final repo = PlatformMusicRepository(platform: MusicPlatform.netease, source: _FakeSource(failSearch: true));
    await expectLater(
      repo.search('x'),
      throwsA(isA<MusicRepositoryException>().having((e) => e.code, 'code', MusicRepositoryErrorCode.network)),
    );
  });

  test('歌词：首次同步读为空、loadLyrics 后缓存命中', () async {
    final repo = PlatformMusicRepository(platform: MusicPlatform.netease, source: _FakeSource());
    final s = _song('1');
    expect(repo.lyricsFor(s).lines, isEmpty);
    final loaded = await repo.loadLyrics(s);
    expect(loaded.lines, isNotEmpty);
    expect(repo.lyricsFor(s).lines.length, loaded.lines.length);
  });

  test('故障注入：指定 scope 抛 network，重置后恢复', () async {
    final repo = PlatformMusicRepository(platform: MusicPlatform.netease, source: _FakeSource());
    repo.setFailScope(FailScope.search, true);
    await expectLater(repo.search('x'), throwsA(isA<MusicRepositoryException>()));
    repo.resetFailScopes();
    expect((await repo.search('x')).songs, isNotEmpty);
  });
}

class _NoAuth extends MusicAuthNotifier {
  @override
  MusicAuthState build() => const MusicAuthState(loading: false);
}

class _FakeSource implements MusicSource {
  _FakeSource({this.recommend = const [], this.chartCount = 3, this.failingChartId, this.failSearch = false});

  /// 榜单清单返回的封面（详情接口故意不给，用于验证回填）。
  final String chartCover = 'https://example.invalid/chart.jpg';

  final List<MusicPlaylist> recommend;
  final int chartCount;
  final String? failingChartId;
  final bool failSearch;

  @override
  MusicPlatform get platform => MusicPlatform.netease;

  @override
  bool get supportsDailySongs => false;

  @override
  bool get supportsComments => false;

  @override
  bool get supportsRecommendPlaylists => recommend.isNotEmpty;

  @override
  bool get supportsSimilarSongs => true;

  @override
  Future<List<MusicSong>> searchSongs(String keywords, {int limit = 30, int offset = 0}) async {
    if (failSearch) throw StateError('boom');
    return [_song('s1')];
  }

  @override
  Future<List<MusicPlaylist>> searchPlaylists(String keywords, {int limit = 12}) async => const [];

  @override
  Future<List<MusicPlaylist>> recommendedPlaylists({int limit = 6}) async => recommend;

  @override
  Future<List<MusicPlaylist>> userPlaylists() async => const [];

  @override
  Future<List<({String id, String name, String updateMeta, String? coverUrl})>> charts() async => [
    for (var i = 0; i < chartCount; i++) (id: 'c$i', name: 'chart $i', updateMeta: 'daily', coverUrl: chartCover),
  ];

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> playlistDetail(String id) async =>
      (meta: MusicPlaylist(id: id, name: 'pl', trackCount: 1, seed: 'pl'), songs: [_song('s1')]);

  @override
  Future<({MusicPlaylist meta, List<MusicSong> songs})> chartDetail(String id) async {
    if (id == failingChartId) throw StateError('chart $id unavailable');
    return (
      meta: MusicPlaylist(id: id, name: 'chart', trackCount: 3, seed: 'chart'),
      songs: [_song('a'), _song('b'), _song('c')],
    );
  }

  @override
  Future<List<MusicSong>> dailySongs() async => [_song('d1')];

  @override
  Future<List<MusicSong>> similarSongs(MusicSong seed, {int limit = 20}) async => [_song('similar')];

  @override
  Future<List<MusicComment>> comments(String songId, {int limit = 20, int offset = 0}) async => const [];

  @override
  Future<SongLyrics> lyrics(MusicSong song) async => const SongLyrics(lines: [LyricLine(t: 0, text: 'line')]);

  @override
  Future<String?> songUrl(MusicSong song, QualityTier quality) async => 'https://example/audio.mp3';
}
