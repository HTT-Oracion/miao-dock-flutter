import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';
import 'package:miao_dock_flutter/features/music/ui/views/discover_view.dart';
import 'package:miao_dock_flutter/features/music/ui/widgets/music_shared.dart';
import 'package:miao_dock_flutter/features/music/ui/widgets/song_row.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

import 'support/demo_music_repository.dart';
import 'support/music_test_account.dart';

/// 封面必须真的进到 UI：真实接口给的 coverUrl 要透传到每一处封面组件。
///
/// 破坏点：
/// · SongRow 桌面端退回「只有序号没有封面」→ 桌面封面断言失败；
/// · 歌单行 / 队列行漏传 imageUrl → 对应断言失败（SeedCover.imageUrl 为 null）；
/// · 模型没带 coverUrl → 第一层断言直接失败。
void main() {
  Widget host(Widget child, {Size size = const Size(1440, 900)}) => ProviderScope(
    overrides: [
      musicRepositoryProvider.overrideWithValue(DemoMusicRepository()),
      musicAccountProvider.overrideWith(LoggedInMusicAccount.new),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );

  const song = MusicSong(
    id: 'x1',
    title: '有封面',
    artist: '歌手',
    album: '专辑',
    duration: Duration(seconds: 200),
    platform: MusicPlatform.netease,
    coverUrl: 'https://example.invalid/cover.jpg',
  );

  testWidgets('桌面歌曲行也渲染封面（不是只有移动端）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(SizedBox(width: 900, child: SongRow(song: song, index: 0))));
    await tester.pump();

    final cover = tester.widget<SeedCover>(find.byType(SeedCover).first);
    // 破坏点：桌面分支不渲染 SeedCover → findsNothing 或 imageUrl 为空。
    expect(cover.imageUrl, 'https://example.invalid/cover.jpg');
  });

  testWidgets('曲目表每行都带封面（推荐 / 详情 / 本地共用）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(SizedBox(width: 900, height: 600, child: MusicSongTable(songs: const [song]))));
    await tester.pump();

    final covers = tester.widgetList<SeedCover>(find.byType(SeedCover)).toList();
    // 破坏点：MusicSongTable 不把 coverUrl 传下去 → 列表里没有带 imageUrl 的封面。
    expect(covers.where((c) => c.imageUrl == 'https://example.invalid/cover.jpg'), isNotEmpty);
  });

  testWidgets('歌单瓦片把 coverUrl 传给封面组件', (tester) async {
    const playlist = MusicPlaylist(
      id: 'p1',
      name: '带封面的歌单',
      trackCount: 10,
      seed: 'p1',
      coverUrl: 'https://example.invalid/pl.jpg',
      playCountValue: 12000,
    );
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(SizedBox(width: 200, child: MusicPlaylistTile(playlist: playlist))));
    await tester.pump();

    final cover = tester.widget<SeedCover>(find.byType(SeedCover).first);
    // 破坏点：瓦片漏传 imageUrl → 只剩渐变占位。
    expect(cover.imageUrl, 'https://example.invalid/pl.jpg');
  });
}
