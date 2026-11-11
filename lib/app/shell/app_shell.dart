import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/storage/shell_prefs.dart';
import '../../core/theme/tokens.dart';
import '../../core/window/window_controller.dart';
import '../../features/manga/controller/queue_controller.dart';
import '../../features/manga/controller/reader_focus.dart';
import '../../features/manga/controller/engine_controller.dart';
import '../../features/manga/controller/remote_controller.dart';
import '../../features/manga/ui/manga_gate.dart';
import '../../features/manga/ui/library_detail.dart';
import 'readiness.dart';
import '../../features/manga/domain/manga_task.dart';
import '../../features/manga/domain/not_ready_state.dart';
import '../../features/music/controller/music_playlist_library.dart';
import '../../features/music/controller/music_session.dart';
import '../../features/music/domain/music_models.dart';
import '../../features/music/controller/music_player.dart';
import '../../features/music/ui/desktop/desktop_lyrics.dart';
import '../../features/music/ui/desktop/account_menu.dart';
import '../../features/music/ui/desktop/immersive_player.dart';
import '../../features/music/ui/desktop/island.dart';
import '../../features/music/ui/desktop/login_modal.dart';
import '../../features/music/ui/desktop/queue_drawer.dart';
import '../../features/music/ui/desktop/search_overlay.dart';
import '../../features/music/ui/sidebar_mini_player.dart';
import '../../features/music/ui/sidebar_source_group.dart';
import '../../features/music/ui/widgets/platform_logo.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/app_title_bar.dart';
import '../../shared/widgets/nav_rail.dart';
import 'module_nav.dart';
import 'shell_controller.dart';
import 'sidebar_music_views.dart';
import 'view_labels.dart';
import 'mobile_nav.dart';
import 'view_tabs.dart';

/// 响应式应用壳（design.html §03）：
/// 桌面 = 侧栏（208/68）+ 工具条（56）+ 内容区；
/// 移动 = 顶栏（56）+ 抽屉侧栏（左滑入 + 遮罩）。
/// 断点取设计稿 `@media (max-width:768px)`。
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(engineStatusPollProvider);
    final path = GoRouterState.of(context).uri.path;
    // 详情页标题由详情屏写进 provider（壳层拿不到歌单数据），只在音乐详情路径读。
    final detailCrumb = path.startsWith('/music/playlist/') || path.startsWith('/music/chart/')
        ? ref.watch(musicDetailCrumbProvider)?.name
        : null;
    final location = _ShellLocation.of(path, AppLocalizations.of(context), detailCrumb: detailCrumb);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > AppMetrics.breakpoint;
        if (wide) return _DesktopShell(shell: navigationShell, location: location, path: path);
        return _MobileShell(shell: navigationShell, location: location, path: path);
      },
    );
  }
}

// ── 路由解析（壳层唯一事实：路径 → 模块 / 视图 / 面包屑）─────────────────

@immutable
class _ShellLocation {
  const _ShellLocation({
    required this.moduleIndex,
    required this.viewId,
    required this.crumbs,
    required this.viewGroupLabel,
    required this.viewItems,
  });

  /// 0 漫画 / 1 音乐 / 2 番剧 / -1 设置。
  final int moduleIndex;

  /// 当前模块内视图 id；null = 非模块页。
  final String? viewId;

  /// 工具条面包屑。
  final List<String> crumbs;

  /// 侧栏视图组标题。
  final String viewGroupLabel;

  /// 侧栏视图组条目。
  final List<SidebarViewItem> viewItems;

  static const _modules = {'manga': 0, 'music': 1, 'anime': 2};

