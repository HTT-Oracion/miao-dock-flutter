import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/storage/engine_inspect.dart';
import '../../../../core/storage/paths.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/log_box.dart';

/// 引擎目录选择 / 导入（D-027）。
///
/// ## 两个用途，一个对话框
/// - **下载**：选目录（默认 `mangaEngineDir()`，每次下载都问，不记忆上次）；
/// - **导入本地**：选已有目录 → 手动点「校验」→ 失败时下方出日志 →
///   引导「重新下载缺失部件」。重新下载同样先选目录，与直接下载一致。
///
/// ## 为什么校验是按钮而不是自动跑
/// 校验会**起一次子进程**（真的 `import torch`），冷盘或首次可能几秒。
/// 自动跑会让对话框一打开就卡住；手动触发也让用户知道「我在检查什么」。
class RuntimePickerDialog extends ConsumerStatefulWidget {
  const RuntimePickerDialog({super.key, required this.initialDir, this.importMode = false});

  /// 初始目录（默认 = `<数据根>/manga/engine`）。
  final String initialDir;

  /// true = 导入已有目录（显示「校验」）；false = 下载前选目录。
  final bool importMode;

  static Future<RuntimePickResult?> show(BuildContext context, {String? initialDir, bool importMode = false}) {
    return showAppDialog<RuntimePickResult>(
      context: context,
      builder: (_) => RuntimePickerDialog(initialDir: initialDir ?? mangaEngineDir(), importMode: importMode),
    );
  }

  @override
  ConsumerState<RuntimePickerDialog> createState() => _RuntimePickerDialogState();
}

/// 选择结果。
class RuntimePickResult {
  const RuntimePickResult({required this.dir, this.imported = false, this.inspection});

  final String dir;

  /// true = 导入本地（跳过下载）；false = 下载到这里。
  final bool imported;

  /// 导入模式下的校验结果。
  final EngineInspection? inspection;
}

class _RuntimePickerDialogState extends ConsumerState<RuntimePickerDialog> {
  late String _dir = widget.initialDir;
  EngineInspection? _inspection;
  bool _checking = false;
  String? _checkError;

  bool get _isImport => widget.importMode;

  Future<void> _pickDir() async {
    final picked = await getDirectoryPath(initialDirectory: _dir);
    if (picked == null || !mounted) return;
    setState(() {
      _dir = picked;
      // 换目录就作废上次校验 —— 留着会让用户以为新目录也验过了。
      _inspection = null;
      _checkError = null;
    });
  }

