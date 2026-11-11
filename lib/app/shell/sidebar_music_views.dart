import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import '../../features/music/controller/music_providers.dart';
import '../../l10n/app_localizations.dart';
import 'view_labels.dart';

/// 音乐模块桌面侧栏视图组（设计稿 N03 / 信息架构：发现 / 我的歌单 / 本地 / 历史）。
///
/// 视图组归音乐模块所有；漫画仍需工具条页签，因此仅在壳层按模块选挂。
/// 徽标口径与原型一致：本地曲目数 / 历史条数，0 不渲染；收起态只留图标。
class SidebarMusicViews extends ConsumerWidget {
  const SidebarMusicViews({
    super.key,
    required this.activeId,
    required this.onSelect,
    required this.collapsed,
    required this.labels,
  });

  final String? activeId;
  final ValueChanged<String> onSelect;
  final bool collapsed;

  /// 设置页「侧栏展开」偏好：展开态也允许只显示图标。
  final bool labels;

  static const _items = [
    ('discover', LucideIcons.compass),
    ('playlist', LucideIcons.listMusic),
    ('local', LucideIcons.hardDrive),
    ('history', LucideIcons.history),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final counts = <String, int>{
      'local': ref.watch(musicLocalProvider).value?.length ?? 0,
      'history': ref.watch(historyFeedProvider).value?.length ?? 0,
    };

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Column(
          children: [
            for (final (id, icon) in _items)
              _ViewRow(
                icon: icon,
                label: viewLabel(l10n, id),
                active: activeId == id,
                collapsed: true,
                count: 0,
                onTap: () => onSelect(id),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              l10n.navMusic,
              style: TextStyle(fontSize: AppFont.px8_5, color: palette.mut),
            ),
          ),
          for (final (id, icon) in _items)
            _ViewRow(
              icon: icon,
              label: viewLabel(l10n, id),
              active: activeId == id,
              collapsed: false,
              showLabel: labels,
              count: counts[id] ?? 0,
              onTap: () => onSelect(id),
            ),
        ],
      ),
    );
  }
}

class _ViewRow extends StatefulWidget {
  const _ViewRow({
    required this.icon,
    required this.label,
    required this.active,
    required this.collapsed,
    required this.count,
    required this.onTap,
    this.showLabel = true,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool collapsed;
  final int count;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  State<_ViewRow> createState() => _ViewRowState();
}

class _ViewRowState extends State<_ViewRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = widget.active ? palette.acc : palette.ink2;
    final Color background;
    if (widget.active) {
      background = palette.accSoft;
    } else if (_hover) {
      background = palette.card;
    } else {
      background = Colors.transparent;
    }
    final row = AnimatedContainer(
      duration: AppMotion.hover,
      height: 34,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          // 激活态左侧 2px 竖条（设计稿 `.sb-item.on::before`）。
          AnimatedContainer(
            duration: AppMotion.hover,
            width: 2,
            height: widget.active ? 16 : 0,
            decoration: BoxDecoration(color: palette.acc, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Icon(widget.icon, size: 15, color: fg),
          if (!widget.collapsed && widget.showLabel) ...[
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFont.px11_5,
                  fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                ),
              ),
            ),
            if (widget.count > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${widget.count}',
                  style: TextStyle(fontSize: AppFont.px8_5, color: widget.active ? palette.acc : palette.mut),
                ),
              ),
          ],
        ],
      ),
    );
    final tappable = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, behavior: HitTestBehavior.opaque, child: row),
    );
    return widget.collapsed ? Tooltip(message: widget.label, child: tappable) : tappable;
  }
}
