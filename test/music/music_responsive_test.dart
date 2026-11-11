import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/music/ui/mobile/mobile_music_screen.dart';
import 'package:miao_dock_flutter/features/music/ui/music_screen.dart';
import 'package:miao_dock_flutter/features/music/ui/views/music_detail.dart';
import 'package:miao_dock_flutter/features/music/ui/widgets/song_row.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 音乐模块的窄屏断言（AGENTS §4.16：390×844 至少一条「窄屏不该出现的没出现」）。
///
/// 破坏点：
/// · 移动端行高退回 34（触控热区不足）→ 行高断言失败；
/// · 移动端仍渲染桌面序号列 / 专辑列 → 宽度布局断言失败；
/// · 移动容器渲染底部一级导航（壳层职责）→ 存在性断言失败。
void main() {
  Widget host(Widget child, {Size size = const Size(390, 844), bool reduceMotion = false}) => ProviderScope(
    child: MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: reduceMotion),
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );

  testWidgets('390×844：移动容器渲染且不含桌面播放条', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const MobileMusicScreen(view: MusicScreenView.discover)));
    await tester.pump(const Duration(milliseconds: 200));

    // 破坏点：把桌面 MusicScreen 塞进窄屏 → 这条失败。
    expect(find.byType(MobileMusicScreen), findsOneWidget);
    expect(find.byType(MusicScreen), findsNothing);
    // 底部导航属于壳层：容器不得渲染。
    expect(find.text('设置'), findsNothing);
  });

  testWidgets('移动端歌曲行高 48、桌面 34（触控热区 M08）', (tester) async {
    const song = MusicSong(
      id: 'x',
      title: 't',
      artist: 'a',
      album: 'al',
      duration: Duration(seconds: 100),
      platform: MusicPlatform.netease,
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(host(SongRow(song: song, index: 0)));
    await tester.pump();
    // 破坏点：移动端行高退回 34 → 断言失败。
    expect(tester.getSize(find.byType(SongRow)).height, 48);
    tester.view.reset();

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(host(SongRow(song: song, index: 0), size: const Size(1280, 800)));
    await tester.pump();
    expect(tester.getSize(find.byType(SongRow)).height, 34);
    tester.view.reset();
  });

  testWidgets('桌面 sm（880）隐藏专辑列，表头与行同步（N32）', (tester) async {
    tester.view.physicalSize = const Size(880, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        const MusicDetailScreen(kind: MusicSourceKind.playlist, id: 'p1'),
        size: const Size(880, 800),
      ),
    );
    await tester.pump(const Duration(milliseconds: 240));
    final l10n = AppLocalizations.of(tester.element(find.byType(MusicDetailScreen)));
    // 破坏点：只在行上隐藏专辑、表头仍渲染 → 表头有「专辑」而行没有，列宽错位。
    expect(find.text(l10n.musicAlbumTag), findsNothing);
  });

  testWidgets('减少动态效果：魔法阵 / 波形不排新帧（不旋转）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const MobileMusicScreen(view: MusicScreenView.discover), reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 200));
    // 有动画时 pumpAndSettle 会超时；关闭动效后应能直接 settle。
    // 破坏点：去掉 reduceMotion 分支 → 这里超时抛出。
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(MobileMusicScreen), findsOneWidget);
  });
}
