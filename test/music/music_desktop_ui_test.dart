import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/music/controller/music_player.dart';
import 'package:miao_dock_flutter/features/music/controller/music_playlist_library.dart';
import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';

import 'support/demo_music_repository.dart';
import 'support/music_test_account.dart';

import 'package:miao_dock_flutter/features/music/data/music_repository.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';
import 'package:miao_dock_flutter/features/music/ui/desktop/account_menu.dart';
import 'package:miao_dock_flutter/features/music/ui/desktop/immersive_player.dart';
import 'package:miao_dock_flutter/features/music/ui/desktop/play_bar.dart';
import 'package:miao_dock_flutter/features/music/ui/desktop/search_overlay.dart';
import 'package:miao_dock_flutter/features/music/ui/music_screen.dart';
import 'package:miao_dock_flutter/features/music/ui/sidebar_source_group.dart';
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

  Widget demoHost(Widget child, {DemoMusicRepository? repo, bool logged = true}) => ProviderScope(
    overrides: [
      availableMusicPlatformsProvider.overrideWith((_) => {MusicPlatform.netease}),
      musicRepositoryProvider.overrideWithValue(repo ?? DemoMusicRepository()),
      if (logged) musicAccountProvider.overrideWith(LoggedInMusicAccount.new),
      if (!logged) musicAccountProvider.overrideWith(_LoggedOutAccount.new),
    ],
    child: baseApp(child),
  );

  testWidgets('(a) 发现页：分区标题与 9 张推荐卡出现', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(demoHost(const MusicScreen(view: MusicScreenView.discover)));
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
    // 推荐歌曲与详情共用曲目表，并在桌面显示专辑列。
    // 破坏点：推荐歌曲退回无表头的 SongRow 堆叠时，本条失败。
    expect(find.text(l10n.musicAlbumTag), findsOneWidget);
  });

  testWidgets('(b) 榜单加载失败：整页魔法阵 + 点重试恢复', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final repo = DemoMusicRepository();
    // N28：首次加载失败（provider 从未成功过，无旧值）→ 整页 FailMagicCircle。
    // 注：首载成功后再失效失败属 N29 局部横幅口径（旧值保留），两者分支不同。
    repo.setFailScope(FailScope.charts, true);
    await tester.pumpWidget(demoHost(const MusicScreen(view: MusicScreenView.discover), repo: repo));
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
    await tester.pumpWidget(demoHost(const MusicScreen(view: MusicScreenView.discover), logged: false));
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
        overrides: [
          musicRepositoryProvider.overrideWithValue(repo),
          availableMusicPlatformsProvider.overrideWith((_) => {MusicPlatform.netease}),
        ],
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

    // 音量滑杆展开不应挤压右侧队列按钮，也不能产生 RenderFlex overflow。
    final queueButton = find.byKey(const ValueKey('music-queue-btn'));
    final queueX = tester.getTopLeft(queueButton).dx;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byKey(const ValueKey('music-volume-region'))));
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('music-volume-region'))));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(queueButton).dx, queueX);
    expect(tester.takeException(), isNull);

    // 停止模拟时钟，避免测试结束时遗留 pending timer。
    container.read(playerProvider.notifier).toggle();
    await tester.pump();
    expect(container.read(playerProvider).playing, isFalse);
  });

  testWidgets('(f) 滚动位置记忆：切视图后回来恢复（N03）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(demoHost(const MusicScreen(view: MusicScreenView.playlist)));
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

  testWidgets('(i) 沉浸样式放大歌词不产生纵向溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final repo = DemoMusicRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [musicRepositoryProvider.overrideWithValue(repo)],
        child: baseApp(const ImmersivePlayer()),
      ),
    );
    final container = containerOf(tester);
    container.read(playerStyleProvider.notifier).set(PlayerStyle.immersive);
    container.read(playerProvider.notifier).playAll(repo.songsByIds(['s7']));
    container.read(musicUiProvider.notifier).setImmersive(true);
    await tester.pump(const Duration(milliseconds: 500));

    // 破坏点：沉浸样式仍复用普通 42px 行高时，每行会 bottom overflow 3px。
    expect(find.textContaining('第 1 句歌词'), findsOneWidget);
    expect(tester.takeException(), isNull);

    container.read(playerProvider.notifier).toggle();
    await tester.pump();
  });

  testWidgets('(j) 沉浸播放器与漫画阅读器一致走应用级全屏', (tester) async {
    var fullScreen = false;
    final calls = <String>[];
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isFullScreen':
          return fullScreen;
        case 'setFullScreen':
          fullScreen = (call.arguments as Map)['isFullScreen'] as bool;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.binding.setSurfaceSize(const Size(1440, 900));

    final repo = DemoMusicRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [musicRepositoryProvider.overrideWithValue(repo)],
        child: baseApp(const ImmersivePlayer()),
      ),
    );
    final container = containerOf(tester);
    container.read(playerProvider.notifier).playAll(repo.songsByIds(['s1']));
    container.read(musicUiProvider.notifier).setImmersive(true);
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(LucideIcons.maximize2), findsOneWidget);
    expect(find.byIcon(LucideIcons.minimize2), findsNothing);

    await tester.tap(find.byKey(const ValueKey('music-window-fullscreen')));
    await tester.pump();
    expect(calls, contains('setFullScreen'));
    expect(calls, isNot(contains('maximize')));
    expect(find.byIcon(LucideIcons.minimize2), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('music-window-fullscreen')));
    await tester.pump();
    expect(fullScreen, isFalse);
    expect(calls, isNot(contains('unmaximize')));
    expect(find.byIcon(LucideIcons.maximize2), findsOneWidget);

    // 系统标题栏或系统快捷键改变全屏状态时，播放器图标也必须同步。
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('onEvent', {'eventName': 'enter-full-screen'})),
      (_) {},
    );
    await tester.pump();
    expect(find.byIcon(LucideIcons.minimize2), findsOneWidget);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('onEvent', {'eventName': 'leave-full-screen'})),
      (_) {},
    );
    await tester.pump();
    expect(find.byIcon(LucideIcons.maximize2), findsOneWidget);

    container.read(playerProvider.notifier).toggle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('(g) 切视图时滚动记忆器写回偏移（dispose 不报错）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final container = ProviderContainer(
      overrides: [
        musicRepositoryProvider.overrideWithValue(DemoMusicRepository()),
        availableMusicPlatformsProvider.overrideWith((_) => {MusicPlatform.netease}),
        musicAccountProvider.overrideWith(LoggedInMusicAccount.new),
      ],
    );
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

  testWidgets('(h) 重复点击当前视图：只回顶不重载（N03）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(demoHost(const MusicScreen(view: MusicScreenView.playlist)));
    await tester.pumpAndSettle();
    final container = containerOf(tester);
    final before = container.read(userPlaylistsProvider);
    container.read(musicScrollTopProvider.notifier).bump('playlist');
    await tester.pump();
    // 破坏点：把回顶实现成 `context.go(同一路径)` → provider 会被重建（不再是同一个 AsyncValue 实例）。
    expect(identityHashCode(container.read(userPlaylistsProvider)), identityHashCode(before));
    expect(container.read(musicScrollTopProvider)['playlist'], 1);
  });

  testWidgets('(k) 账号菜单贴在「未登录」胶囊正下方（不是左上角）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    const chip = Rect.fromLTWH(1300, 16, 92, 30);
    final menu = accountMenuRect(anchor: chip, screen: const Size(1440, 900));
    // 破坏点：用固定 top/right，或把 global 当局部坐标 → 落位不在胶囊下方，两条失败。
    expect((menu.top - chip.bottom).abs(), lessThanOrEqualTo(6));
    expect((menu.right - chip.right).abs(), lessThanOrEqualTo(1));
    // 靠右边缘时也夹在窗口内，不溢出屏幕。
    final edge = accountMenuRect(anchor: const Rect.fromLTWH(1400, 16, 40, 30), screen: const Size(1440, 900));
    expect(edge.right, lessThanOrEqualTo(1440 - 8 + 0.01));
    // 窗口很矮时菜单不跑出底部。
    final short = accountMenuRect(anchor: const Rect.fromLTWH(1200, 700, 92, 30), screen: const Size(1440, 760));
    expect(short.top, lessThanOrEqualTo(760 - 240 + 0.01));
  });

  testWidgets('(k2) 点账号 chip 会记录它的全局矩形（锚点来源）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [musicAccountProvider.overrideWith(_LoggedOutAccount.new)],
        child: baseApp(const _AccountChipProbe()),
      ),
    );
    await tester.pumpAndSettle();
    final container = containerOf(tester);
    await tester.tap(find.byKey(const ValueKey('music-account-chip')));
    await tester.pump();
    final rect = container.read(musicAccountAnchorProvider);
    final chip = tester.getRect(find.byKey(const ValueKey('music-account-chip')));
    // 破坏点：点击时不写锚点（仍靠 LayerLink / 固定偏移）→ 这条失败。
    expect(rect, isNotNull);
    expect((rect!.right - chip.right).abs(), lessThan(1));
    expect(rect.width, chip.width);
  });

  testWidgets('(l) 未登录时点「当前源」也要拉起登录（网易云）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicAccountProvider.overrideWith(_LoggedOutAccount.new),
          // 源体系口径：侧栏只列已导入平台，本用例注入网易云源。
          availableMusicPlatformsProvider.overrideWith((_) => {MusicPlatform.netease}),
        ],
        child: baseApp(const SidebarSourceGroup()),
      ),
    );
    await tester.pumpAndSettle();
    final container = containerOf(tester);
    // 当前源 = 网易云且未登录：破坏点：先判 `cur == p` 直接 return → 登录弹窗不出现。
    await tester.tap(find.text('网易云'));
    await tester.pump();
    expect(container.read(musicUiProvider).loginOpen, isTrue);
    expect(container.read(musicUiProvider).loginPlatform, MusicPlatform.netease);
  });

  testWidgets('(l2) 侧栏：无已导入源时整组不渲染', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [musicAccountProvider.overrideWith(_LoggedOutAccount.new)],
        child: baseApp(const SidebarSourceGroup()),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    // 破坏点：侧栏仍列内置四平台 → 用户以为内置源可用（源体系口径失效）。
    expect(find.text(l10n.musicSrcGroup), findsNothing);
    expect(find.text('网易云'), findsNothing);
  });

  testWidgets('(e) 搜索浮层：未导入源显示导入引导；有源未登录显示登录说明', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final l10nBase = AppLocalizations.localizationsDelegates;

    // 场景 1：无源 → 导入引导（不再提供搜索）。
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [musicAccountProvider.overrideWith(_LoggedOutAccount.new)],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
          localizationsDelegates: l10nBase,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SearchOverlay()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 破坏点：浮层对「无源」不拦 → 用户会在没有任何音源时搜到空结果。
    expect(find.text(l10nOf(tester).musicNoSourceTitle), findsOneWidget);

    // 场景 2：有源未登录 → 原有的未登录说明态（N06 边界）。
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          musicAccountProvider.overrideWith(_LoggedOutAccount.new),
          availableMusicPlatformsProvider.overrideWith((_) => {MusicPlatform.netease}),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
          localizationsDelegates: l10nBase,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SearchOverlay()),
        ),
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

