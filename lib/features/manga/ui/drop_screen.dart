import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/toast.dart';
import '../controller/drop_controller.dart';
import '../controller/queue_controller.dart';

/// 投放屏（设计稿 H 投放页，Note 05/06）：640px 单栏竖向流——
/// 热区 → 漫画名（必填）→ 待投放清单（逐行标注第 N 批）→ 提交 / 清空。
class DropScreen extends ConsumerStatefulWidget {
  const DropScreen({super.key});

  @override
  ConsumerState<DropScreen> createState() => _DropScreenState();
}

class _DropScreenState extends ConsumerState<DropScreen> {
  bool _hovering = false;

  Future<void> _pickImages() async {
    final files = await openFiles(
      acceptedTypeGroups: [
        const XTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp']),
      ],
    );
    ref.read(dropController.notifier).addFiles(files.map((f) => f.path));
  }

  Future<void> _pickFolder() async {
    if (kIsWeb) return;
    final dirPath = await getDirectoryPath();
    if (dirPath == null) return;
    final files = <String>[];
    await for (final entity in Directory(dirPath).list(recursive: true, followLinks: false)) {
      if (entity is File && isAllowedImage(entity.path)) files.add(entity.path);
    }
    ref.read(dropController.notifier).addFiles(files);
  }

  Future<void> _submit() async {
    final state = ref.read(dropController);
    if (state.name.isEmpty || state.files.isEmpty) return;
    final result = await ref.read(queueProvider.notifier).submit(comicName: state.name, imagePaths: state.files);
    ref.read(dropController.notifier).clear();
    if (mounted) {
      showAppToast(context, '已提交 ${result.submitted} 张，队内第 ${result.position} 位');
      context.go('/manga/queue');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dropController);
    final ready = state.name.isNotEmpty && state.files.isNotEmpty;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 30),
          children: [
            _Dropzone(
              hovering: _hovering,
              onHover: (v) => setState(() => _hovering = v),
              onDrop: (files) => ref.read(dropController.notifier).addFiles(files),
              onPickImages: _pickImages,
              onPickFolder: _pickFolder,
            ),
            const _FieldLabel('漫画名', required: true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: TextField(
                onChanged: ref.read(dropController.notifier).setName,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '同一名字会归入同一部漫画',
                  hintStyle: const TextStyle(fontSize: 12.5, color: AppTokens.textSecondary),
                  filled: true,
                  fillColor: AppTokens.card,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
            ),
            if (state.files.isNotEmpty) ...[const _FieldLabel('待投放清单'), _PendingList(files: state.files)],
            const SizedBox(height: 18),
            Row(
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.accent,
                    foregroundColor: AppTokens.pageBg,
                    disabledBackgroundColor: AppTokens.progressTrack,
                    disabledForegroundColor: AppTokens.textSecondary,
                  ),
                  onPressed: ready ? _submit : null,
                  child: const Text('提交'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTokens.textSecondary,
                    side: const BorderSide(color: AppTokens.progressTrack),
                  ),
                  onPressed: state.files.isEmpty ? null : () => ref.read(dropController.notifier).clear(),
                  child: const Text('清空'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Dropzone extends StatelessWidget {
  const _Dropzone({
    required this.hovering,
    required this.onHover,
    required this.onDrop,
    required this.onPickImages,
    required this.onPickFolder,
  });

  final bool hovering;
  final ValueChanged<bool> onHover;
  final ValueChanged<List<String>> onDrop;
  final VoidCallback onPickImages;
  final VoidCallback onPickFolder;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => onHover(true),
      onDragExited: (_) => onHover(false),
      onDragDone: (details) {
        onHover(false);
        onDrop(details.files.map((f) => f.path).toList());
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 150,
        decoration: BoxDecoration(
          color: hovering ? AppTokens.navActive : AppTokens.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hovering ? AppTokens.accent : AppTokens.progressTrack, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.fileUp, size: 22, color: hovering ? AppTokens.accent : AppTokens.textSecondary),
            const SizedBox(height: 8),
            const Text(
              '把图片或文件夹拖进这里',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              '支持 png / jpg / jpeg / webp；服务端每批 20 张，超出的部分会自动排队（序号连续，不需要你分批）',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppTokens.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ZoneButton(label: '选择图片', onTap: onPickImages),
                const SizedBox(width: 8),
                _ZoneButton(label: '选择文件夹', onTap: onPickFolder),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoneButton extends StatelessWidget {
  const _ZoneButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTokens.divider,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text(label, style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary)),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(1, 18, 0, 8),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
          ),
          if (required) const Text(' *', style: TextStyle(fontSize: 12.5, color: AppTokens.accent)),
        ],
      ),
    );
  }
}

class _PendingList extends StatelessWidget {
  const _PendingList({required this.files});

  final List<String> files;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(8)),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: files.length,
        itemExtent: 34,
        itemBuilder: (context, i) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTokens.divider)),
            ),
            child: Row(
              children: [
                Text('第 ${i ~/ 20 + 1} 批', style: const TextStyle(fontSize: 11, color: AppTokens.accent)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    dropDisplayName(files[i]),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
