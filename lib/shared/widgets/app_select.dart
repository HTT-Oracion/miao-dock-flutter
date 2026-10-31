import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';

/// 下拉选择（design.html `.select`，一比一）。
///
/// ```css
/// .select{display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 10px;
///         border-radius:6px;background:var(--card);border:1px solid var(--line2);
///         font-size:10px;color:var(--ink);cursor:pointer}
/// .select svg{color:var(--mut)}
/// ```
///
/// 用 `PopupMenuButton` 而非 `DropdownButton`：后者的菜单项高度 / 内距由 Material
/// 主题决定，改不到稿子的比例；前者可以完全自绘菜单。
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width,
    this.enabled = true,
  });

  final T value;

  /// 值与显示文案。
  final List<(T, String)> items;
  final ValueChanged<T>? onChanged;

  /// 固定宽度；null = 自适应内容。
  final double? width;
  final bool enabled;

  String get _label {
    for (final (v, label) in items) {
      if (v == value) return label;
    }
    return items.isEmpty ? '' : items.first.$2;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return PopupMenuButton<T>(
      enabled: enabled && onChanged != null,
      tooltip: '',
      offset: const Offset(0, 30),
      color: palette.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
        side: BorderSide(color: palette.line2),
      ),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final (v, label) in items)
          PopupMenuItem<T>(
            value: v,
            height: 30,
            padding: EdgeInsets.zero,
            child: _MenuRow(label: label, selected: v == value),
          ),
      ],
      child: Container(
        height: 28,
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: palette.card,
          border: Border.all(color: palette.line2),
          borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: enabled ? palette.ink : palette.mut),
              ),
            ),
            const SizedBox(width: 6),
            Icon(LucideIcons.chevronDown, size: 10, color: palette.mut),
          ],
        ),
      ),
    );
  }
}

/// 菜单里的一行（与 `.select` 同字号）。
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: selected ? palette.acc : palette.ink,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (selected) Icon(LucideIcons.check, size: 10, color: palette.acc),
        ],
      ),
    );
  }
}
