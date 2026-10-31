import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/shell/shell_controller.dart';
import '../../app/shell/view_labels.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';

/// 应用侧栏（design.html §03 / `app.css .sidebar`）：
/// 展开 208 / 收起 68；品牌 52 → 分隔线 → 模块 → 分隔线 → 视图组 → 弹性 → MiniPlayer → 设置脚。
///
/// 纯展示件：路由状态与回调由 AppShell 注入；hover / 动效在本件内完成。
/// 图标按 design.html §05 指定（`languages` / `music` / `clapperboard` /
/// `folder-up` / `list-minus` / `book-text`，禁用已废弃的 `tv` / `upload` / `list` /
/// `layout-grid` / `more-horizontal`）。
class NavRail extends StatelessWidget {
  const NavRail({
    super.key,
    required this.collapsed,
    required this.labels,
    required this.onToggleCollapse,
    required this.moduleIndex,
    required this.onSelectModule,
    required this.viewGroupLabel,
    required this.viewItems,
    required this.activeViewId,
    required this.onSelectView,
    required this.queueCount,
    required this.onOpenSettings,
    this.miniPlayer,
    this.topInset = 0,
  });

  /// 宽度折叠态（208 ⇄ 68）。
  final bool collapsed;

  /// 展开态下是否渲染文字标签（原项目 `sidebar-labels` 偏好）。
  final bool labels;

  final VoidCallback onToggleCollapse;

  /// 当前激活模块：0 漫画翻译 / 1 音乐 / 2 番剧；-1 = 设置（无激活模块）。
  final int moduleIndex;
  final ValueChanged<int> onSelectModule;

  /// 视图组标题（= 当前模块名，原项目 `grp-label`）。
  final String viewGroupLabel;

  /// 视图项（按模块注入，域常量见 [mangaViews] / [musicViews]）。
  final List<SidebarViewItem> viewItems;

  /// 当前视图 id（`drop` / `queue` / `library` / `discover` …）；null = 非模块页。
  final String? activeViewId;
  final ValueChanged<String> onSelectView;

  /// 队列视图的待办计数（原项目口径 `running + queued`，不是列表长度）。
  final int queueCount;

  final VoidCallback onOpenSettings;

  /// MiniPlayer 槽位。音乐域尚未接真实播放状态时传 null —— **不渲染**，
  /// 绝不写死假曲目。
  final Widget? miniPlayer;

  /// 顶部安全区 / 红绿灯避让高度（桌面 macOS 传红绿灯带，移动端传系统状态栏）。
  final double topInset;

  double get _width => collapsed ? AppMetrics.sidebarCollapsedWidth : AppMetrics.sidebarWidth;

  @override
  Widget build(BuildContext context) {
    // 宽度做 320ms 形变（design.html §06），但内容按**目标**宽度布局、
    // 且用 OverflowBox 解除父级窄约束 —— 否则动画中途文本会被挤进 50px 宽的列而溢出。
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _width),
      duration: AppMotion.morph,
      curve: AppMotion.morphCurve,
      builder: (context, width, _) => SizedBox(
        width: width,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: _width,
            maxWidth: _width,
            child: _RailBody(
              width: _width,
              collapsed: collapsed,
              labels: labels,
              onToggleCollapse: onToggleCollapse,
              moduleIndex: moduleIndex,
              onSelectModule: onSelectModule,
              viewGroupLabel: viewGroupLabel,
              viewItems: viewItems,
              activeViewId: activeViewId,
              onSelectView: onSelectView,
              queueCount: queueCount,
              onOpenSettings: onOpenSettings,
              miniPlayer: miniPlayer,
              topInset: topInset,
            ),
          ),
        ),
      ),
    );
  }
}

/// 侧栏主体（按目标宽度布局，不参与宽度补间）。
class _RailBody extends StatelessWidget {
  const _RailBody({
    required this.width,
    required this.collapsed,
    required this.labels,
    required this.onToggleCollapse,
    required this.moduleIndex,
    required this.onSelectModule,
    required this.viewGroupLabel,
    required this.viewItems,
    required this.activeViewId,
    required this.onSelectView,
    required this.queueCount,
    required this.onOpenSettings,
    required this.miniPlayer,
    required this.topInset,
  });

