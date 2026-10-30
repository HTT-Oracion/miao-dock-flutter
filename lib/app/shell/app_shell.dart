import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import '../../shared/widgets/app_title_bar.dart';
import '../../shared/widgets/nav_rail.dart';
import 'shell_controller.dart';

/// 响应式应用壳（设计稿 G 帧）：桌面 = 侧栏(208) + 自绘标题栏(56) + 内容；
/// 移动端 = 顶栏(52) + 抽屉导航。宽度 < 720 走移动布局。
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _breakpoint = 720.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final module = _ModuleLocation.of(GoRouterState.of(context).uri.path);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _breakpoint;
        if (wide) return _DesktopShell(navigationShell: navigationShell, module: module);
        return _MobileShell(shell: navigationShell, module: module);
      },
    );
  }
}

// ── 路由解析（壳层唯一事实：路径 → 模块 / 视图 / 标题）─────────────────────

class _ModuleLocation {
  const _ModuleLocation(this.index, this.mangaView, this.crumbs);

  /// 0 漫画 / 1 音乐 / 2 番剧 / -1 设置
  final int index;
  final String? mangaView;
  final List<String> crumbs;

  static const _moduleNames = ['漫画翻译', '音乐', '番剧'];
  static const _viewNames = {'drop': '投放', 'queue': '队列', 'library': '漫画库'};

  static _ModuleLocation of(String path) {
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    if (seg.isEmpty) return const _ModuleLocation(-1, null, []);
    const modules = {'manga': 0, 'music': 1, 'anime': 2};
    final index = modules[seg[0]] ?? -1;
    final crumbs = <String>[if (index >= 0) _moduleNames[index] else if (seg[0] == 'settings') '设置'];
    String? mangaView;
    if (seg[0] == 'manga' && seg.length > 1 && _viewNames.containsKey(seg[1])) {
      mangaView = seg[1];
      crumbs.add(_viewNames[seg[1]]!);
    }
    return _ModuleLocation(index, mangaView, crumbs);
  }
}

// ── 桌面壳 ────────────────────────────────────────────────────────────────

class _DesktopShell extends ConsumerWidget {
  const _DesktopShell({required this.navigationShell, required this.module});

  final StatefulNavigationShell navigationShell;
  final _ModuleLocation module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(navCollapsedProvider);
    return Row(
      children: [
        NavRail(
          collapsed: collapsed,
          onToggleCollapse: () => ref.read(navCollapsedProvider.notifier).toggle(),
          moduleIndex: module.index,
          onSelectModule: (i) => context.go(switch (i) {
            0 => '/manga',
            1 => '/music',
            _ => '/anime',
          }),
          mangaView: module.mangaView,
          onSelectView: (v) => context.go('/manga/$v'),
        ),
        const VerticalDivider(width: 1, color: AppTokens.divider),
        Expanded(
          child: Column(
            children: [
              AppTitleBar(
                breadcrumb: _Crumbs(crumbs: module.crumbs),
                actions: [
                  IconButton(
                    icon: const Icon(LucideIcons.settings, size: 15),
                    color: AppTokens.textSecondary,
                    tooltip: '设置',
                    onPressed: () => context.go('/settings'),
                  ),
                ],
              ),
              const Divider(height: 1, color: AppTokens.divider),
              Expanded(
                child: Material(color: AppTokens.pageBg, child: navigationShell),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Crumbs extends StatelessWidget {
  const _Crumbs({required this.crumbs});

  final List<String> crumbs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, c) in crumbs.indexed) ...[
          if (i > 0) ...[
            const SizedBox(width: 9),
            const Icon(LucideIcons.chevronRight, size: 10, color: AppTokens.textSecondary),
            const SizedBox(width: 9),
          ],
          Text(
            c,
            style: TextStyle(
              fontSize: 13,
              fontWeight: i == crumbs.length - 1 ? FontWeight.w600 : FontWeight.w400,
              color: i == crumbs.length - 1 ? AppTokens.textPrimary : AppTokens.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

// ── 移动端壳 ──────────────────────────────────────────────────────────────

class _MobileShell extends StatelessWidget {
  const _MobileShell({required this.shell, required this.module});

  final StatefulNavigationShell shell;
  final _ModuleLocation module;

  @override
  Widget build(BuildContext context) {
    final title = module.crumbs.isEmpty ? '喵坞' : module.crumbs.join(' · ');
    return Scaffold(
      drawer: _NavDrawer(module: module),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.menu, size: 18),
                    color: AppTokens.textSecondary,
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.settings, size: 16),
                    color: AppTokens.textSecondary,
                    onPressed: () => context.go('/settings'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTokens.divider),
            Expanded(child: shell),
          ],
        ),
      ),
    );
  }
}

class _NavDrawer extends StatelessWidget {
  const _NavDrawer({required this.module});

  final _ModuleLocation module;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppTokens.navBg,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 232,
          child: NavRail(
            collapsed: false,
            onToggleCollapse: () {},
            moduleIndex: module.index,
            onSelectModule: (i) => context.go(switch (i) {
              0 => '/manga',
              1 => '/music',
              _ => '/anime',
            }),
            mangaView: module.mangaView,
            onSelectView: (v) => context.go('/manga/$v'),
          ),
        ),
      ),
    );
  }
}
