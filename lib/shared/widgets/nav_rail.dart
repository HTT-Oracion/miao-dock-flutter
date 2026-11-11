import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import '../../features/manga/domain/not_ready_state.dart';
import '../../l10n/app_localizations.dart';

/// 应用侧栏（design.html §03 / 重设计稿 2026-11-07）：
/// 展开 208 / 收起 68；品牌 → 模块组 → 弹性 → MiniPlayer → 设置脚。
/// 视图组已迁到工具条页签（[ShellViewTabs]），侧栏只保留模块级导航。
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
    required this.queueCount,
    required this.onOpenSettings,
    this.readiness = ReadinessLevel.unconfigured,
    this.miniPlayer,
    this.sourceGroup,
    this.viewGroup,
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

  /// 队列视图的待办计数（原项目口径 `running + queued`，不是列表长度）。
  /// 视图组迁去工具条页签后，徽标落在漫画模块项上（功能零删减）。
  final int queueCount;

  final VoidCallback onOpenSettings;

  /// 「能否翻译」四色（D-012）—— 取代原「服务已启动」假绿点。
  final ReadinessLevel readiness;

  /// MiniPlayer 槽位。音乐域尚未接真实播放状态时传 null —— **不渲染**，
  /// 绝不写死假曲目。
  final Widget? miniPlayer;

  /// 模块附属组槽位（音乐模块 = 音源组，由壳层注入；shared 不 import features）。
  final Widget? sourceGroup;

  /// 模块内视图组槽位（音乐模块 = 发现 / 我的歌单 / 本地 / 历史）。
  ///
  /// 漫画模块的视图仍由工具条页签承担；音乐设计稿把视图放回侧栏，
  /// 因此这里做成可选槽位，按模块注入，不强行改另一模块的信息架构。
  final Widget? viewGroup;

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
              readiness: readiness,
              queueCount: queueCount,
              onOpenSettings: onOpenSettings,
              miniPlayer: miniPlayer,
              sourceGroup: sourceGroup,
              viewGroup: viewGroup,
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
    required this.readiness,
    required this.onSelectModule,
    required this.queueCount,
    required this.onOpenSettings,
    required this.miniPlayer,
    required this.sourceGroup,
    required this.viewGroup,
    required this.topInset,
  });

  final double width;
  final bool collapsed;
  final bool labels;
  final VoidCallback onToggleCollapse;
  final int moduleIndex;
  final ValueChanged<int> onSelectModule;
  final ReadinessLevel readiness;
  final int queueCount;
  final VoidCallback onOpenSettings;

  /// 「能否翻译」四色（D-012）—— 取代原「服务已启动」假绿点。
  final Widget? miniPlayer;

  /// 模块附属组槽位（音乐模块 = 音源组）。
  final Widget? sourceGroup;

  /// 模块内视图组槽位（音乐模块）。
  final Widget? viewGroup;
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
              queueCount: queueCount,
            ),
            // 模块内视图组（音乐设计稿把 4 个视图放在侧栏；漫画仍走工具条页签）。
            if (viewGroup != null) ...[const _RailDivider(inset: 10), viewGroup!],
            // 模块附属组：音乐模块激活时渲染音源组（收起态由壳层注入 mini 版）。
            if (sourceGroup != null) ...[const _RailDivider(inset: 10), sourceGroup!],
            const Spacer(),
            // 迷你播放器：有播放状态渲染真数据；无状态渲染空态占位（设计稿
            // 「未在播放 · 迷你播放器」——不写死曲目，但让槽位在版面上可见）。
            ?miniPlayer,
            if (miniPlayer == null && !collapsed) const _MiniPlayerStub(),
            if (miniPlayer == null) const SizedBox(height: 8),
            _NavFoot(
              collapsed: collapsed,
              labels: labels,
              onOpenSettings: onOpenSettings,
              readiness: readiness,
              settingsActive: moduleIndex < 0,
            ),
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
                      style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      l10n.brandTagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px9, color: palette.mut),
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
    required this.queueCount,
  });

  final bool collapsed;
  final bool labels;
  final int moduleIndex;
  final ValueChanged<int> onSelectModule;

  /// 队列待办计数（原视图组徽标迁移：视图组去工具条后落在漫画模块项上）。
  final int queueCount;

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
              count: i == 0 ? queueCount : null,
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
    this.count,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool collapsed;
  final bool showLabel;
  final VoidCallback onTap;

  /// 待办徽标（仅漫画模块）：>0 才渲染，不显示 0。
  final int? count;

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
                                      fontSize: AppFont.px12,
                                      fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                                      color: widget.active ? palette.ink : palette.ink2,
                                    ),
                                  ),
                                ),
                                if ((widget.count ?? 0) > 0)
                                  Text(
                                    '${widget.count}',
                                    style: TextStyle(
                                      fontSize: AppFont.px9,
                                      fontWeight: FontWeight.w600,
                                      color: palette.acc,
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

// ── 迷你播放器空态（重设计稿：未在播放 · 迷你播放器）──────────────────

/// 空态占位：不写死曲目，但让槽位可见 —— 用户不用猜「这块是干嘛的」。
class _MiniPlayerStub extends StatelessWidget {
  const _MiniPlayerStub();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: palette.card,
          border: Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: palette.accSoft, borderRadius: BorderRadius.circular(6)),
              child: Icon(LucideIcons.music, size: 14, color: palette.mut),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).miniPlayerIdle,
                    style: TextStyle(fontSize: AppFont.px10, fontWeight: FontWeight.w600, color: palette.ink2),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    AppLocalizations.of(context).miniPlayerHint,
                    style: TextStyle(fontSize: AppFont.px8_5, color: palette.mut),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 设置脚 ───────────────────────────────────────────────────────────────

/// 设置脚（`app.css .nav-foot`）：40 高、`--ink2`、右侧服务状态点。
class _NavFoot extends StatefulWidget {
  const _NavFoot({
    required this.collapsed,
    required this.labels,
    required this.onOpenSettings,
    required this.readiness,
    this.settingsActive = false,
  });

  final bool collapsed;
  final bool labels;
  final VoidCallback onOpenSettings;

  /// 「能否翻译」四色（D-012）—— 取代原「服务已启动」假绿点。
  final ReadinessLevel readiness;

  /// 当前是否在设置页（决定底部设置项高亮）。
  final bool settingsActive;

  @override
  State<_NavFoot> createState() => _NavFootState();
}

class _NavFootState extends State<_NavFoot> {
  bool _hover = false;

  Color _readinessColor(AppPalette palette) => switch (widget.readiness) {
    ReadinessLevel.ready => palette.good,
    ReadinessLevel.partial => palette.warn,
    ReadinessLevel.broken => palette.bad,
    ReadinessLevel.unconfigured => palette.mut,
  };

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
              // hover 与「当前页」共用同一个容器与内距 —— 两处区域必须一致。
              color: (_hover || widget.settingsActive) ? palette.card : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.settings, size: 14, color: widget.settingsActive ? palette.acc : palette.ink2),
                if (showText) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).navSettings,
                      style: TextStyle(
                        fontSize: AppFont.px11,
                        color: widget.settingsActive ? palette.ink : palette.ink2,
                        fontWeight: widget.settingsActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  // 「能否翻译」四色点：色相只由圆点承载，文字保持中性（design.html §02）。
                  // 🔴 不再用写死的绿：那会让服务挂了也显示绿色。
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: _readinessColor(palette), shape: BoxShape.circle),
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
