import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:protocol/protocol.dart';

import '../../core/storage/shell_prefs.dart';
import '../../core/theme/theme_mode.dart';
import '../../core/theme/tokens.dart';
import '../../core/window/window_controller.dart';
import '../../features/manga/controller/queue_controller.dart';
import '../../features/music/ui/sidebar_mini_player.dart';
import '../../shared/widgets/app_title_bar.dart';
import '../../shared/widgets/nav_rail.dart';
import 'shell_controller.dart';

/// 响应式应用壳（design.html §03）：
/// 桌面 = 侧栏（208/68）+ 工具条（56）+ 内容区；
/// 移动 = 顶栏（56）+ 抽屉侧栏（左滑入 + 遮罩）。
/// 断点取设计稿 `@media (max-width:768px)`。
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = _ShellLocation.of(GoRouterState.of(context).uri.path);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > AppMetrics.breakpoint;
        if (wide) return _DesktopShell(shell: navigationShell, location: location);
        return _MobileShell(shell: navigationShell, location: location);
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

  static const _moduleNames = ['漫画翻译', '音乐', '番剧'];

  /// 视图标题（与原项目 `TITLES` 逐字一致，仅取本期已实现的模块）。
  static const _viewTitles = {
    'drop': '投放',
    'queue': '任务队列',
    'library': '本地漫画库',
    'discover': '发现',
    'playlist': '我的歌单',
    'local': '本地音乐',
    'history': '播放历史',
  };

  static const _modules = {'manga': 0, 'music': 1, 'anime': 2};

  static _ShellLocation of(String path) {
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    if (seg.isEmpty) return _empty;
    final index = _modules[seg[0]] ?? -1;
    if (index < 0) {
      // 设置页：全局层，无模块、无视图组。
      return const _ShellLocation(
        moduleIndex: -1,
        viewId: null,
        crumbs: ['喵坞', '设置'],
        viewGroupLabel: '设置',
        viewItems: [],
      );
    }
    final items = index == 0 ? mangaViews : (index == 1 ? musicViews : const <SidebarViewItem>[]);
    final viewId = seg.length > 1 && items.any((v) => v.id == seg[1]) ? seg[1] : items.firstOrNull?.id;
    final crumbs = <String>[_moduleNames[index]];
    final title = viewId == null ? null : _viewTitles[viewId];
    if (title != null) crumbs.add(title);
    return _ShellLocation(
      moduleIndex: index,
      viewId: viewId,
      crumbs: crumbs,
      viewGroupLabel: _moduleNames[index],
      viewItems: items,
    );
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
  const _DesktopShell({required this.shell, required this.location});

  final StatefulNavigationShell shell;
  final _ShellLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final collapsed = ref.watch(navCollapsedProvider);
    final labels = ref.watch(sidebarLabelsProvider);
    final queueDepth = _queueDepth(ref.watch(queueProvider).value ?? const []);
    // macOS 无边框窗口：原生红绿灯叠在客户区左上角，侧栏与工具条整体下移一条带子。
    final topInset = isMacosPlatform ? AppMetrics.macTrafficLightBand : 0.0;

    return Scaffold(
      backgroundColor: palette.bg,
      body: Row(
        children: [
          NavRail(
            collapsed: collapsed,
            labels: labels,
            onToggleCollapse: () => ref.read(navCollapsedProvider.notifier).toggle(),
            moduleIndex: location.moduleIndex,
            onSelectModule: (i) => _goModule(context, i),
            viewGroupLabel: location.viewGroupLabel,
            viewItems: location.viewItems,
            activeViewId: location.viewId,
            onSelectView: (v) => _goView(context, location.moduleIndex, v),
            queueCount: queueDepth,
            onOpenSettings: () => context.go('/settings'),
            miniPlayer: SidebarMiniPlayer(collapsed: collapsed),
            topInset: topInset,
          ),
          Container(width: 1, color: palette.line),
          Expanded(
            child: Column(
              children: [
                AppTitleBar(
                  topInset: topInset,
                  breadcrumb: _Crumbs(crumbs: location.crumbs),
                  actions: [const _ThemeToggleButton()],
                ),
                Container(height: 1, color: palette.line),
                Expanded(
                  child: _PageTransition(location: GoRouterState.of(context).uri.path, child: shell),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _goModule(BuildContext context, int index) {
  switch (index) {
    case 0:
      context.go('/manga/drop');
    case 1:
      context.go('/music/discover');
    default:
      context.go('/anime');
  }
}

void _goView(BuildContext context, int moduleIndex, String viewId) {
  final base = moduleIndex == 1 ? 'music' : 'manga';
  context.go('/$base/$viewId');
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
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.ink),
              ),
            )
          else
            Text(c, style: TextStyle(fontSize: 10, color: palette.mut)),
        ],
      ],
    );
  }
}

/// 主题切换（design.html §01：深浅双主题；图标沿用 lucide 线性风格）。
class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      icon: Icon(isDark ? LucideIcons.sun : LucideIcons.moon, size: 15),
      color: palette.ink2,
      tooltip: isDark ? '切换到浅色主题' : '切换到深色主题',
      onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
    );
  }
}