  /// 路径 → 壳层位置。文案经 [AppLocalizations] 注入，不在本层写死中文。
  static _ShellLocation of(String path, AppLocalizations l10n, {String? detailCrumb}) {
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    if (seg.isEmpty) return _empty;
    final index = _modules[seg[0]] ?? -1;
    if (index < 0) {
      // 设置页：全局层，无模块、无视图组。
      return _ShellLocation(
        moduleIndex: -1,
        viewId: null,
        crumbs: [l10n.brandName, l10n.navSettings],
        viewGroupLabel: l10n.navSettings,
        viewItems: const [],
      );
    }
    final module = moduleLabel(l10n, index);
    final items = index == 0 ? mangaViews : (index == 1 ? musicViews : const <SidebarViewItem>[]);
    final viewId = resolveViewId(seg.length > 1 ? seg[1] : null, items);
    final crumbs = <String>[module];
    if (viewId != null) crumbs.add(viewLabel(l10n, viewId));
    // 歌单 / 榜单详情：面包屑补一级当前歌单名（设计稿 N41）。
    if (index == 1 && seg.length > 2 && (seg[1] == 'playlist' || seg[1] == 'chart')) {
      final title = detailCrumb;
      if (title != null && title.isNotEmpty) crumbs.add(title);
    }
    return _ShellLocation(moduleIndex: index, viewId: viewId, crumbs: crumbs, viewGroupLabel: module, viewItems: items);
  }

  static const _empty = _ShellLocation(moduleIndex: -1, viewId: null, crumbs: [], viewGroupLabel: '', viewItems: []);
}

/// 队列待办计数 —— 口径取自原项目 `queueDepth = running + queued`。
///
/// 不能用 `tasks.length`：那会把已完成 / 失败 / 已取消的历史任务也算进侧栏徽标，
/// 与「队内还有几个在等」的语义不符。
int _queueDepth(List<MangaTask> tasks) =>
    tasks.where((t) => t.status == MangaTaskStatus.translating || t.status == MangaTaskStatus.queued).length;

// ── 桌面壳 ────────────────────────────────────────────────────────────────

class _DesktopShell extends ConsumerWidget {
  const _DesktopShell({required this.shell, required this.location, required this.path});

  final StatefulNavigationShell shell;
  final _ShellLocation location;
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final collapsed = ref.watch(navCollapsedProvider);
    final labels = ref.watch(sidebarLabelsProvider);
    final queueDepth = _queueDepth(ref.watch(queueProvider).value ?? const []);
    final musicUi = ref.watch(musicUiProvider);
    final hasSong = ref.watch(playerProvider.select((p) => p.current != null));
    // 阅读器专注模式：只留阅读器，壳层（侧栏 / 工具条 / 页签）整体不渲染。
    // 绑定 `isReaderPath` 是为了「离开阅读器就自动还壳」——否则从阅读器点到别处
    // 会看到一个没有侧栏的空窗口。
    if (ref.watch(readerFocusProvider) && isReaderPath(path)) {
      // 专注模式顶部让位（D-180）：macOS 的原生红绿灯叠在客户区左上角，
      // 不渲染自绘标题栏时会把阅读器顶栏压住；Windows / Linux 无此问题（让位 0）。
      // 这条带子本身是拖拽区 —— 否则窗口没法拖（最大化后拖动会退出最大化并移动）。
      // 真全屏时系统标题栏 / 红绿灯都已隐藏，不需要让位；全屏失败才按平台让。
      final fullscreen = ref.watch(readerFullscreenProvider);
      final focusInset = readerFocusTopInset(macos: isMacosPlatform, fullscreen: fullscreen);
      return Scaffold(
        backgroundColor: palette.bg,
        body: Column(
          children: [
            if (focusInset > 0)
              DragToMoveArea(
                child: SizedBox(key: const Key('reader-focus-inset'), height: focusInset, width: double.infinity),
              ),
            Expanded(child: shell),
          ],
        ),
      );
    }

    // macOS 无边框窗口：原生红绿灯叠在客户区左上角，侧栏与工具条整体下移一条带子。
    final topInset = isMacosPlatform ? AppMetrics.macTrafficLightBand : 0.0;