  final double width;
  final bool collapsed;
  final bool labels;
  final VoidCallback onToggleCollapse;
  final int moduleIndex;
  final ValueChanged<int> onSelectModule;
  final String viewGroupLabel;
  final List<SidebarViewItem> viewItems;
  final String? activeViewId;
  final ValueChanged<String> onSelectView;
  final int queueCount;
  final VoidCallback onOpenSettings;
  final Widget? miniPlayer;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(
      color: palette.panel,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (topInset > 0) SizedBox(height: topInset),
            _Brand(collapsed: collapsed, labels: labels, onToggleCollapse: onToggleCollapse),
            const _RailDivider(inset: 10),
            _ModuleGroup(
              collapsed: collapsed,
              labels: labels,
              moduleIndex: moduleIndex,
              onSelectModule: onSelectModule,
            ),
            const _RailDivider(inset: 10),
            if (!collapsed)
              _ViewGroup(
                label: viewGroupLabel,
                labels: labels,
                items: viewItems,
                activeId: activeViewId,
                queueCount: queueCount,
                onSelect: onSelectView,
              ),
            const Spacer(),
            ?miniPlayer,
            _NavFoot(collapsed: collapsed, labels: labels, onOpenSettings: onOpenSettings),
          ],
        ),
      ),
    );
  }
}

/// 分隔线（`app.css .nav-div`：1px、`--line`、上下 8）。
class _RailDivider extends StatelessWidget {
  const _RailDivider({required this.inset});

  final double inset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: inset),
      child: Container(height: 1, color: AppPalette.of(context).line),
    );
  }
}

// ── 品牌 ─────────────────────────────────────────────────────────────────

class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed, required this.labels, required this.onToggleCollapse});

  final bool collapsed;
  final bool labels;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    // 收起态：品牌竖排（logo 在上、展开钮在下），与 app.css `.sidebar.mini .brand` 同构。
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Column(
          children: [
            const _MiaoLogo(size: 32),
            const SizedBox(height: 8),
            _CollapseButton(
              icon: LucideIcons.panelLeftOpen,
              tooltip: AppLocalizations.of(context).actionExpandSidebar,
              onTap: onToggleCollapse,
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: AppMetrics.brandHeight,
      child: Padding(
        // 左 12 / 右 6：右侧折叠钮自身有 4 的内边距，合计仍落在 208 内不溢出。
        padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
        child: Row(
          children: [
            const _MiaoLogo(size: 32),
            if (labels) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.brandName,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      l10n.brandTagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, color: palette.mut),
                    ),
                  ],
                ),
              ),
            ] else
              const Spacer(),
            _CollapseButton(
              icon: LucideIcons.panelLeftClose,
              tooltip: AppLocalizations.of(context).actionCollapseSidebar,
              onTap: onToggleCollapse,
            ),
          ],
        ),
      ),
    );
  }
}

/// 折叠按钮（`app.css .collapse-btn`：`--mut` 前景、hover 变 `--hi` 底）。
class _CollapseButton extends StatefulWidget {
  const _CollapseButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_CollapseButton> createState() => _CollapseButtonState();
}

class _CollapseButtonState extends State<_CollapseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppMotion.hover,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _hover ? palette.hi : Colors.transparent,
              borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
            ),
            child: Icon(widget.icon, size: 14, color: _hover ? palette.ink2 : palette.mut),
          ),
        ),
      ),
    );
  }
}

class _MiaoLogo extends StatelessWidget {
  const _MiaoLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // `app.css .logo-img`：32 方形、圆角 8、cover。
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/icons/miao-logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: palette.accSoft,
          child: Icon(LucideIcons.languages, size: size * 0.55, color: palette.acc),
        ),
      ),
    );
  }
}

// ── 模块 ─────────────────────────────────────────────────────────────────

/// 模块项（`app.css .mod-item`）：50 高、8 圆角、激活 `--acc-soft` + 左 3px 橙条。
class _ModuleGroup extends StatelessWidget {
  const _ModuleGroup({
    required this.collapsed,
    required this.labels,
    required this.moduleIndex,
    required this.onSelectModule,
  });

  final bool collapsed;
  final bool labels;
  final int moduleIndex;
  final ValueChanged<int> onSelectModule;

  /// 顺序即侧栏渲染顺序（design.html：漫画翻译 / 音乐 / 番剧）。
  /// 模块图标；顺序固定（design.html：漫画翻译 / 音乐 / 番剧）。
  static const _icons = [LucideIcons.languages, LucideIcons.music, LucideIcons.clapperboard];

  /// 模块序号 → 文案（0 漫画翻译 / 1 音乐 / 2 番剧）。
  static String _moduleLabel(AppLocalizations l10n, int index) => switch (index) {
    0 => l10n.navManga,
    1 => l10n.navMusic,
    _ => l10n.navAnime,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 10),
      child: Column(
        children: [
          for (final (i, icon) in _icons.indexed)
            _ModuleItem(
              icon: icon,
              label: _moduleLabel(AppLocalizations.of(context), i),
              active: moduleIndex == i,
              collapsed: collapsed,
              showLabel: labels,
              onTap: () => onSelectModule(i),
            ),
        ],
      ),
    );
  }
}

