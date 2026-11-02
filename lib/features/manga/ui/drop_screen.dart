import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/responsive.dart';
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
  static const _folderChannel = MethodChannel('miao_dock/folder_picker');
  bool _over = false;

  Future<void> _pickImages() async {
    final files = await openFiles();
    if (files.isEmpty) return;
    // 🔴 移动端（Android/iOS）返回的是 content:// URI，**没有扩展名也没有真实路径**：
    // `addFiles` 按扩展名过滤会全部丢掉 —— 表现成「选了图片但列表没反应」（实测）。
    // 这里把字节落进缓存目录换成真实路径；桌面端 path 本来就是真路径，直接放行。
    final paths = <String>[];
    for (final f in files) {
      if (f.path.startsWith('content://') || !File(f.path).existsSync()) {
        final saved = await _materialize(f);
        if (saved != null) paths.add(saved);
      } else {
        paths.add(f.path);
      }
    }
    if (paths.isEmpty) return;
    ref.read(dropController.notifier).addFiles(paths);
  }

  /// 把「非真实路径」的选择结果落盘到缓存目录，返回可读的真实路径。
  ///
  /// 文件名取原名的扩展名（`XFile.name` 带扩展名），保不住就按 png 处理 ——
  /// 下游按扩展名判图片类型，没有扩展名会被当成非法文件。
  Future<String?> _materialize(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final base = file.name.isNotEmpty ? file.name : 'image.png';
      final ext = base.contains('.') ? base.split('.').last.toLowerCase() : 'png';
      final dir = Directory('${Directory.systemTemp.path}/miao-drop');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final target = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$base');
      await target.writeAsBytes(bytes);
      // 扩展名不在白名单时补一个，避免被 addFiles 过滤掉。
      return target.path.endsWith('.$ext') ? target.path : '${target.path}.$ext';
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickFolder() async {
    if (Platform.isAndroid) {
      try {
        final paths = await _folderChannel.invokeListMethod<String>('pickImageFolder') ?? const [];
        if (paths.isNotEmpty) ref.read(dropController.notifier).addFiles(paths);
      } on PlatformException {
        if (mounted) showAppToast(context, AppLocalizations.of(context).dropFolderPickFailed, tone: ToastTone.bad);
      }
      return;
    }
    // iOS 的系统目录授权能力与 Android SAF 不同，暂时保留多选图片回退。
    if (Platform.isIOS) {
      await _pickImages();
      return;
    }
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
    final l10n = AppLocalizations.of(context);
    try {
      final result = await ref
          .read(queueProvider.notifier)
          .submit(
            comicName: state.name,
            imagePaths: state.files,
            // 远程配置无效时把文案交给任务失败原因（controller 不碰 ARB）。
            blockedReason: l10n.remoteConfigInvalid,
          );
      ref.read(dropController.notifier).clear();
      if (!mounted) return;
      if (result.blocked) {
        // 配置问题 ⇒ 任务已建成 failed，不进流水线：直接弹提示并跳到队列让用户看到那条任务。
        showAppToast(context, result.blockedReason!, tone: ToastTone.bad);
        context.go('/manga/queue');
        return;
      }
      showAppToast(context, l10n.dropSubmittedToast(result.submitted, result.position), tone: ToastTone.good);
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

    // 原型 `.upload-panel`：白色卡片（max 720 / 内距 32 / 圆角 6）+ 四周留白。
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        context.isMobile ? 12 : 20,
        context.isMobile ? 12 : 40,
        context.isMobile ? 12 : 20,
        40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            padding: EdgeInsets.all(context.isMobile ? 16 : 32),
            decoration: BoxDecoration(
              color: palette.panel,
              border: Border.all(color: palette.line),
              borderRadius: BorderRadius.circular(context.isMobile ? 8 : 6),
            ),
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
                    child: Text(
                      l10n.dropLandingPreviewUnknown,
                      style: TextStyle(fontSize: AppFont.px10, color: palette.ink2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.dropLandingPreviewHint,
                    style: TextStyle(fontSize: AppFont.px9, height: 1.6, color: palette.mut),
                  ),
                ],

                const SizedBox(height: 16),
                // 提交与清空固定一行；Align 隔离外层 stretch，Row 用最小宽度避免按钮拉伸。
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        label: state.files.isEmpty ? l10n.dropSubmit : '${l10n.dropSubmit} ${state.files.length}',
                        onTap: (state.name.isNotEmpty && state.files.isNotEmpty) ? _submit : null,
                        clickable: state.name.isNotEmpty && state.files.isNotEmpty,
                        variant: AppButtonVariant.primary,
                        height: 36,
                        horizontalPadding: 24,
                        fontSize: AppFont.px12_5,
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        label: l10n.dropClear,
                        onTap: state.files.isEmpty ? null : () => ref.read(dropController.notifier).clear(),
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

/// 拖拽区（`.dropzone`：150 高 / 圆角 12 / 1.5px 描边；hover 与拖入都是主色）。
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
    // 拖拽中或鼠标悬停都算 active（原型 `.drop-zone:hover` 变主色）。
    final active = widget.over || _hover;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: DropTarget(
        onDragEntered: (_) => widget.onDragEnter(),
        onDragExited: (_) => widget.onDragExit(),
        onDragDone: (details) => widget.onDrop(details.files.map((f) => f.path).toList()),
        child: Container(
          // 原型 `.drop-zone`：**虚线**边框 + 内距撑开（不再固定高度，
          // 固定高度在窄屏会把文案和按钮挤在一起）。
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: context.isMobile ? 24 : 32),
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
              // 原型：桌面并排居中；窄屏**纵向堆叠且占满整行**（手指好点）。
              if (context.isMobile)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GhostButton(label: l10n.dropPickImages, onPressed: widget.onPickImages, full: true),
                    const SizedBox(height: 10),
                    _GhostButton(label: l10n.dropPickFolder, onPressed: widget.onPickFolder, full: true),
                  ],
                )
              else
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
  const _GhostButton({required this.label, required this.onPressed, this.full = false});

  final String label;
  final VoidCallback onPressed;

  /// 是否占满整行（窄屏用）。
  final bool full;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onTap: onPressed,
      variant: AppButtonVariant.ghost,
      border: true,
      width: full ? double.infinity : null,
      // 原型 34 高、14 号字；窄屏拉到 40（触控区域）。
      height: context.isMobile ? 40 : 34,
      horizontalPadding: 20,
      fontSize: AppFont.px14,
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
          style: TextStyle(fontSize: AppFont.px14, fontWeight: FontWeight.w500, color: palette.ink),
        ),
        if (required_)
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
      // 原型 `.form-input` 写 38 偏小（实测反馈）；桌面 44 / 窄屏 48 更好点按。
      height: context.isMobile ? 48 : 44,
      fontSize: AppFont.px14,
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
