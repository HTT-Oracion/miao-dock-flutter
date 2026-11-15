import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import 'app_input.dart';
import 'buttons.dart';

/// 数据源面板的「链接导入」卡片外壳。
///
/// 漫画源与音乐源**共用同一实现**：卡片底、边框圆角、图标、标题行、说明、
/// 输入行与按钮的字号/高度/内距全部由本组件决定，调用方只传文案与回调。
/// 这样两页的按钮字号、描述字号不会各自漂移。
class SourceLinkImportCard extends StatelessWidget {
  const SourceLinkImportCard({
    super.key,
    required this.controller,
    required this.busy,
    required this.mobile,
    required this.onImport,
    required this.title,
    required this.trailingLabel,
    required this.description,
    required this.hint,
    required this.actionLabel,
    required this.actionLabelBusy,
    this.errorText,
    this.footer,
  });

  final TextEditingController controller;
  final bool busy;
  final bool mobile;
  final VoidCallback onImport;

  final String title;
  final String trailingLabel;
  final String description;
  final String hint;
  final String actionLabel;
  final String actionLabelBusy;

  /// 卡片底部附加区（漫画/音乐各自的「源仓库列表」）。
  final Widget? footer;

  /// 输入框错误提示（null = 无错误）。
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final buttonLabel = busy ? actionLabelBusy : actionLabel;
    return Container(
      padding: EdgeInsets.all(mobile ? 12 : 14),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.link, size: 15, color: palette.acc),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.ink),
              ),
              const Spacer(),
              if (trailingLabel.isNotEmpty)
                Text(
                  trailingLabel,
                  style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(fontSize: AppFont.px10_5, height: 1.6, color: palette.mut),
            ),
          ],
          const SizedBox(height: 9),
          if (mobile) ...[
            AppInput(
              controller: controller,
              hint: hint,
              onSubmitted: (_) => onImport(),
              height: 44,
              prefixIcon: LucideIcons.link2,
              errorText: errorText,
            ),
            const SizedBox(height: 8),
            AppButton(
              label: buttonLabel,
              icon: LucideIcons.download,
              onTap: busy ? null : onImport,
              variant: AppButtonVariant.primary,
              loading: busy,
              width: double.infinity,
              height: 44,
              fontSize: AppFont.px12,
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: AppInput(
                    controller: controller,
                    hint: hint,
                    onSubmitted: (_) => onImport(),
                    height: 36,
                    prefixIcon: LucideIcons.link2,
                    errorText: errorText,
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: buttonLabel,
                  icon: LucideIcons.download,
                  onTap: busy ? null : onImport,
                  variant: AppButtonVariant.primary,
                  loading: busy,
                  height: 36,
                  horizontalPadding: 12,
                  fontSize: AppFont.px11,
                ),
              ],
            ),
          if (footer != null) ...[const SizedBox(height: 12), footer!],
        ],
      ),
    );
  }
}
