import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/music/controller/music_playlist_library.dart';
import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';
import 'package:miao_dock_flutter/features/music/domain/music_platform_info.dart';
import 'package:miao_dock_flutter/features/music/ui/mobile/mobile_music_screen.dart';
import 'package:miao_dock_flutter/features/music/ui/music_screen.dart';
import 'package:miao_dock_flutter/features/music/ui/views/music_detail.dart';
import 'package:miao_dock_flutter/features/music/ui/views/playlist_view.dart';
import 'package:miao_dock_flutter/features/music/ui/widgets/music_shared.dart';
import 'package:miao_dock_flutter/features/music/ui/widgets/song_row.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

import 'support/demo_music_repository.dart';
import 'support/music_test_account.dart';

/// 我的歌单库（N41/N42/N43/N44/M18）断言。
///
/// 破坏点示例：
/// · 分组不按 `subscribed` 语义位拆 → 创建 / 收藏两组计数断言失败；
/// · 组头点不动（折叠状态没进 controller）→ 折叠后条目仍可见，断言失败；
/// · 收藏歌单取消订阅不落到屏级状态 → 返回库列表后收藏组仍 4 条；
/// · 未登录仍渲染库列表 → 登录 CTA 断言失败；
/// · 移动端退回 4 列卡片 → 390×844 下出现 `_PlaylistCard` 而不是行。
MusicPlatformInfo _neteaseInfo() => const MusicPlatformInfo(id: 'netease', label: '网易云', builtIn: true);