    return Scaffold(
      backgroundColor: palette.bg,
      body: Stack(
        children: [
          Row(
            children: [
              NavRail(
                collapsed: collapsed,
                labels: labels,
                onToggleCollapse: () => ref.read(navCollapsedProvider.notifier).toggle(),
                moduleIndex: location.moduleIndex,
                onSelectModule: (i) => switchModule(context, ref, shell, i),
                queueCount: queueDepth,
                onOpenSettings: () => goSettings(context, ref),
                readiness: ref.watch(shellReadinessProvider),
                miniPlayer: SidebarMiniPlayer(collapsed: collapsed),
                // 音乐模块视图组（设计稿信息架构：视图在侧栏，不在工具条）。
                viewGroup: location.moduleIndex == 1
                    ? SidebarMusicViews(
                        activeId: location.viewId,
                        onSelect: (v) => _goView(context, 1, v),
                        collapsed: collapsed,
                        labels: labels,
                      )
                    : null,
                // 音乐模块附属组：音源（四平台 + 三态徽标，设计稿 N04）。
                sourceGroup: location.moduleIndex == 1
                    ? (collapsed ? const SidebarSourceMini() : const SidebarSourceGroup())
                    : null,
                topInset: topInset,
              ),
              Container(width: 1, color: palette.line),
              Expanded(
                child: Column(
                  children: [
                    AppTitleBar(
                      topInset: topInset,
                      breadcrumb: _Crumbs(crumbs: location.crumbs),
                      tabs: [
                        // 模块内视图页签（漫画模块；音乐设计稿把视图放回侧栏，不渲染页签）。
                        // 番剧无视图、设置是全局层 ⇒ 不渲染页签。
                        if (location.moduleIndex >= 0 && location.moduleIndex != 1 && location.viewItems.isNotEmpty)
                          ShellViewTabs(
                            items: [
                              for (final item in location.viewItems)
                                (item.id, viewLabel(AppLocalizations.of(context), item.id)),
                            ],
                            activeId: location.viewId,
                            onSelect: (v) => _goView(context, location.moduleIndex, v),
                          ),
                      ],
                      actions: [
                        if (location.moduleIndex == 0) const _TranslateStatusChips(),
                        // 设计稿 `.apptool` 右端：漫画库视图专属「新建漫画」。
                        // 阅读器归到漫画库视图，但阅读时不该出现新建入口。
                        if (location.viewId == 'library' && !isReaderPath(path)) const LibraryHeaderActions(),
                        // 音乐模块：顶栏搜索 + 账号 chip（设计稿 N06/N05）。
                        if (location.moduleIndex == 1) const _MusicToolbarActions(),
                      ],
                    ),
                    Container(height: 1, color: palette.line),
                    Expanded(
                      child: MangaGate(enabled: location.moduleIndex == 0, path: path, child: shell),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 灵动岛：设计稿挂在工具条中央、按应用窗口居中；展开态向下覆盖内容区。
          // ≤1120 隐藏（播放条已覆盖同样能力，N13 边界），避免挤掉搜索与账号。
          if (location.moduleIndex == 1 &&
              hasSong &&
              !musicUi.immersiveOpen &&
              MediaQuery.sizeOf(context).width > AppMetrics.musicIslandBreakpoint)
            Positioned(
              top: topInset + 11,
              left: 0,
              right: 0,
              child: const Center(child: DynamicIsland()),
            ),
          if (location.moduleIndex == 1 && musicUi.accountMenuOpen) const Positioned.fill(child: AccountMenuPopover()),
          // 沉浸播放器覆盖整个应用（含侧栏 / 工具条 / 播放条，N16）。
          // 挂在壳层而非模块容器，才能盖住壳层；键盘 Esc 由播放器自身收口。
          if (location.moduleIndex == 1 && musicUi.immersiveOpen) const Positioned.fill(child: ImmersivePlayer()),
          // 展开播放器的队列必须挂在同一壳层并后绘制，否则会被播放器整层盖住。
          if (location.moduleIndex == 1 && musicUi.immersiveOpen && musicUi.queueOpen)
            const Positioned(top: 0, right: 0, bottom: 0, child: QueueDrawer()),
          // 桌面歌词设置弹窗要在沉浸播放器之上（N19 从播放器底部齿轮进入）。
          if (location.moduleIndex == 1 && musicUi.lyricsSettingsOpen)
            const Positioned.fill(child: DesktopLyricsSettingsModal()),
          // 音乐模块全屏浮层（挂壳层：搜索 / 登录要盖住侧栏与工具条，N06/N04）。
          if (location.moduleIndex == 1 && musicUi.searchOpen) const SearchOverlay(),
          if (location.moduleIndex == 1 && musicUi.loginOpen) const LoginModal(),
        ],
      ),
    );
  }
}

void _goView(BuildContext context, int moduleIndex, String viewId) {
  final base = moduleIndex == 1 ? 'music' : 'manga';
  final target = '/$base/$viewId';
  // N03：重复点击当前视图不重载，只把内容滚回顶部（省一次无意义的重新请求）。
  if (moduleIndex == 1 && GoRouterState.of(context).uri.path == target) {
    ProviderScope.containerOf(context, listen: false).read(musicScrollTopProvider.notifier).bump(viewId);
    return;
  }
  context.go(target);
  // 再打一次「跳完之后路由器认为自己在哪」——
  // 若这里仍是旧路径 ⇒ 路由没生效；若已是新路径 ⇒ 路由对、是渲染层没换。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final router = GoRouter.maybeOf(context);
    debugPrint('[nav] at = ${router?.routerDelegate.currentConfiguration.uri}');
  });
}

// ── 页面切换动效（design.html §06：opacity 0→1 + translateY(8→0)，300ms ease）──

class _PageTransition extends StatefulWidget {
  const _PageTransition({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<_PageTransition> createState() => _PageTransitionState();
}

/// 页面切换动效（design.html §06）：`opacity 0→1 + translateY(8px→0)`，300ms ease。
///
/// 🔴 只对**内容层**做单次入场动画，不用 [AnimatedSwitcher] 交叉淡出：
/// 被动画的子件是 `StatefulNavigationShell`，它带 GlobalKey；AnimatedSwitcher 会在
/// 过渡期同时挂载新旧两份子树，导致 "Duplicate GlobalKey detected" 直接白屏。
class _PageTransitionState extends State<_PageTransition> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.pageSwitch)..forward();
  }

  @override
  void didUpdateWidget(covariant _PageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.ease);
    final offset = Tween<Offset>(
      begin: const Offset(0, AppMotion.pageSwitchOffset / 100),
      end: Offset.zero,
    ).animate(curved);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: offset, child: widget.child),
    );
  }
}

