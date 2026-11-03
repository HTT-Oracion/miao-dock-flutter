import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_input.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../controller/drop_controller.dart';

/// 投放页**移动端**表单。
///
/// 与桌面分开维护（D-138）：移动端没有拖拽（无 HTML5 drag），整页纵向单栏、
/// 密度更紧凑（拖拽区图标 26 / 标题 12 / 按钮 34）。壳（`drop_screen.dart`）
/// 只负责取图 / 提交，两端共用。
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
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.panel,
              border: Border.all(color: palette.line),
              borderRadius: BorderRadius.circular(8),
            ),
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
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        label: state.files.isEmpty ? l10n.dropSubmit : '${l10n.dropSubmit} ${state.files.length}',
                        onTap: onSubmit,
                        clickable: onSubmit != null,
                        variant: AppButtonVariant.primary,
                        height: 32,
                        horizontalPadding: 18,
                        fontSize: AppFont.px12,
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        label: l10n.dropClear,
                        onTap: state.files.isEmpty ? null : onClear,
                        clickable: state.files.isNotEmpty,
                        variant: AppButtonVariant.ghost,
                        border: true,
                        height: 32,
                        horizontalPadding: 18,
                        fontSize: AppFont.px12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 选图区（移动端形态）：**不是拖拽区**，只是两个纵向铺满的按钮 + 规格说明。
///
/// 移动端没有 HTML5 拖拽，画一个「拖入图片」的虚线框只会误导用户，
/// 所以这里只保留图标、规格与两个动作。
class _PickerZone extends StatelessWidget {
  const _PickerZone({required this.onPickImages, required this.onPickFolder});

  final VoidCallback onPickImages;
  final VoidCallback onPickFolder;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.upload, size: 26, color: palette.acc.withValues(alpha: 0.85)),
          const SizedBox(height: 6),
          Text(
            l10n.dropDropHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w600, color: palette.ink),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.dropSpec,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
          ),
          const SizedBox(height: 10),
          _GhostButton(label: l10n.dropPickImages, onPressed: onPickImages),
          const SizedBox(height: 10),
          _GhostButton(label: l10n.dropPickFolder, onPressed: onPickFolder),
        ],
      ),
    );
  }
}

/// 投放页次级按钮（移动端：34 高 / 12 号 / 铺满整行便于点按）。
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onTap: onPressed,
      variant: AppButtonVariant.ghost,
      border: true,
      width: double.infinity,
      height: 34,
      horizontalPadding: 14,
      fontSize: AppFont.px12,
    );
  }
}

/// `.field label`：10.5/600（与队列、漫画库的标签同级别），必填项带红 `*`。
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

/// 名称输入（移动端 48 高、点按舒适）。
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

/// 待投放清单（移动端最大 150 高）。
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
