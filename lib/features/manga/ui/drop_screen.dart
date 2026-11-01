import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/toast.dart';
import '../controller/drop_controller.dart';
import '../controller/queue_controller.dart';

/// 投放屏 —— 按 `ver1.0` 的 `.drop-wrap` 一比一重画（D-069）。
///
/// 结构（640px 单栏、间距 16、顶部留 30）：
/// ```
/// 拖拽区（150 高，虚线感边框）
/// 漫画名 *（38 高输入框）
/// 说明文字（9px）
/// 待投放 N 张 + 清单（每行 26 高，右侧「第 N 批」标签）
/// 落盘路径预览 + 说明
/// 提交 / 清空
/// ```
///
/// 设计稿里 `frow` **没有删除按钮**，所以这里也不画——删单张请用「清空」。
/// 引擎未启动的横幅按用户要求**不再显示**（引导页承担该职责）。
class DropScreen extends ConsumerStatefulWidget {
  const DropScreen({super.key});

  @override
  ConsumerState<DropScreen> createState() => _DropScreenState();
}

class _DropScreenState extends ConsumerState<DropScreen> {
  bool _over = false;

  Future<void> _pickImages() async {
    final files = await openFiles();
    if (files.isEmpty) return;
    ref.read(dropController.notifier).addFiles(files.map((f) => f.path));
  }

  Future<void> _pickFolder() async {
    final dirPath = await getDirectoryPath();
    if (dirPath == null) return;
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;
    // 只收图片：混进 .txt / .DS_Store 会让服务端按批校验时整批失败。
    const exts = {'.png', '.jpg', '.jpeg', '.webp'};
    final files =
        dir
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where((p) => exts.any((e) => p.toLowerCase().endsWith(e)))
            .toList()
          ..sort();
    if (files.isNotEmpty) ref.read(dropController.notifier).addFiles(files);
  }

  Future<void> _submit() async {
    final state = ref.read(dropController);
    if (state.name.isEmpty || state.files.isEmpty) return;
    try {
      final result = await ref.read(queueProvider.notifier).submit(comicName: state.name, imagePaths: state.files);
      ref.read(dropController.notifier).clear();
      if (!mounted) return;
      showAppToast(
        context,
        AppLocalizations.of(context).dropSubmittedToast(result.submitted, result.position),
        tone: ToastTone.good,
      );
      context.go('/manga/queue');
    } catch (e) {
      // 提交失败必须给反馈：以前是静默抛异常，用户完全不知道发生了什么。
      if (!mounted) return;
      showAppToast(context, '${AppLocalizations.of(context).dropSubmitFailed}：$e', tone: ToastTone.bad);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(dropController);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.only(top: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DropZone(
                  over: _over,
                  onPickImages: _pickImages,
                  onPickFolder: _pickFolder,
                  onDragEnter: () => setState(() => _over = true),
                  onDragExit: () => setState(() => _over = false),
                  onDrop: (paths) {
                    setState(() => _over = false);
                    ref.read(dropController.notifier).addFiles(paths);
                  },
                ),

                const SizedBox(height: 16),
                _FieldLabel(text: l10n.dropComicName, required_: true),
                const SizedBox(height: 6),
                _NameInput(value: state.name, onChanged: (v) => ref.read(dropController.notifier).setName(v)),
                const SizedBox(height: 6),
                Text(l10n.dropComicNameHint, style: TextStyle(fontSize: 9, height: 1.6, color: palette.mut)),

                if (state.files.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _FieldLabel(
                    text: '${l10n.dropPendingList} ${state.files.length}',
                    suffix: state.batchCount > 1 ? l10n.dropBatchSummary(state.batchCount) : null,
                  ),
                  const SizedBox(height: 6),
                  _FileList(state: state),
                  const SizedBox(height: 16),
                  _FieldLabel(text: l10n.dropLandingPreview),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                    decoration: BoxDecoration(
                      color: palette.card,
                      border: Border.all(color: palette.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(l10n.dropLandingPreviewUnknown, style: TextStyle(fontSize: 10, color: palette.ink2)),
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.dropLandingPreviewHint, style: TextStyle(fontSize: 9, height: 1.6, color: palette.mut)),
                ],

                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton(
                      onPressed: (state.name.isNotEmpty && state.files.isNotEmpty) ? _submit : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.acc,
                        foregroundColor: palette.onAcc,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppMetrics.radiusButton)),
                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      child: Text(state.files.isEmpty ? l10n.dropSubmit : '${l10n.dropSubmit} ${state.files.length}'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: state.files.isEmpty ? null : () => ref.read(dropController.notifier).clear(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.ink2,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        side: BorderSide(color: palette.line2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppMetrics.radiusButton)),
                        textStyle: const TextStyle(fontSize: 9.5),
                      ),
                      child: Text(l10n.dropClear),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 拖拽区（`.dropzone`：150 高 / 圆角 12 / 1.5px 描边；hover 与拖入都是主色）。
class _DropZone extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final active = over;

    return DropTarget(
      onDragEntered: (_) => onDragEnter(),
      onDragExited: (_) => onDragExit(),
      onDragDone: (details) => onDrop(details.files.map((f) => f.path).toList()),
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: active ? palette.accSoft : palette.panel,
          border: Border.all(color: active ? palette.acc : palette.line2, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.upload, size: 20, color: active ? palette.acc : palette.mut),
            const SizedBox(height: 7),
            Text(
              active ? l10n.dropDropHintActive : l10n.dropDropHint,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? palette.acc : palette.ink),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                l10n.dropSpec,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9.5, color: palette.mut),
              ),
            ),
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GhostButton(label: l10n.dropPickImages, onPressed: onPickImages),
                  const SizedBox(width: 8),
                  _GhostButton(label: l10n.dropPickFolder, onPressed: onPickFolder),
                ],
              ),
            ),
          ],
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
      height: 26,
      horizontalPadding: 10,
      fontSize: 9.5,
    );
  }
}

/// `.field label`：11/600，必填项带红 `*`。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, this.required_ = false, this.suffix});

  final String text;
  final bool required_;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.ink),
        ),
        if (required_) Text(' *', style: TextStyle(fontSize: 11, color: palette.bad)),
        if (suffix != null) Text(suffix!, style: TextStyle(fontSize: 10, color: palette.acc)),
      ],
    );
  }
}

/// `.finput`：38 高 / 圆角 8 / `--card` 底 / 聚焦换主色。
class _NameInput extends StatefulWidget {
  const _NameInput({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_NameInput> createState() => _NameInputState();
}

class _NameInputState extends State<_NameInput> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppInput(
      controller: _c,
      hint: l10n.dropComicNamePlaceholder,
      height: 38,
      fontSize: 10.5,
      onChanged: widget.onChanged,
    );
  }
}

/// `.flist`：描边容器 + 每行 26 高 + 右侧批次标签。
class _FileList extends StatelessWidget {
  const _FileList({required this.state});

  final DropState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 210),
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
                          style: TextStyle(fontSize: 10, color: palette.ink2),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(5)),
                        child: Text(
                          l10n.dropBatchLabel(state.batchOf(i)),
                          style: TextStyle(fontSize: 8.5, color: palette.mut),
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
