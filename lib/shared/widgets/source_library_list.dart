import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import '../../shared/domain/source_library.dart';
import 'buttons.dart';
import 'skeleton.dart';

/// 源仓库列表 + 单行：漫画源与音乐源**共用同一实现**。
///
/// 仓库在两个模块语义一致（一个 index.json → 若干可安装的源），所以整块 UI
/// 连同空态、加载态、错误态都由本组件决定，调用方只接数据与三个回调。
class SourceLibraryList extends StatelessWidget {
  const SourceLibraryList({
    super.key,
    required this.libraries,
    required this.loading,
    required this.error,
    required this.emptyLabel,
    required this.errorLabel,
    required this.busyId,
    required this.onBrowse,
    required this.onDelete,
  });

  final List<SourceLibrary> libraries;
  final bool loading;
  final bool error;
  final String emptyLabel;
  final String errorLabel;
  final String? busyId;
  final ValueChanged<SourceLibrary> onBrowse;
  final ValueChanged<SourceLibrary> onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 180, height: 10)),
      );
    }
    if (error) {
      return Text(
        errorLabel,
        style: TextStyle(fontSize: AppFont.px10_5, color: palette.bad),
      );
    }
    if (libraries.isEmpty) {
      return Text(
        emptyLabel,
        style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
      );
    }
    return Column(
      children: [
        for (final library in libraries)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SourceLibraryRow(
              library: library,
              busy: busyId == library.id,
              onBrowse: () => onBrowse(library),
              onDelete: () => onDelete(library),
            ),
          ),
      ],
    );
  }
}

/// 单条源仓库：图标 + 名称/域名 + 刷新 + 删除。
class SourceLibraryRow extends StatelessWidget {
  const SourceLibraryRow({
    super.key,
    required this.library,
    required this.busy,
    required this.onBrowse,
    required this.onDelete,
  });

  final SourceLibrary library;
  final bool busy;
  final VoidCallback onBrowse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final host = Uri.tryParse(library.url)?.host ?? library.url;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: palette.navBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.line2),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.library, size: 16, color: palette.acc),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: busy ? null : onBrowse,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    library.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px11_5, fontWeight: FontWeight.w600, color: palette.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                  ),
                ],
              ),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
            )
          else
            AppButton(
              icon: LucideIcons.refreshCw,
              onTap: onBrowse,
              variant: AppButtonVariant.ghost,
              width: 30,
              height: 30,
              horizontalPadding: 0,
            ),
          AppButton(
            icon: LucideIcons.trash2,
            onTap: onDelete,
            variant: AppButtonVariant.ghost,
            width: 30,
            height: 30,
            horizontalPadding: 0,
          ),
        ],
      ),
    );
  }
}