// ── 工具条内容 ────────────────────────────────────────────────────────────

/// 面包屑（app.css `.crumb` 10 / `--mut`，`.crumb2` 13 / 700 / `--ink`）。
class _Crumbs extends StatelessWidget {
  const _Crumbs({required this.crumbs});

  final List<String> crumbs;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (crumbs.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (final (i, c) in crumbs.indexed) ...[
          if (i > 0) ...[
            const SizedBox(width: 8),
            Icon(LucideIcons.chevronRight, size: 10, color: palette.mut),
            const SizedBox(width: 8),
          ],
          if (i == crumbs.length - 1)
            Flexible(
              child: Text(
                c,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
              ),
            )
          else
            Text(
              c,
              style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
            ),
        ],
      ],
    );
  }
}

/// 主题切换（design.html §01：深浅双主题；图标沿用 lucide 线性风格）。
class _MobileShell extends ConsumerStatefulWidget {
  const _MobileShell({required this.shell, required this.location, required this.path});

  final StatefulNavigationShell shell;
  final _ShellLocation location;
  final String path;

  @override
  ConsumerState<_MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<_MobileShell> {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final location = widget.location;
    final l10n = AppLocalizations.of(context);
    final musicUi = location.moduleIndex == 1 ? ref.watch(musicUiProvider) : null;
    // 全屏播放器（M04）与移动端全屏搜索（M06）：顶到屏幕边缘，隐藏底部一级导航与
    // 顶部页签；两者自身处理安全区，外壳只保留状态栏让位。
    final musicFull = (musicUi?.immersiveOpen ?? false) || (musicUi?.searchOpen ?? false);

    // 全屏阅读（移动端）：阅读器顶到屏幕边缘 —— 不渲染顶部视图页签、不渲染
    // 底部一级导航，也不套 SafeArea（顶栏自己避让状态栏，内容才能满屏）。
    // 退出只有两条路：顶栏 × 或系统返回，都由 ReaderScreen 处理。
    if (isReaderPath(widget.path)) {
      return Scaffold(
        backgroundColor: palette.bg,
        body: MangaGate(enabled: location.moduleIndex == 0, path: widget.path, child: widget.shell),
      );
    }

    return Scaffold(
      backgroundColor: palette.bg,
      // 一级导航在**底部**（漫画 / 音乐 / 番剧 / 设置）：手机上一级入口必须一次点击可达。
      bottomNavigationBar: musicFull
          ? null
          : MobileBottomNav(
              moduleIndex: location.moduleIndex,
              onSelectModule: (i) => switchModule(context, ref, widget.shell, i),
            ),
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // 音乐模块移动端顶栏（M10：左搜索条 + 右当前音源 logo）；
                // 歌单 / 榜单详情才出现返回箭头（M18：歌单库是一级页）。
                if (!musicFull && location.moduleIndex == 1)
                  _MusicMobileHeader(showBack: _isMusicDetailPath(widget.path)),
                // 二级导航在**顶部**：当前模块内的视图，可横向滑动。
                if (!musicFull)
                  MobileViewTabs(
                    items: [
                      for (final item in location.viewItems)
                        (
                          item.id,
                          location.moduleIndex == 1 ? mobileViewLabel(l10n, item.id) : viewLabel(l10n, item.id),
                        ),
                    ],
                    activeId: location.viewId,
                    onSelect: (v) => _goView(context, location.moduleIndex, v),
                    actions: [
                      // 设计稿 `.vtabs .acts`：漫画库页签右侧「新建漫画」。
                      // 阅读器归到漫画库视图，但阅读时不该出现新建入口。
                      if (location.viewId == 'library' && !isReaderPath(widget.path)) const LibraryHeaderActions(),
                    ],
                  ),
                Expanded(
                  child: MangaGate(enabled: location.moduleIndex == 0, path: widget.path, child: widget.shell),
                ),
              ],
            ),
          ),
          // 音乐模块全屏浮层（移动端挂壳层：搜索浮层 / 登录弹窗，N06/N04）。
          if (location.moduleIndex == 1 && (musicUi?.searchOpen ?? false)) const SearchOverlay(),
          if (location.moduleIndex == 1 && (musicUi?.loginOpen ?? false)) const LoginModal(),
        ],
      ),
    );
  }
}

