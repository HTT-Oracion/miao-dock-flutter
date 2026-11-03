import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../features/manga/domain/not_ready_state.dart';
import 'readiness.dart';

/// 移动端**底部一级导航**（模块层）：漫画 / 音乐 / 番剧 / 设置。
///
/// 为什么是底部而不是抽屉：手机的一级入口必须**一次点击可达**；抽屉要
/// 「汉堡 → 模块」两次，且抽屉内套的是桌面侧栏内容，与移动端的信息密度不匹配。
/// 容器可横向滑动 —— 后续加模块不用改布局。
class MobileBottomNav extends ConsumerWidget {
  const MobileBottomNav({super.key, required this.moduleIndex, required this.onSelectModule});

  /// 0 漫画 / 1 音乐 / 2 番剧 / -1 设置。
  final int moduleIndex;
  final ValueChanged<int> onSelectModule;

  static const _items = [
    (0, LucideIcons.languages, 'navManga'),
    (1, LucideIcons.music, 'navMusic'),
    (2, LucideIcons.clapperboard, 'navAnime'),
    (-1, LucideIcons.settings, 'navSettings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final readiness = ref.watch(shellReadinessProvider);

    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          // 与设计稿一致：四项**均分铺满**整宽（不是居中扎堆）。
          // 用 LayoutBuilder 算每项宽度 = 可用宽 / 项数，超过最小宽度后可横滑。
          child: LayoutBuilder(
            builder: (context, constraints) {
              const minItemWidth = 62.0;
              final perItem = (constraints.maxWidth / _items.length).clamp(minItemWidth, 400.0);
              final totalWidth = perItem * _items.length;
              final scrollable = totalWidth > constraints.maxWidth;
              final row = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, icon, labelKey) in _items)
                    _BottomItem(
                      width: perItem,
                      icon: icon,
                      label: switch (labelKey) {
                        'navManga' => l10n.navManga,
                        'navMusic' => l10n.navMusic,
                        'navAnime' => l10n.navAnime,
                        _ => l10n.navSettings,
                      },
                      active: moduleIndex == index,
                      // 漫画模块的状态点：只在「能否翻译」未就绪时提示。
                      dot: index == 0 ? _dotColor(palette, readiness) : null,
                      onTap: () => onSelectModule(index),
                    ),
                ],
              );
              // 项数少时不滚动（均分铺满）；超宽时横滑，不加挤压。
              return scrollable
                  ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row)
                  : SizedBox(width: constraints.maxWidth, child: row);
            },
          ),
        ),
      ),
    );
  }

  Color? _dotColor(AppPalette palette, ReadinessLevel r) => switch (r) {
    ReadinessLevel.ready => null,
    ReadinessLevel.partial => palette.warn,
    ReadinessLevel.broken => palette.bad,
    ReadinessLevel.unconfigured => palette.mut,
  };
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.width,
    this.dot,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final double width;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 15, color: active ? palette.acc : palette.mut),
                if (dot != null)
                  Positioned(
                    right: -3,
                    top: -2,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: AppFont.px8_5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? palette.acc : palette.mut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 移动端**顶部二级标签**（模块内视图）：投放 / 队列 / 漫画库 ……
///
/// 与底部一级导航配套：一级选模块、二级选视图。横向可滑动（后续加视图不用改布局）。
/// 右侧留 `actions` 位（刷新 / 新建等视图级动作）。
class MobileViewTabs extends StatelessWidget {
  const MobileViewTabs({
    super.key,
    required this.items,
    required this.activeId,
    required this.onSelect,
    this.actions = const [],
  });

  /// （id, 标签）。
  final List<(String, String)> items;
  final String? activeId;
  final ValueChanged<String> onSelect;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              // 左右留白：首个标签不贴边（用户实测要求）。
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final (id, label) in items)
                  _TabItem(id: id, label: label, active: id == activeId, onTap: () => onSelect(id)),
              ],
            ),
          ),
          ...actions,
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.id, required this.label, required this.active, required this.onTap});

  final String id;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active ? palette.acc : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppFont.px11_5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? palette.acc : palette.mut,
          ),
        ),
      ),
    );
  }
}
