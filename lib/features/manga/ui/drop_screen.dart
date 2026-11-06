import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/responsive.dart';
import '../../../shared/widgets/toast.dart';
import '../controller/drop_controller.dart';
import '../controller/queue_controller.dart';
import 'drop/drop_desktop.dart';
import 'drop/drop_mobile.dart';

/// 投放屏 —— **壳**：取图 / 提交两类逻辑与断点分流。
///
/// 表单本身按平台分成两份独立实现（D-138）：
/// - [DropDesktopBody]：拖拽区 + 并排按钮 + 720 卡片（桌面专属布局）；
/// - [DropMobileBody]：无拖拽、纵向单栏、密度紧凑（`移动端设计稿`）。
///
/// 分开的理由：这不是「间距差几 px」，而是**结构不同**——移动端没有 HTML5 拖拽，
/// 画一个「拖入图片」的虚线框只会误导。此前 26 处 `isMobile ?` 三元混在一个
/// build 里，改任何一端都要读完整段。
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

  bool _submitting = false;

  Future<void> _submit() async {
    final state = ref.read(dropController);
    if (state.name.isEmpty || state.files.isEmpty || _submitting) return;
    final l10n = AppLocalizations.of(context);
    try {
      setState(() => _submitting = true);
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
      // 回执卡留在投放页（重设计稿）：提交结果可视 + 双出口，不再直接跳走。
      ref.read(dropController.notifier).setReceipt(count: result.submitted, position: result.position);
    } catch (e) {
      // 提交失败必须给反馈：以前是静默抛异常，用户完全不知道发生了什么。
      if (!mounted) return;
      showAppToast(context, '${AppLocalizations.of(context).dropSubmitFailed}：$e', tone: ToastTone.bad);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dropController);
    final canSubmit = state.name.isNotEmpty && state.files.isNotEmpty;

    if (context.isMobile) {
      return DropMobileBody(
        state: state,
        onPickImages: _pickImages,
        onPickFolder: _pickFolder,
        onNameChanged: (v) => ref.read(dropController.notifier).setName(v),
        onClear: () => ref.read(dropController.notifier).clear(),
        onSubmit: canSubmit && !_submitting ? _submit : null,
      );
    }

    return DropDesktopBody(
      state: state,
      over: _over,
      submitting: _submitting,
      onPickImages: _pickImages,
      onPickFolder: _pickFolder,
      onDragEnter: () => setState(() => _over = true),
      onDragExit: () => setState(() => _over = false),
      onRemoveFile: (i) => ref.read(dropController.notifier).removeAt(i),
      onDrop: (paths) {
        setState(() => _over = false);
        ref.read(dropController.notifier).addFiles(paths);
      },
      onNameChanged: (v) => ref.read(dropController.notifier).setName(v),
      onClear: () => ref.read(dropController.notifier).clear(),
      onSubmit: canSubmit ? _submit : null,
    );
  }
}
