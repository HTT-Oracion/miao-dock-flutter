import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_input.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../controller/drop_controller.dart';

/// 投放页**移动端**表单（对齐移动端设计稿的投放屏）。
///
/// 规格（逐项取自设计稿）：
/// - 页面内距 12；**无外层卡片**（设计稿是裸表单）；
/// - 选图区：虚线 1.5 描边 / 圆角 12 / 内距 14×16 / 图标 22 / 标题 12(600) /
///   规格 9(mut) / 两个按钮**整行铺满** 34 高、间距 10；
/// - 字段标签 10.5(600)、必填红星；名称输入 48 高；
/// - 提交/清空：34 高 / 横排 / 间距 8。
class DropMobileBody extends StatelessWidget {
  const DropMobileBody({
    super.key,
    required this.state,
    required this.onPickImages,
    required this.onPickFolder,
    required this.onNameChanged,
    required this.onClear,
    required this.onSubmit,
  });

  final DropState state;
  final VoidCallback onPickImages;
  final VoidCallback onPickFolder;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onClear;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PickerZone(onPickImages: onPickImages, onPickFolder: onPickFolder),
          const SizedBox(height: 12),
          _FieldLabel(text: l10n.dropComicName, required: true),
          const SizedBox(height: 6),
          _NameInput(value: state.name, onChanged: onNameChanged),
          if (state.files.isNotEmpty) ...[
            const SizedBox(height: 12),
            _FieldLabel(
              text: '${l10n.dropPendingList} ${state.files.length}',
              suffix: state.batchCount > 1 ? l10n.dropBatchSummary(state.batchCount) : null,
            ),
            const SizedBox(height: 6),
            _FileList(state: state),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              AppButton(
                label: state.files.isEmpty ? l10n.dropSubmit : '${l10n.dropSubmit} ${state.files.length}',
                onTap: onSubmit,
                clickable: onSubmit != null,
                variant: AppButtonVariant.primary,
                height: 34,
                horizontalPadding: 18,
                fontSize: AppFont.px12,
              ),
              const SizedBox(width: 8),
              AppButton(
                label: l10n.dropClear,
                onTap: state.files.isEmpty ? null : onClear,
                clickable: state.files.isNotEmpty,
                variant: AppButtonVariant.ghost,
                height: 34,
                horizontalPadding: 18,
                fontSize: AppFont.px12,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 选图区（移动端）：虚线框 + 图标 + 标题 + 规格 + 两个**整行铺满**的按钮。
///
/// 文案按移动端场景优化：手机没有拖拽，「拖入图片」是无效提示，改成
/// 「选择图片」类的动作描述（ARB：`dropPickHintMobile` / `dropSpecMobile`）。
class _PickerZone extends StatelessWidget {
  const _PickerZone({required this.onPickImages, required this.onPickFolder});

  final VoidCallback onPickImages;
  final VoidCallback onPickFolder;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.upload, size: 24, color: palette.acc.withValues(alpha: 0.85)),
          const SizedBox(height: 8),
          Text(
            l10n.dropPickHintMobile,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w600, color: palette.ink),
          ),
          const SizedBox(height: 5),
          Text(
            l10n.dropSpecMobile,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppFont.px9, height: 1.5, color: palette.mut),
          ),
          const SizedBox(height: 14),
          // 两个按钮**同一行**、等宽平分（设计稿口径）。
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: l10n.dropPickImages,
                  onTap: onPickImages,
                  variant: AppButtonVariant.secondary,
                  height: 34,
                  fontSize: AppFont.px12,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: l10n.dropPickFolder,
                  onTap: onPickFolder,
                  variant: AppButtonVariant.secondary,
                  height: 34,
                  fontSize: AppFont.px12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `.field label`：10.5/600，必填项带红 `*`。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, this.required = false, this.suffix});

  final String text;
  final bool required;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(fontSize: AppFont.px10_5, fontWeight: FontWeight.w600, color: palette.ink),
        ),
        if (required)
          Text(
            ' *',
            style: TextStyle(fontSize: AppFont.px10_5, color: palette.bad),
          ),
        if (suffix != null)
          Text(
            suffix!,
            style: TextStyle(fontSize: AppFont.px10, color: palette.acc),
          ),
      ],
    );
  }
}

/// 名称输入（移动端 48 高）。
class _NameInput extends StatefulWidget {
  const _NameInput({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_NameInput> createState() => _NameInputState();
}

class _NameInputState extends State<_NameInput> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppInput(
      controller: _c,
      hint: AppLocalizations.of(context).dropComicNamePlaceholder,
      height: 48,
      fontSize: AppFont.px14,
      onChanged: widget.onChanged,
    );
  }
}

/// 待投放清单（移动端最大 150 高，每行 26）。
class _FileList extends StatelessWidget {
  const _FileList({required this.state});

  final DropState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            for (var i = 0; i < state.files.length; i++)
              SizedBox(
                height: 26,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          state.files[i].split(RegExp(r'[/\\]')).last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppFont.px10, color: palette.ink2),
                        ),
                      ),
                      Text(
                        l10n.dropBatchLabel(state.batchOf(i)),
                        style: TextStyle(fontSize: AppFont.px8_5, color: palette.mut),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