/// 账号 chip 探针：行为与壳层一致（点一下写锚点 + 打开菜单）。
class _AccountChipProbe extends ConsumerWidget {
  const _AccountChipProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 16, top: 8),
        child: _AccountChipForTest(
          onTap: (rect) {
            ref.read(musicAccountAnchorProvider.notifier).set(rect);
            ref.read(musicUiProvider.notifier).setAccountMenu(true);
          },
        ),
      ),
    );
  }
}

/// 与壳层同一视觉的账号 chip；点击时把自身全局矩形交给锚点。
class _AccountChipForTest extends StatefulWidget {
  const _AccountChipForTest({required this.onTap});

  final ValueChanged<Rect> onTap;

  @override
  State<_AccountChipForTest> createState() => _AccountChipForTestState();
}

class _AccountChipForTestState extends State<_AccountChipForTest> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('music-account-chip'),
      onTap: () {
        final box = context.findRenderObject()! as RenderBox;
        widget.onTap(box.localToGlobal(Offset.zero) & box.size);
      },
      child: const SizedBox(width: 92, height: 30, child: Text('未登录')),
    );
  }
}

/// 未登录会话替身（覆盖 musicAccountProvider 的 build）。
class _LoggedOutAccount extends MusicAccountNotifier {
  @override
  MusicAccountState build() =>
      const MusicAccountState(cur: MusicPlatform.netease, logged: false, nick: null, extra: {});
}
