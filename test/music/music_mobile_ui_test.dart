import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/app/shell/mobile_nav.dart';
import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/music/controller/music_player.dart';
import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';
import 'package:miao_dock_flutter/features/music/domain/music_platform_info.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';

import 'support/demo_music_repository.dart';
import 'support/music_test_account.dart';

import 'package:miao_dock_flutter/features/music/ui/mobile/mini_bar.dart';
import 'package:miao_dock_flutter/features/music/ui/mobile/mobile_music_screen.dart';
import 'package:miao_dock_flutter/features/music/ui/music_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 音乐模块移动端 UI 断言（M01–M17 的容器口径）。
///
/// 破坏点示例：
/// - 迷你条没接 playerProvider → 注入队列后 MiniMusicBar 找不到；
/// - 横滑没接 nextTrack/prevTrack → 拖 80px 后 idx 不变；
/// - 队列抽屉没接 musicUiProvider.queueOpen → 标题找不到。
///
/// 🔴 播放器有 500ms 周期 ticker（Timer）与模拟推进：用例结束前必须把
/// 播放态暂停（toggle），否则 "Timer still pending" 断言失败；
/// 也因此这里**不能 pumpAndSettle**（每次 tick 都会排一帧），用定长 pump。
MusicPlatformInfo _neteaseInfo() => const MusicPlatformInfo(id: 'netease', label: '网易云', builtIn: true);

void main() {
  Widget host() => ProviderScope(
    overrides: [
      musicPlatformInfosProvider.overrideWith((_) => [_neteaseInfo()]),
      musicRepositoryProvider.overrideWithValue(DemoMusicRepository()),
      musicAccountProvider.overrideWith(LoggedInMusicAccount.new),
    ],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: MobileMusicScreen(view: MusicScreenView.discover)),
    ),
  );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MobileMusicScreen)));

  /// 注入演示队列（真 DemoMusicRepository 的曲目组装）。
  void injectQueue(WidgetTester tester, {int songs = 3}) {
    final repo = DemoMusicRepository();
    final ids = ['s1', 's2', 's3', 's4'].take(songs).toList();
    containerOf(tester).read(playerProvider.notifier).playAll(repo.songsByIds(ids));
  }

  /// 用例收尾：暂停播放态，停掉周期 ticker（避免 pending Timer）。
  void pausePlayer(WidgetTester tester) {
    final player = containerOf(tester).read(playerProvider);
    if (player.playing) containerOf(tester).read(playerProvider.notifier).toggle();
  }

  testWidgets('发现页渲染：视图分区出现，且容器不含底部一级导航（壳层职责）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 200)); // AsyncNotifier 就绪

    // 发现页三个分区标题（N21 顺序：推荐歌单 / 官方榜单 / 推荐歌曲）。
    expect(find.text('推荐歌单'), findsWidgets);
    expect(find.text('官方榜单'), findsWidgets);
    expect(find.text('推荐歌曲'), findsWidgets);
    // 底部一级导航属于壳层：本容器不得渲染。
    expect(find.byType(MobileBottomNav), findsNothing);
    // 队列为空 → 迷你条不出现。
    expect(find.byType(MiniMusicBar), findsNothing);
  });

  testWidgets('注入队列：迷你条出现，播放键 toggle 翻转播放态', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 200));
    injectQueue(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(MiniMusicBar), findsOneWidget);
    final container = containerOf(tester);
    expect(container.read(playerProvider).playing, isTrue);

    // 迷你条 34px 播放键：toggle 后状态翻转、图标同步换形（M03/N08）。
    await tester.tap(find.descendant(of: find.byType(MiniMusicBar), matching: find.byIcon(LucideIcons.pause)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(playerProvider).playing, isFalse);
    expect(find.descendant(of: find.byType(MiniMusicBar), matching: find.byIcon(LucideIcons.play)), findsOneWidget);
  });

  testWidgets('迷你条横滑切歌：左滑 80px（≥56 阈值）后 idx 前进一位（M16）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 200));
    injectQueue(tester, songs: 3);
    await tester.pump(const Duration(milliseconds: 100));
    final container = containerOf(tester);
    expect(container.read(playerProvider).idx, 0);

    // 在迷你条文字区左滑 80px：当前卡滑出、下一首卡跟手滑入，松手过阈值切歌。
    final text = find.descendant(of: find.byType(MiniMusicBar), matching: find.text('夜に駆ける'));
    expect(text, findsOneWidget);
    await tester.drag(text, const Offset(-80, 0));
    // 松手后先「滑到位」（settle 150ms 内）再切歌重绘；两拍 pump 覆盖动画 + 吞 click 定时器。
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(playerProvider).idx, 1);
    pausePlayer(tester);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('账号与音源抽屉：顶栏 logo 打开（M10/accountSheetOpen）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 200));
    // 破坏点：抽屉仍监听桌面 accountMenuOpen → 这条点了没反应，标题找不到。
    containerOf(tester).read(musicUiProvider.notifier).setAccountSheet(true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('账号与音源'), findsOneWidget);
    pausePlayer(tester);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('队列抽屉：打开后标题出现（M07/M12）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 200));
    injectQueue(tester, songs: 3);
    await tester.pump(const Duration(milliseconds: 100));

    containerOf(tester).read(musicUiProvider.notifier).setQueue(true);
    await tester.pump(const Duration(milliseconds: 400)); // 380ms 抽屉动画

    expect(find.textContaining('播放队列'), findsOneWidget);
    expect(find.text('夜に駆ける'), findsWidgets); // 队列行已列出
    // 标题栏右侧垃圾桶（清空）+ ✕（每行移除 + 标题栏关闭 —— M12/N14）。
    expect(find.byIcon(LucideIcons.trash2), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsWidgets);
    pausePlayer(tester);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('390×844：未导入音乐源时发现页显示导入引导（不渲染数据分区）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 无源场景：不注入 availableMusicPlatformsProvider（默认空集）。
          musicRepositoryProvider.overrideWithValue(DemoMusicRepository()),
          musicAccountProvider.overrideWith(_LoggedOutAccount.new),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: MusicScreen(view: MusicScreenView.discover)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
    // 破坏点：无源时仍渲染推荐 / 榜单分区 → 用户对着空数据疑惑；引导缺失则无法导入。
    expect(find.text(l10n.musicNoSourceTitle), findsOneWidget);
    expect(find.text(l10n.musicSecRecPlaylists), findsNothing);
    expect(find.text(l10n.musicSecCharts), findsNothing);
  });
}

/// 未登录替身（无源场景下账号态同样未登录）。
class _LoggedOutAccount extends MusicAccountNotifier {
  @override
  MusicAccountState build() => const MusicAccountState(cur: 'netease', logged: false, nick: null, extra: {});
}