// ── 移动壳 ────────────────────────────────────────────────────────────────

class _MobileShell extends ConsumerStatefulWidget {
  const _MobileShell({required this.shell, required this.location});

  final StatefulNavigationShell shell;
  final _ShellLocation location;

  @override
  ConsumerState<_MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<_MobileShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final labels = ref.watch(sidebarLabelsProvider);
    final queueDepth = _queueDepth(ref.watch(queueProvider).value ?? const []);
    final title = widget.location.crumbs.isEmpty ? '喵坞' : widget.location.crumbs.last;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: palette.bg,
      // 抽屉宽度固定展开态 208（design.html 移动端 `.sidebar{width:var(--sidebar-w)}`）。
      drawer: _MobileDrawer(
        width: AppMetrics.sidebarWidth,
        location: widget.location,
        labels: labels,
        queueDepth: queueDepth,
      ),
      // 移动端安全区：刘海 / 挖孔由 SafeArea 让位；顶栏本身贴状态栏下沿（沉浸式）。
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _MobileTopBar(title: title, onMenu: () => _scaffoldKey.currentState?.openDrawer()),
            Container(height: 1, color: palette.line),
            Expanded(
              child: _PageTransition(location: GoRouterState.of(context).uri.path, child: widget.shell),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({required this.title, required this.onMenu});

  final String title;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      height: AppMetrics.toolbarHeight,
      child: Row(
        children: [
          // app.css `.hamb`：34 方形、8 圆角。
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton(
              icon: const Icon(LucideIcons.menu, size: 17),
              color: palette.ink2,
              tooltip: '打开导航',
              onPressed: onMenu,
            ),
          ),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.ink),
            ),
          ),
          const _ThemeToggleButton(),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// 移动端抽屉：复用同一 [NavRail]，走展开态；关抽屉由 AppShell 处理。
class _MobileDrawer extends ConsumerWidget {
  const _MobileDrawer({required this.width, required this.location, required this.labels, required this.queueDepth});

  final double width;
  final _ShellLocation location;
  final bool labels;
  final int queueDepth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Drawer(
      width: width,
      backgroundColor: palette.panel,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        right: false,
        child: NavRail(
          collapsed: false,
          labels: labels,
          onToggleCollapse: () => Navigator.of(context).pop(),
          moduleIndex: location.moduleIndex,
          onSelectModule: (i) {
            Navigator.of(context).pop();
            _goModule(context, i);
          },
          viewGroupLabel: location.viewGroupLabel,
          viewItems: location.viewItems,
          activeViewId: location.viewId,
          onSelectView: (v) {
            Navigator.of(context).pop();
            _goView(context, location.moduleIndex, v);
          },
          queueCount: queueDepth,
          onOpenSettings: () {
            Navigator.of(context).pop();
            context.go('/settings');
          },
          miniPlayer: SidebarMiniPlayer(collapsed: false),
        ),
      ),
    );
  }
}