/// 音乐模块桌面工具条动作：搜索（⌘K 语义入口）+ 账号 chip（N06/N05）。
class _MusicToolbarActions extends ConsumerWidget {
  const _MusicToolbarActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final account = ref.watch(musicAccountProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: l10n.musicSearchHint,
          child: GestureDetector(
            onTap: () => ref.read(musicUiProvider.notifier).setSearch(true),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: palette.card,
                  border: Border.all(color: palette.line2),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.search, size: 12, color: palette.mut),
                    const SizedBox(width: 8),
                    Text(
                      l10n.musicSearchHint,
                      style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _AccountChip(
          account: account,
          onTap: () {
            final box = _accountChipKey.currentContext?.findRenderObject() as RenderBox?;
            if (box != null) {
              ref.read(musicAccountAnchorProvider.notifier).set(box.localToGlobal(Offset.zero) & box.size);
            }
            ref.read(musicUiProvider.notifier).setAccountMenu(true);
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

/// 账号 chip 的 key：点击时用它取全局矩形，作为账号菜单的锚点。
final GlobalKey _accountChipKey = GlobalKey();

/// 顶栏账号 chip（头像 + 昵称 / 未登录）。
class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.account, required this.onTap});

  final MusicAccountState account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      key: _accountChipKey,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: palette.card,
            border: Border.all(color: palette.line2),
            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: account.logged ? palette.accSoft : palette.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: account.logged ? palette.acc : palette.line2),
                ),
                child: Text(
                  account.logged ? (account.nick?.substring(0, 1) ?? '?') : '?',
                  style: TextStyle(fontSize: AppFont.px9, color: account.logged ? palette.accInk : palette.mut),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                account.logged ? (account.nick ?? '') : l10n.musicNotLogged,
                style: TextStyle(fontSize: AppFont.px10, color: palette.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 音乐模块内「详情」路径（歌单 / 榜单 / 每日推荐）：移动端顶栏据此显示返回箭头。
bool _isMusicDetailPath(String path) =>
    path.startsWith('/music/playlist/') || path.startsWith('/music/chart/') || path.startsWith('/music/daily');

/// 音乐模块移动端顶栏（M10）：左整条搜索入口 + 右当前音源品牌 logo。
///
/// 详情页在搜索条左侧补一枚返回箭头（M18）：点它回歌单库，而不是回发现页。
class _MusicMobileHeader extends ConsumerWidget {
  const _MusicMobileHeader({this.showBack = false});

  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final cur = ref.watch(musicAccountProvider).cur;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          if (showBack) ...[
            GestureDetector(
              onTap: () => GoRouter.of(context).go('/music/playlist'),
              behavior: HitTestBehavior.opaque,
              child: Tooltip(
                message: l10n.musicPlBack,
                child: SizedBox(
                  width: 40,
                  height: 36,
                  child: Icon(LucideIcons.arrowLeft, size: 20, color: palette.ink),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: GestureDetector(
              onTap: () => ref.read(musicUiProvider.notifier).setSearch(true),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: palette.card,
                  border: Border.all(color: palette.line2),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.search, size: 14, color: palette.mut),
                    const SizedBox(width: 8),
                    Text(
                      l10n.musicSearchHint,
                      style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => ref.read(musicUiProvider.notifier).setAccountSheet(true),
            child: Tooltip(
              message: l10n.musicCurSourceAria(platformBrands[cur]!.label),
              child: PlatformLogo(platform: cur, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

/// 工具条状态徽标（D-012）—— 取代原「服务运行中」。
///
/// 🔴 为什么要移除「服务运行中」：服务常驻后它永远显示绿色，**没有信息量**，
/// 而且会误导 —— 服务绿 ≠ 能翻译。这里改为显示用户真正关心的两件事：
/// 「引擎是否就绪」（可点击直接启动）与「当前翻译来源」。
class _TranslateStatusChips extends ConsumerWidget {
  const _TranslateStatusChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(notReadyViewProvider);
    final source = ref.watch(translateSourceProvider);
    final remoteVerification = ref.watch(remoteVerificationProvider);
    final engineReady = source == TranslateSource.remote ? remoteVerification.isReady : view.engine.isReady;

    final sourceLabel = switch (source) {
      TranslateSource.local => l10n.sourceLocal,
      TranslateSource.llm => l10n.sourceLlm,
      TranslateSource.remote => l10n.sourceRemote,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 引擎就绪度：未就绪时**可点击**直接拉起（不让用户先去别的页面）
        InkWell(
          onTap: engineReady
              ? null
              : () {
                  if (source == TranslateSource.remote) {
                    goSettings(context, ref);
                  } else {
                    ref.read(engineStateProvider.notifier).start();
                  }
                },
          borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: engineReady ? palette.good : palette.bad, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(
                  engineReady ? l10n.engineReady : l10n.engineNotReady,
                  style: TextStyle(fontSize: AppFont.px10, color: palette.ink2),
                ),
              ],
            ),
          ),
        ),
        Container(width: 1, height: 14, color: palette.line, margin: const EdgeInsets.symmetric(horizontal: 6)),
        _Chip(label: sourceLabel),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: AppFont.px9, color: palette.ink2),
      ),
    );
  }
}
