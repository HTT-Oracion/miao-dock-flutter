import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_input.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../controller/drop_controller.dart';

/// 投放页**桌面**表单。
///
/// 与移动端分开维护（D-138）：拖拽区、并排按钮、更大的卡片内距都是桌面专属。
/// 壳（`drop_screen.dart`）只负责取图 / 提交，两端共用。
class DropDesktopBody extends StatelessWidget {
  const DropDesktopBody({
    super.key,
    required this.state,
    required this.over,
    required this.onPickImages,
    required this.onPickFolder,
    required this.onDragEnter,
    required this.onDragExit,
    required this.onDrop,
    required this.onNameChanged,
    required this.onClear,
    required this.onSubmit,
  });

  final DropState state;
  final bool over;
  final VoidCallback onPickImages;
  final VoidCallback onPickFolder;
  final VoidCallback onDragEnter;
  final VoidCallback onDragExit;
  final ValueChanged<List<String>> onDrop;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onClear;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: palette.panel,
              border: Border.all(color: palette.line),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DropZone(
                  over: over,
                  onPickImages: onPickImages,
                  onPickFolder: onPickFolder,
                  onDragEnter: onDragEnter,
                  onDragExit: onDragExit,
                  onDrop: onDrop,
                ),
                const SizedBox(height: 16),
                _FieldLabel(text: l10n.dropComicName, required: true),
                const SizedBox(height: 6),
                _NameInput(value: state.name, onChanged: onNameChanged),
                const SizedBox(height: 6),
                Text(
                  l10n.dropComicNameHint,
                  style: TextStyle(fontSize: AppFont.px12, height: 1.5, color: palette.mut),
                ),
                if (state.files.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _FieldLabel(
                    text: '${l10n.dropPendingList} ${state.files.length}',
                    suffix: state.batchCount > 1 ? l10n.dropBatchSummary(state.batchCount) : null,
                  ),
                  const SizedBox(height: 6),
                  _FileList(state: state, maxHeight: 210),
                  const SizedBox(height: 16),
                  _FieldLabel(text: l10n.dropLandingPreview),
                  const SizedBox(height: 6),
                  _LandingPreview(),
                  const SizedBox(height: 4),
                  Text(
                    l10n.dropLandingPreviewHint,
                    style: TextStyle(fontSize: AppFont.px9, height: 1.6, color: palette.mut),
                  ),
                ],
                const SizedBox(height: 16),
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
                        height: 36,
                        horizontalPadding: 24,
                        fontSize: AppFont.px12_5,
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        label: l10n.dropClear,
                        onTap: state.files.isEmpty ? null : onClear,
                        clickable: state.files.isNotEmpty,
                        variant: AppButtonVariant.ghost,
                        border: true,
                        height: 36,
                        horizontalPadding: 24,
                        fontSize: AppFont.px12_5,
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

/// 拖拽区（`.dropzone`：圆角 6 / 1px 描边；hover 与拖入都是主色）。
///
/// **桌面专属**：移动端没有 HTML5 拖拽，用点击选图代替。
class _DropZone extends StatefulWidget {
  const _DropZone({
    required this.over,
    required this.onPickImages,
    required this.onPickFolder,
    required this.onDragEnter,
    required this.onDragExit,
    required this.onDrop,
  });

  final bool over;
  final VoidCallback onPickImages;
  final VoidCallback onPickFolder;
  final VoidCallback onDragEnter;
  final VoidCallback onDragExit;
  final ValueChanged<List<String>> onDrop;

  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final active = widget.over || _hover;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: DropTarget(
        onDragEntered: (_) => widget.onDragEnter(),
        onDragExited: (_) => widget.onDragExit(),
        onDragDone: (details) => widget.onDrop(details.files.map((f) => f.path).toList()),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          decoration: BoxDecoration(
            color: active ? palette.accSoft : palette.card,
            border: Border.all(color: active ? palette.acc : palette.line2, width: 1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.upload, size: 40, color: active ? palette.acc : palette.acc.withValues(alpha: 0.8)),
              const SizedBox(height: 12),
              Text(
                active ? l10n.dropDropHintActive : l10n.dropDropHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppFont.px15,
                  fontWeight: FontWeight.w600,
                  color: active ? palette.acc : palette.ink,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  l10n.dropSpec,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GhostButton(label: l10n.dropPickImages, onPressed: widget.onPickImages),
                  const SizedBox(width: 12),
                  _GhostButton(label: l10n.dropPickFolder, onPressed: widget.onPickFolder),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 投放页次级按钮：统一走 [AppButton]。
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
      height: 34,
      horizontalPadding: 20,
      fontSize: AppFont.px14,
    );
  }
}

/// `.field label`：14/500，必填项带红 `*`。
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
          style: TextStyle(fontSize: AppFont.px14, fontWeight: FontWeight.w500, color: palette.ink),
        ),
        if (required)
          Text(
            ' *',
            style: TextStyle(fontSize: AppFont.px14, color: palette.bad),
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

/// `.finput`：44 高 / 圆角 6 / 聚焦换主色。
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
      height: 44,
      fontSize: AppFont.px14,
      onChanged: widget.onChanged,
    );
  }
}

/// `.flist`：描边容器 + 每行 26 高 + 右侧批次标签。
class _FileList extends StatelessWidget {
  const _FileList({required this.state, required this.maxHeight});

  final DropState state;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(5)),
                        child: Text(
                          l10n.dropBatchLabel(state.batchOf(i)),
                          style: TextStyle(fontSize: AppFont.px8_5, color: palette.mut),
                        ),
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

/// 落盘路径预览（服务端才做名称规范化，这里不猜具体路径）。
class _LandingPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        AppLocalizations.of(context).dropLandingPreviewUnknown,
        style: TextStyle(fontSize: AppFont.px10, color: palette.ink2),
      ),
    );
  }
}
