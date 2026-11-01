import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 表格列定义：width 为固定像素宽；flex 列占满剩余宽（width 留 0）。
class AppTableColumn {
  const AppTableColumn(this.header, {this.width = 0, this.flex = false});

  final String header;
  final double width;
  final bool flex;
}

/// 通用表格卡（设计稿 TableCard）：圆角卡容器 + 40 表头 + 58px 行 + 分隔线。
/// 勾选列等前置件经 [headerLeading] / [rowLeading] 注入（36px 宽）；
/// [rowBuilder] 按列返回单元格，与 [columns] 一一对应。
class AppTable extends StatelessWidget {
  const AppTable({
    super.key,
    required this.columns,
    required this.rowCount,
    required this.rowBuilder,
    this.headerLeading,
    this.rowLeading,
    this.onRowTap,
    this.rowColor,
    this.rowAccentColor,
  });

  final List<AppTableColumn> columns;
  final int rowCount;
  final List<Widget> Function(BuildContext context, int index) rowBuilder;
  final Widget? headerLeading;

  /// 按行构建的前置件（36px 宽），如行勾选框。
  final Widget? Function(BuildContext context, int index)? rowLeading;

  /// 整行可点选（命中区大，不必精确点中勾选框，H Note 03）。
  final void Function(BuildContext context, int index)? onRowTap;

  /// 行底色（如多选选中态）。
  final Color? Function(BuildContext context, int index)? rowColor;

  /// 行左侧 3px 色条（与漫画库选中样式同语言）。
  final Color? Function(BuildContext context, int index)? rowAccentColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.divider)),
            ),
            child: Row(
              children: [
                if (headerLeading != null) SizedBox(width: 36, child: headerLeading!),
                for (final c in columns)
                  c.flex
                      ? Expanded(
                          child: Text(c.header, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                        )
                      : SizedBox(
                          width: c.width,
                          child: Text(c.header, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                        ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: rowCount,
              itemExtent: 58,
              itemBuilder: (context, i) {
                final cells = rowBuilder(context, i);
                final color = rowColor?.call(context, i);
                final accent = rowAccentColor?.call(context, i);
                final leading = rowLeading?.call(context, i);
                final row = Container(
                  height: 58,
                  padding: EdgeInsets.only(left: accent != null ? 11 : 14, right: 14),
                  decoration: BoxDecoration(
                    color: color,
                    border: Border(
                      bottom: BorderSide(color: palette.divider),
                      left: accent != null ? BorderSide(color: accent, width: 3) : BorderSide.none,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (leading != null) SizedBox(width: 36, child: leading),
                      for (final (j, cell) in cells.indexed)
                        columns[j].flex ? Expanded(child: cell) : SizedBox(width: columns[j].width, child: cell),
                    ],
                  ),
                );
                final tap = onRowTap;
                return tap == null ? row : InkWell(onTap: () => tap(context, i), child: row);
              },
            ),
          ),
        ],
      ),
    );
  }
}
