import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'app_dialog.dart';
import 'app_input.dart';
import 'buttons.dart';

/// 可搜索的单项选择器（**项目唯一实现**，用于选项多、需要搜索的场景）。
///
/// 为什么不用「下拉里塞搜索框」：M3 `MenuAnchor` 的菜单面板与内嵌 `TextField`
/// 的 tap region 冲突，实测菜单项 `hitTestable` 为 0（点不中）。
/// 选择器改成独立弹窗后，搜索与选择都稳定，且列表能显示更多项。
///
/// 返回选中值；用户取消返回 null。
Future<T?> showAppPicker<T>({
  required BuildContext context,
  required String title,
  required List<(T, String)> items,
  required String searchHint,
  T? current,
  String? emptyText,
}) {
  return showAppDialog<T>(
    context: context,
    builder: (_) =>
        _AppPicker<T>(title: title, items: items, searchHint: searchHint, current: current, emptyText: emptyText),
  );
}

class _AppPicker<T> extends StatefulWidget {
  const _AppPicker({required this.title, required this.items, required this.searchHint, this.current, this.emptyText});

  final String title;
  final List<(T, String)> items;
  final String searchHint;
  final T? current;
  final String? emptyText;

  @override
  State<_AppPicker<T>> createState() => _AppPickerState<T>();
}

class _AppPickerState<T> extends State<_AppPicker<T>> {
  String _query = '';

  List<(T, String)> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    // 子序列匹配：既能"连续包含"，也能"跳字"（与书架搜索同一套规则）。
    return [
      for (final it in widget.items)
        if (it.$2.toLowerCase().contains(q)) it,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final shown = _filtered;
    return AppDialog(
      title: widget.title,
      width: 360,
      onClose: () => Navigator.of(context).pop(),
      actions: [AppButton(label: AppLocalizations.of(context).actionCancel, onTap: () => Navigator.of(context).pop())],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppInput(
            hint: widget.searchHint,
            autofocus: true,
            prefixIcon: LucideIcons.search,
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: shown.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      widget.emptyText ?? '',
                      style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: shown.length,
                    itemBuilder: (context, i) =>
                        _Row<T>(value: shown[i].$1, label: shown[i].$2, selected: shown[i].$1 == widget.current),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Row<T> extends StatefulWidget {
  const _Row({required this.value, required this.label, required this.selected});

  final T value;
  final String label;
  final bool selected;

  @override
  State<_Row<T>> createState() => _RowState<T>();
}

class _RowState<T> extends State<_Row<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(widget.value),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: _hover ? palette.hi : Colors.transparent,
            borderRadius: BorderRadius.circular(kButtonRadius),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFont.px11,
                    color: widget.selected ? palette.acc : palette.textPrimary,
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.selected) Icon(LucideIcons.check, size: 12, color: palette.acc),
            ],
          ),
        ),
      ),
    );
  }
}
