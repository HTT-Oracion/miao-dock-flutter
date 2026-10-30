import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';

/// 应用侧栏（设计稿 G Nav，展开 208 / 收起 64）：品牌 + 模块 + 视图 + MiniPlayer 占位 + 状态脚。
/// 纯展示件：路由状态与回调由 AppShell 注入，收起状态存 shell 层 controller。
class NavRail extends StatelessWidget {
  const NavRail({
    super.key,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.moduleIndex,
    required this.onSelectModule,
    required this.mangaView,
    required this.onSelectView,
  });

  final bool collapsed;
  final VoidCallback onToggleCollapse;

  /// 当前激活模块：0 漫画翻译 / 1 音乐 / 2 番剧；-1 = 设置（无激活模块）。
  final int moduleIndex;
  final ValueChanged<int> onSelectModule;

  /// 当前漫画视图：drop / queue / library；null = 非漫画模块。
  final String? mangaView;
  final ValueChanged<String> onSelectView;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: collapsed ? 64 : 208,
      color: AppTokens.navBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Brand(collapsed: collapsed, onToggleCollapse: onToggleCollapse),
          const SizedBox(height: 6),
          _Modules(collapsed: collapsed, moduleIndex: moduleIndex, onSelect: onSelectModule),
          const Divider(height: 1, color: AppTokens.divider),
          if (!collapsed) ...[const _ViewsLabel(), _Views(active: mangaView, onSelect: onSelectView)],
          const Spacer(),
          _MiniPlayerPlaceholder(collapsed: collapsed),
          _NavFoot(collapsed: collapsed),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed, required this.onToggleCollapse});

  final bool collapsed;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: AppTokens.accent, borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: const Text(
                '喵',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTokens.pageBg),
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '喵坞',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.panelLeftClose, size: 14),
                color: AppTokens.textSecondary,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                onPressed: onToggleCollapse,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Modules extends StatelessWidget {
  const _Modules({required this.collapsed, required this.moduleIndex, required this.onSelect});

  final bool collapsed;
  final int moduleIndex;
  final ValueChanged<int> onSelect;

  static const _items = [(LucideIcons.bookImage, '漫画翻译'), (LucideIcons.music, '音乐'), (LucideIcons.tv, '番剧')];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (final (i, item) in _items.indexed)
            _NavModuleItem(
              icon: item.$1,
              label: item.$2,
              active: moduleIndex == i,
              collapsed: collapsed,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _NavModuleItem extends StatelessWidget {
  const _NavModuleItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.collapsed,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: active ? AppTokens.navActive : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: collapsed ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: active ? AppTokens.accent : AppTokens.textSecondary),
                if (!collapsed) ...[
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: active ? AppTokens.textPrimary : AppTokens.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewsLabel extends StatelessWidget {
  const _ViewsLabel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 8, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('视图', style: TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
      ),
    );
  }
}

class _Views extends StatelessWidget {
  const _Views({required this.active, required this.onSelect});

  final String? active;
  final ValueChanged<String> onSelect;

  static const _items = [
    ('drop', LucideIcons.fileUp, '投放'),
    ('queue', LucideIcons.layers, '队列'),
    ('library', LucideIcons.library, '漫画库'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (final (view, icon, label) in _items)
            _NavViewItem(icon: icon, label: label, active: active == view, onTap: () => onSelect(view)),
        ],
      ),
    );
  }
}

class _NavViewItem extends StatelessWidget {
  const _NavViewItem({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? AppTokens.divider : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(icon, size: 14, color: active ? AppTokens.accent : AppTokens.textSecondary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: active ? AppTokens.textPrimary : AppTokens.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerPlaceholder extends StatelessWidget {
  const _MiniPlayerPlaceholder({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(9),
      child: Container(
        height: 87,
        decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.center,
        child: collapsed
            ? const Icon(LucideIcons.music, size: 14, color: AppTokens.textSecondary)
            : const Text('MiniPlayer', style: TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
      ),
    );
  }
}

class _NavFoot extends StatelessWidget {
  const _NavFoot({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: AppTokens.success, shape: BoxShape.circle),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 8),
            const Expanded(
              child: Text('服务状态', style: TextStyle(fontSize: 12, color: AppTokens.textSecondary)),
            ),
          ],
        ],
      ),
    );
  }
}