  Future<void> _runCheck() async {
    setState(() {
      _checking = true;
      _checkError = null;
    });
    try {
      final r = await inspectEngine(_dir);
      if (mounted) setState(() => _inspection = r);
    } catch (e) {
      if (mounted) setState(() => _checkError = '$e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return AppDialog(
      title: _isImport ? l10n.runtimeImportTitle : l10n.runtimePickTitle,
      icon: _isImport ? LucideIcons.folderInput : LucideIcons.hardDriveDownload,
      width: 640,
      onClose: () => Navigator.of(context).pop(),
      actions: [
        AppButton(label: l10n.actionCancel, onTap: () => Navigator.of(context).pop()),
        AppButton(
          label: _isImport ? l10n.runtimeImportOk : l10n.runtimePickConfirm,
          variant: AppButtonVariant.primary,
          // 导入必须校验过才允许：没验就导入，问题会推迟到翻译时才暴露。
          onTap: !_isImport || _inspection != null
              ? () =>
                    Navigator.of(context)
                        .pop(RuntimePickResult(dir: _dir, imported: _isImport, inspection: _inspection))
              : null,
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isImport ? l10n.runtimeImportDesc : l10n.runtimePickDesc,
              style: TextStyle(fontSize: AppFont.px11, height: 1.6, color: palette.ink2),
            ),
            const SizedBox(height: 14),
            _DirRow(dir: _dir, label: _isImport ? l10n.runtimeImportPick : l10n.runtimePickDefault, onChange: _pickDir),
            if (_isImport) ..._buildCheckSection(context, palette, l10n),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCheckSection(BuildContext context, AppPalette palette, AppLocalizations l10n) {
    return [
      const SizedBox(height: 12),
      Row(
        children: [
          AppButton(
            label: _checking ? l10n.engineChecking : l10n.engineCheck,
            icon: LucideIcons.shieldCheck,
            onTap: _checking ? null : _runCheck,
            clickable: !_checking,
            variant: AppButtonVariant.primary,
            height: 32,
            horizontalPadding: 14,
            fontSize: AppFont.px11,
          ),
          const SizedBox(width: 10),
          if (_inspection != null)
            Text(
              _inspection!.ok ? l10n.engineCheckPassed : l10n.engineCheckFailed(_inspection!.failedRequired.length),
              style: TextStyle(fontSize: AppFont.px11, color: _inspection!.ok ? palette.good : palette.bad),
            ),
        ],
      ),
      if (_checkError != null) ...[
        const SizedBox(height: 8),
        Text(
          _checkError!,
          style: TextStyle(fontSize: AppFont.px10_5, color: palette.bad),
        ),
      ],
      if (_inspection != null) ...[
        const SizedBox(height: 12),
        _PartsList(inspection: _inspection!, l10n: l10n),
        // 只有失败才出日志块 —— 成功时刷屏没有价值。
        if (!_inspection!.ok) ...[
          const SizedBox(height: 10),
          LogBox(lines: _inspection!.logLines, title: l10n.engineCheckLog, maxHeight: 180),
          const SizedBox(height: 10),
          _RedownloadHint(
            missing: _inspection!.failedRequired.map((c) => c.part.id).join(', '),
            onRedownload: () =>
                Navigator.of(context).pop(RuntimePickResult(dir: _dir, imported: true, inspection: _inspection)),
          ),
        ],
      ],
    ];
  }
}

/// 目录行。
class _DirRow extends StatelessWidget {
  const _DirRow({required this.dir, required this.label, required this.onChange});

  final String dir;
  final String label;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.folder, size: 13, color: palette.mut),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: AppFont.px9, color: palette.mut),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  dir,
                  maxLines: 2,
                  style: TextStyle(fontSize: AppFont.px10_5, color: palette.ink, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          AppButton(
            label: l10n.runtimePickChange,
            onTap: onChange,
            variant: AppButtonVariant.link,
            fontSize: AppFont.px11,
          ),
        ],
      ),
    );
  }
}

/// 七个部件的状态行。
class _PartsList extends StatelessWidget {
  const _PartsList({required this.inspection, required this.l10n});

  final EngineInspection inspection;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      ),
      child: Column(
        children: [
          for (final (i, c) in inspection.checks.indexed) ...[
            if (i > 0) Container(height: 1, color: palette.line),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    c.ok ? LucideIcons.circleCheck : (c.part.required ? LucideIcons.circleX : LucideIcons.circleMinus),
                    size: 13,
                    color: c.ok ? palette.good : (c.part.required ? palette.bad : palette.mut),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: Text(
                      c.part.id,
                      style: TextStyle(fontSize: AppFont.px10_5, color: palette.ink2),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      c.detail ?? (c.ok ? l10n.enginePartReady : l10n.enginePartMissing),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px10, color: c.ok ? palette.mut : palette.bad),
                    ),
                  ),
                  if (!c.part.required && !c.ok)
                    Text(
                      l10n.enginePartOptional,
                      style: TextStyle(fontSize: AppFont.px9, color: palette.mut),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 校验失败后的引导：重新下载缺失部件（同样要先选目录）。
class _RedownloadHint extends StatelessWidget {
  const _RedownloadHint({required this.missing, required this.onRedownload});

  final String missing;
  final VoidCallback onRedownload;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: palette.bad.withValues(alpha: 0.08),
        border: Border.all(color: palette.bad.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.engineRedownloadHint(missing),
            style: TextStyle(fontSize: AppFont.px10_5, height: 1.5, color: palette.ink2),
          ),
          const SizedBox(height: 8),
          AppButton(
            label: l10n.engineRedownloadMissing,
            icon: LucideIcons.download,
            onTap: onRedownload,
            variant: AppButtonVariant.primary,
            height: 30,
            horizontalPadding: 14,
            fontSize: AppFont.px11,
          ),
        ],
      ),
    );
  }
}
