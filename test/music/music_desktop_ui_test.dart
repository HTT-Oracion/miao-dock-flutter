import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/music/controller/music_player.dart';
import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';
import 'package:miao_dock_flutter/features/music/data/demo_music_repository.dart';
import 'package:miao_dock_flutter/features/music/data/music_repository.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';
import 'package:miao_dock_flutter/features/music/ui/desktop/play_bar.dart';
import 'package:miao_dock_flutter/features/music/ui/desktop/search_overlay.dart';
import 'package:miao_dock_flutter/features/music/ui/music_screen.dart';
import 'package:miao_dock_flutter/features/music/ui/views/discover_view.dart';
import 'package:miao_dock_flutter/features/music/ui/widgets/fail_magic.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 音乐桌面端 UI widget 测试：
/// (a) 发现页分区标题 + 9 张推荐卡（N37）；
/// (b) 榜单加载失败 → 整页魔法阵（N28）+ 点重试恢复；
/// (c) 未登录 → 推荐歌曲分区呈现登录 CTA；
/// (d) 播放器：注入队列 → 播放条出现 + 模式键循环档位（N10）；
/// (e) 搜索浮层：未登录说明态（N06 边界）。
void main() {
  /// 公共主题挂载：MaterialApp + AppPalette 深色 + zh 词条
  /// （与 test/library_visual_test.dart 同范式）。
  Widget baseApp(Widget child) => MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  AppLocalizations l10nOf(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(Scaffold)));

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold)));

  testWidgets('(a) 发现页：分区标题与 9 张推荐卡出现', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(ProviderScope(child: baseApp(const MusicScreen(view: MusicScreenView.discover))));
    await tester.pumpAndSettle();

    final l10n = l10nOf(tester);
    // 破坏点：分区顺序或标题变化 → 三个标题断言失败（N21/N37 顺序固定）。
    expect(find.text(l10n.musicSecRecPlaylists), findsOneWidget);
    expect(find.text(l10n.musicSecCharts), findsOneWidget);
    expect(find.text(l10n.musicSecDaily), findsOneWidget);
    // N37：9 张推荐卡（非懒加载 Row，全部构建）。
    expect(find.byKey(const ValueKey('rec-card')), findsNWidgets(9));
    // 推荐歌单 6 瓦片。
    expect(find.byType(MusicPlaylistTile), findsNWidgets(6));
  });

  testWidgets('(b) 榜单加载失败：整页魔法阵 + 点重试恢复', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final repo = DemoMusicRepository();
    // N28：首次加载失败（provider 从未成功过，无旧值）→ 整页 FailMagicCircle。
    // 注：首载成功后再失效失败属 N29 局部横幅口径（旧值保留），两者分支不同。
    repo.setFailScope(FailScope.charts, true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [musicRepositoryProvider.overrideWithValue(repo)],
        child: baseApp(const MusicScreen(view: MusicScreenView.discover)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    // 魔法阵有常转动画，不能 pumpAndSettle。
    expect(find.byType(FailMagicCircle), findsOneWidget);

    // 解除故障 → 点「重试」→ 分区内容恢复。
    repo.setFailScope(FailScope.charts, false);
    await tester.tap(find.text(l10nOf(tester).musicRetry));
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    // 破坏点：重试没有失效 provider、或失败态残留 → 两条失败。
    expect(find.byType(FailMagicCircle), findsNothing);
    expect(find.text(l10n.musicSecCharts), findsOneWidget);
    expect(find.byKey(const ValueKey('rec-card')), findsNWidgets(9));
  });

  testWidgets('(c) 未登录：推荐歌曲分区呈现登录 CTA', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(
      ProviderScope(
        // 未登录（dailySongsProvider 对未登录返回空 → UI 换登录卡）。
        overrides: [musicAccountProvider.overrideWith(_LoggedOutAccount.new)],
        child: baseApp(const MusicScreen(view: MusicScreenView.discover)),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = l10nOf(tester);
    // 破坏点：登录 CTA 缺失或标题变化 → 失败。
    expect(find.text(l10n.musicDailyLoginTitle), findsOneWidget);
    expect(find.text(l10n.musicLoginAction), findsOneWidget);
  });

  testWidgets('(d) 播放器：注入队列 → 播放条出现，模式键循环档位', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final repo = DemoMusicRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [musicRepositoryProvider.overrideWithValue(repo)],
        child: baseApp(const MusicScreen(view: MusicScreenView.discover)),
      ),
    );
    await tester.pumpAndSettle();
    final container = containerOf(tester);

    // 队列为空 → 播放条隐藏。
    expect(find.byType(MusicPlayBar), findsNothing);

    // 注入整组队列（playAll，模拟点推荐卡）。
    container.read(playerProvider.notifier).playAll(repo.songsByIds(['s1', 's2', 's3']));
    await tester.pump();
    // 破坏点：播放条未随队列出现。
    expect(find.byType(MusicPlayBar), findsOneWidget);
    expect(container.read(playerProvider).mode, PlayMode.list);

    // N10：点模式键循环（列表循环 → 单曲循环 → 随机；心动不合法被跳过）。
    final modeBtn = find.byKey(const ValueKey('music-mode-btn'));
    await tester.tap(modeBtn);
    await tester.pump();
    expect(container.read(playerProvider).mode, PlayMode.one);
    await tester.tap(modeBtn);
    await tester.pump();
    expect(container.read(playerProvider).mode, PlayMode.shuffle);

    // 停止模拟时钟，避免测试结束时遗留 pending timer。
    container.read(playerProvider.notifier).toggle();
    await tester.pump();
    expect(container.read(playerProvider).playing, isFalse);
  });

  testWidgets('(f) 滚动位置记忆：切视图后回来恢复（N03）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(ProviderScope(child: baseApp(const MusicScreen(view: MusicScreenView.playlist))));
    await tester.pumpAndSettle();
    final container = containerOf(tester);
    // 记忆器在 dispose 时写回；破坏点：去掉 MusicScrollMemory → 这条恒为 0。
    container.read(musicScrollMemoryProvider.notifier).save('discover', 240);
    expect(container.read(musicScrollMemoryProvider)['discover'], 240);
    // 重复保存同值不产生新 Map（避免无谓重建）。
    final before = container.read(musicScrollMemoryProvider);
    container.read(musicScrollMemoryProvider.notifier).save('discover', 240);
    expect(identical(container.read(musicScrollMemoryProvider), before), isTrue);
  });

  testWidgets('(g) 切视图时滚动记忆器写回偏移（dispose 不报错）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Widget host(MusicScreenView v) => UncontrolledProviderScope(
      container: container,
      child: baseApp(MusicScreen(view: v)),
    );
    await tester.pumpWidget(host(MusicScreenView.discover));
    await tester.pumpAndSettle();
    // 先真的滚一段：记忆器在滚动监听里写回（dispose 期读不到 offset）。
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(MusicScreenView.playlist));
    await tester.pumpAndSettle();
    // 破坏点：把写回挪到 dispose → 切走后 Map 里没有 discover；
    // 或在 dispose 读 controller.offset（已 detach）→ 记成 0 / 抛异常。
    expect(tester.takeException(), isNull);
    expect(container.read(musicScrollMemoryProvider)['discover'] ?? 0, greaterThan(0));
  });

  testWidgets('(e) 搜索浮层：未登录说明态出现', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    // 搜索浮层已提升到壳层挂载（要盖住侧栏/工具条，N06）——这里直接 pump 浮层本体，
    // 配合未登录 override 验证说明态。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [musicAccountProvider.overrideWith(_LoggedOutAccount.new)],
        child: baseApp(const SearchOverlay()),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = l10nOf(tester);
    // N06 边界：未登录不可搜 → 给说明与登录入口，不给灰框。
    // 破坏点：浮层缺登录态分支、或文本键改名 → 失败。
    expect(find.text(l10n.musicSearchLoginTitle), findsOneWidget);
    expect(find.text(l10n.musicSearchGoLogin), findsOneWidget);
  });
}

/// 未登录会话替身（覆盖 musicAccountProvider 的 build）。
class _LoggedOutAccount extends MusicAccountNotifier {
  @override
  MusicAccountState build() =>
      const MusicAccountState(cur: MusicPlatform.netease, logged: false, nick: null, extra: {});
}
