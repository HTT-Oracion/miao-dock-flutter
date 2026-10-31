import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/toast.dart';
import '../controller/drop_controller.dart';
import '../controller/engine_controller.dart';
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
        XTypeGroup(label: AppLocalizations.of(context).imageFilter, extensions: const ['png', 'jpg', 'jpeg', 'webp']),
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
      showAppToast(context, AppLocalizations.of(context).dropSubmittedToast(result.submitted, result.position));
      context.go('/manga/queue');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dropController);
    final ready = state.name.isNotEmpty && state.files.isNotEmpty;
    final view = ref.watch(notReadyViewProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 30),
          children: [
            // D-012：引擎未就绪不再整屏拦截 —— 投放、看库、补页都可正常用，
            // 只在实际要翻译时提示。这条横幅可点击直达启动。
            if (!view.canTranslate && view.needsLocalEngine) ...[
              _EngineOffBanner(onStart: () => ref.read(engineStateProvider.notifier).start()),
              const SizedBox(height: 12),
            ],
            _Dropzone(
              hovering: _hovering,
              onHover: (v) => setState(() => _hovering = v),
              onDrop: (files) => ref.read(dropController.notifier).addFiles(files),
              onPickImages: _pickImages,
              onPickFolder: _pickFolder,
            ),
            _FieldLabel(AppLocalizations.of(context).dropComicName, required: true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: TextField(
                onChanged: ref.read(dropController.notifier).setName,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).dropComicNameHint,
                  hintStyle: const TextStyle(fontSize: 12.5, color: AppTokens.textSecondary),
                  filled: true,
                  fillColor: AppTokens.card,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
            ),
            if (state.files.isNotEmpty) ...[
              _FieldLabel(AppLocalizations.of(context).dropPendingList),
              _PendingList(files: state.files),
            ],
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
                  child: Text(AppLocalizations.of(context).dropSubmit),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTokens.textSecondary,
                    side: const BorderSide(color: AppTokens.progressTrack),
                  ),
                  onPressed: state.files.isEmpty ? null : () => ref.read(dropController.notifier).clear(),
                  child: Text(AppLocalizations.of(context).dropClear),
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
            Text(
              AppLocalizations.of(context).dropDropHint,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context).dropSpec,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ZoneButton(label: AppLocalizations.of(context).dropPickImages, onTap: onPickImages),
                const SizedBox(width: 8),
                _ZoneButton(label: AppLocalizations.of(context).dropPickFolder, onTap: onPickFolder),
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
                Text(
                  AppLocalizations.of(context).dropBatchLabel(i ~/ 20 + 1),
                  style: const TextStyle(fontSize: 11, color: AppTokens.accent),
                ),
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

/// 引擎未启动提示条（D-012）—— 不挡内容，只提示「现在翻译不了」。
class _EngineOffBanner extends StatelessWidget {
  const _EngineOffBanner({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    // 引擎未启动横幅**固定不显示**：这件事已由引导页承担（用户要求）。
    // 保留组件本身是为了不牵动调用方布局；直接渲染空盒子。
    return const SizedBox.shrink();
  }
}