class _ModuleItem extends StatefulWidget {
  const _ModuleItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.collapsed,
    required this.showLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool collapsed;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  State<_ModuleItem> createState() => _ModuleItemState();
}

class _ModuleItemState extends State<_ModuleItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = widget.active ? palette.acc : palette.ink2;
    final Color background;
    if (widget.active) {
      background = palette.accSoft;
    } else if (_hover) {
      background = palette.card; // app.css `.mod-item:hover{background:var(--card)}`
    } else {
      background = Colors.transparent;
    }
    final showText = !widget.collapsed && widget.showLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: widget.collapsed ? widget.label : '',
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: AppMotion.hover,
              height: 50,
              decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
              child: Stack(
                children: [
                  if (widget.active)
                    Positioned(
                      left: 0,
                      top: 13,
                      child: Container(
                        width: 3,
                        height: 24,
                        decoration: BoxDecoration(color: palette.acc, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  Center(
                    child: showText
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Icon(widget.icon, size: 17, color: fg),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    widget.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                                      color: widget.active ? palette.ink : palette.ink2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Icon(widget.icon, size: 17, color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 视图组 ───────────────────────────────────────────────────────────────

/// 视图组（`app.css .grp-label` + `.view-item`）：标题 8 号字距 1，项 34 高。
class _ViewGroup extends StatelessWidget {
  const _ViewGroup({
    required this.label,
    required this.labels,
    required this.items,
    required this.activeId,
    required this.queueCount,
    required this.onSelect,
  });

  final String label;
  final bool labels;
  final List<SidebarViewItem> items;
  final String? activeId;
  final int queueCount;
  final ValueChanged<String> onSelect;

  /// 视图 id → 图标（design.html §05 指定值）。
  static const _icons = {
    'drop': LucideIcons.folderUp,
    'queue': LucideIcons.listMinus,
    'library': LucideIcons.bookText,
    'discover': LucideIcons.compass,
    'playlist': LucideIcons.listMusic,
    'local': LucideIcons.hardDrive,
    'history': LucideIcons.history,
  };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (labels)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
              child: Text(label, style: TextStyle(fontSize: 8, letterSpacing: 1, color: palette.mut)),
            ),
          for (final item in items)
            _ViewItem(
              icon: _icons[item.id] ?? LucideIcons.listMinus,
              label: viewLabel(AppLocalizations.of(context), item.id),
              active: activeId == item.id,
              showLabel: labels,
              count: item.id == 'queue' ? queueCount : null,
              onTap: () => onSelect(item.id),
            ),
        ],
      ),
    );
  }
}

class _ViewItem extends StatefulWidget {
  const _ViewItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.showLabel,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool showLabel;
  final VoidCallback onTap;
  final int? count;

  @override
  State<_ViewItem> createState() => _ViewItemState();
}

class _ViewItemState extends State<_ViewItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final Color background;
    if (widget.active || _hover) {
      background = palette.card; // `.view-item.active{background:var(--card)}`，hover 同值
    } else {
      background = Colors.transparent;
    }
    final fg = widget.active ? palette.ink : palette.ink2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.hover,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Icon(widget.icon, size: 13, color: widget.active ? palette.acc : palette.ink2),
                if (widget.showLabel) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                        color: fg,
                      ),
                    ),
                  ),
                  if ((widget.count ?? 0) > 0)
                    Text(
                      '${widget.count}',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: palette.acc),
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

// ── 设置脚 ───────────────────────────────────────────────────────────────

/// 设置脚（`app.css .nav-foot`）：40 高、`--ink2`、右侧服务状态点。
class _NavFoot extends StatefulWidget {
  const _NavFoot({required this.collapsed, required this.labels, required this.onOpenSettings});

  final bool collapsed;
  final bool labels;
  final VoidCallback onOpenSettings;

  @override
  State<_NavFoot> createState() => _NavFootState();
}

class _NavFootState extends State<_NavFoot> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final showText = !widget.collapsed && widget.labels;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onOpenSettings,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.hover,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _hover ? palette.card : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.settings, size: 14, color: palette.ink2),
                if (showText) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).navSettings,
                      style: TextStyle(fontSize: 11, color: palette.ink2),
                    ),
                  ),
                  // 服务状态点：色相只由圆点承载，文字保持中性（design.html §02）。
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: palette.good, shape: BoxShape.circle),
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