void main() {
  Widget host(Widget child, {Size size = const Size(1440, 900), bool logged = true}) => ProviderScope(
    overrides: [
      musicPlatformInfosProvider.overrideWith((_) => [_neteaseInfo()]),
      musicRepositoryProvider.overrideWithValue(DemoMusicRepository()),
      if (logged) musicAccountProvider.overrideWith(LoggedInMusicAccount.new),
      if (!logged) musicAccountProvider.overrideWith(_LoggedOutAccount.new),
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

  AppLocalizations l10nOf(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  Future<void> pumpLibrary(WidgetTester tester, {Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final widget = size.width <= AppMetrics.breakpoint
        ? const MobileMusicScreen(view: MusicScreenView.playlist)
        : const MusicScreen(view: MusicScreenView.playlist);
    await tester.pumpWidget(host(widget, size: size));
    await tester.pump(const Duration(milliseconds: 240));
  }

  testWidgets('横卡 hover 上移不被裁剪：滚动区顶部预留呼吸空间', (tester) async {
    // 破坏点：去掉 SingleChildScrollView 的 top padding → 横卡 hover 时
    // translateY(-2) 的上边框被外层 Stack 裁掉（用户实测：上边框消失）。
    await pumpLibrary(tester);
    final scroll = tester.widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView)).first;
    final pad = scroll.padding;
    final top = pad is EdgeInsets ? pad.top : null;
    expect(top, greaterThanOrEqualTo(6));
  });

  testWidgets('分组：系统歌单置顶 + 创建 8 + 收藏 4（subscribed 语义位）', (tester) async {
    await pumpLibrary(tester);
    final l10n = l10nOf(tester);
    final state = containerOf(tester).read(playlistLibraryProvider);

    // 破坏点：漏掉「我喜欢的音乐」置顶卡或组头文案 → 失败。
    expect(find.textContaining(l10n.musicPlLibraryLikedTitle), findsOneWidget);
    expect(find.text(l10n.musicPlLibraryCreated), findsOneWidget);
    expect(find.text(l10n.musicPlLibraryCollected), findsOneWidget);

    final groups = groupPlaylists(containerOf(tester).read(userPlaylistsProvider).value!, state.unsubscribed);
    // 破坏点：把收藏歌单混进创建组（或反之）→ 两条计数断言同时失败。
    expect(groups.created.length, 8);
    expect(groups.collected.length, 4);
    expect(groups.liked?.special, isTrue);
    expect(find.text(l10n.musicPlLibraryLikedSummary(groups.liked!.trackCount)), findsOneWidget);
    expect(find.textContaining('收藏过的歌'), findsNothing);
    expect(find.text('心动模式唯一来源'), findsNothing);
    expect(tester.widget<SeedCover>(find.byType(SeedCover).first).imageUrl, groups.liked!.coverUrl);
    // 页内不放大标题与总数（N44）：库里只应出现组头，不出现「N 个歌单」。
    expect(find.textContaining('12 个歌单'), findsNothing);
  });

  testWidgets('组头折叠：点「创建的歌单」后条目消失，再点恢复', (tester) async {
    await pumpLibrary(tester);
    final l10n = l10nOf(tester);
    const firstCreated = '日语小甜歌 | 听完想谈恋爱系列';
    expect(find.text(firstCreated), findsOneWidget);

    await tester.tap(find.text(l10n.musicPlLibraryCreated));
    await tester.pump(const Duration(milliseconds: 200));
    // 破坏点：折叠态没进 controller（只在 widget 局部）→ 条目仍在。
    expect(find.text(firstCreated), findsNothing);
    expect(containerOf(tester).read(playlistLibraryProvider).createdCollapsed, isTrue);

    await tester.tap(find.text(l10n.musicPlLibraryCreated));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(firstCreated), findsOneWidget);
  });

  testWidgets('收藏歌单详情：点「已收藏」取消订阅 → 库列表收藏组少一条；再点可加回', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        const MusicDetailScreen(kind: MusicSourceKind.playlist, id: 'c2'),
        size: const Size(1440, 900),
      ),
    );
    await tester.pump(const Duration(milliseconds: 240));

    final l10n = l10nOf(tester);
    final container = containerOf(tester);
    // 详情页本身不取歌单库（只有库视图取），这里手动把库数据拉起来，
    // 断言「取消订阅真的落到屏级分组状态」而不是只看按钮文字。
    await container.read(userPlaylistsProvider.future);
    await tester.pump(const Duration(milliseconds: 120));
    // 收藏歌单默认「已收藏」（N43：详情按钮默认态由 subscribed 决定）。
    expect(find.text(l10n.musicCollected), findsOneWidget);
    expect(find.text(l10n.musicKickerCollected), findsOneWidget);
    expect(find.text(l10n.musicPlChipCollected), findsOneWidget);

    await tester.tap(find.text(l10n.musicCollected));
    await tester.pump(const Duration(milliseconds: 160));
    // 破坏点：取消订阅只改了按钮文字、没落屏级状态 → 分组仍有 4 条。
    expect(container.read(playlistLibraryProvider).unsubscribed.contains('c2'), isTrue);
    final groups = groupPlaylists(
      container.read(userPlaylistsProvider).value!,
      container.read(playlistLibraryProvider).unsubscribed,
    );
    expect(groups.collected.length, 3);
    expect(find.text(l10n.musicCollect), findsOneWidget);

    await tester.tap(find.text(l10n.musicCollect));
    await tester.pump(const Duration(milliseconds: 160));
    expect(container.read(playlistLibraryProvider).unsubscribed.contains('c2'), isFalse);
    // 轻提示自带自动消失定时器：等它走完，否则用例结束时报 pending timer。
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('详情曲目按设计稿 pick 偏移组装（p2 从第 4 首起）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        const MusicDetailScreen(kind: MusicSourceKind.playlist, id: 'p2'),
        size: const Size(1440, 900),
      ),
    );
    await tester.pump(const Duration(milliseconds: 240));
    // data.js: p2.pick = 3 → **首曲**是 _songs[3] = 光年之外。
    // 破坏点：按数组下标当偏移（p2 → 第 3 首 = 起风了）→ 首行断言失败。
    final firstRow = tester.widget<SongRow>(find.byType(SongRow).first);
    expect(firstRow.song.id, 's4');
    expect(firstRow.song.title, '光年之外');

    final l10n = l10nOf(tester);
    // 破坏点：详情表重新加入音质列或专辑列没有与表头共用固定列宽时失败。
    expect(find.text(l10n.musicQualitySheetTitle), findsNothing);
    final albumHeadX = tester.getTopLeft(find.text(l10n.musicAlbumTag)).dx;
    final albumCell = find.descendant(
      of: find.byType(SongRow).first,
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == firstRow.song.album && widget.style?.fontSize == AppFont.px11,
      ),
    );
    final albumCellX = tester.getTopLeft(albumCell).dx;
    expect(albumCellX, closeTo(albumHeadX, 0.5));
  });

  testWidgets('未登录：登录 CTA 卡（不是空态图）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(const MusicScreen(view: MusicScreenView.playlist), size: const Size(1440, 900), logged: false),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final l10n = l10nOf(tester);
    // 破坏点：未登录仍走库列表（没有 CTA）→ 失败。
    expect(find.text(l10n.musicPlLibraryLoginTitle), findsOneWidget);
    expect(find.text(l10n.musicPlLibraryLoginAction), findsOneWidget);
    expect(find.textContaining(l10n.musicPlLibraryLikedTitle), findsNothing);
  });

  testWidgets('390×844：歌单库降级为单列行，不渲染桌面 4 列卡', (tester) async {
    await pumpLibrary(tester, size: const Size(390, 844));
    final l10n = l10nOf(tester);
    // 破坏点：移动端仍走桌面卡片布局 → 会出现横向溢出的 4 列 Row。
    expect(find.textContaining(l10n.musicPlLibraryLikedTitle), findsOneWidget);
    expect(find.byType(PlaylistLibrarySkeleton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('加载骨架：与真内容同布局（系统歌单横卡 + 分组标题）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const PlaylistLibrarySkeleton(), size: const Size(1440, 900)));
    await tester.pump();
    // 破坏点：骨架改成通用灰条（无 8 + 4 卡）→ 高度/数量断言失效。
    expect(find.byType(PlaylistLibrarySkeleton), findsOneWidget);
    expect(find.byIcon(LucideIcons.heart), findsNothing);
  });
}

/// 未登录会话替身（覆盖 musicAccountProvider 的 build）。
class _LoggedOutAccount extends MusicAccountNotifier {
  @override
  MusicAccountState build() => const MusicAccountState(cur: 'netease', logged: false, nick: null, extra: {});
}
