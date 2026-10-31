import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/storage/paths.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';

/// 引擎运行时目录选择（D-015）。
///
/// ## 为什么每次下载都要弹
/// 引擎与模型数 GB，装在系统盘可能是用户的真实痛点。**不记忆上次选择**是有意的：
/// 用户换机器 / 换盘时，不会被静默塞回旧位置。
///
/// ## 两个入口
/// - **下载**：选一个目录，开始下载；
/// - **导入本地**：指向已有的 runtimes 目录，跳过下载直接使用（支持离线 / 内网分发）。
///
/// ## 校验的边界（重要）
/// 当前只做**浅检查**（`src/` 与 `venv/` 是否存在）。
/// 版本匹配、模型齐全、venv 可用性属于**完整性校验**，见 P0-F6d（已记账，后做）。
/// 界面必须如实说明这一点，不能让用户以为已经校验过。
class RuntimePickerDialog extends ConsumerStatefulWidget {
  const RuntimePickerDialog({super.key, required this.initialDir});

  /// 初始目录（默认 = `<appData>/MiaoDock/manga/runtimes`）。
  final String initialDir;

  /// 返回选定的目录；取消返回 null。
  static Future<RuntimePickResult?> show(BuildContext context, {String? initialDir}) {
    return showDialog<RuntimePickResult>(
      context: context,
      builder: (_) => RuntimePickerDialog(initialDir: initialDir ?? mangaRuntimeRoot()),
    );
  }

  @override
  ConsumerState<RuntimePickerDialog> createState() => _RuntimePickerDialogState();
}

/// 选择结果。
class RuntimePickResult {
  const RuntimePickResult({required this.dir, required this.imported});

  final String dir;

  /// true = 导入本地（跳过下载）；false = 下载到这里。
  final bool imported;
}

class _RuntimePickerDialogState extends ConsumerState<RuntimePickerDialog> {
  late String _dir = widget.initialDir;
  bool _importMode = false;
  List<String> _missing = const [];
  bool _checked = false;

  Future<void> _pickDir() async {
    final picked = await getDirectoryPath(initialDirectory: _dir);
    if (picked == null || !mounted) return;
    setState(() {
      _dir = picked;
      if (_importMode) {
        _check();
      } else {
        _checked = false;
        _missing = const [];
      }
    });
  }

  /// 浅检查（**不是完整性校验**）。
  void _check() {
    final missing = inspectRuntimeDir(_dir);
    setState(() {
      _missing = missing;
      _checked = true;
    });
  }

  void _toggleImportMode() {
    setState(() {
      _importMode = !_importMode;
      if (_importMode) {
        _check();
      } else {
        _checked = false;
        _missing = const [];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final valid = !_importMode || (_checked && _missing.isEmpty);

    return Dialog(
      backgroundColor: palette.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppMetrics.radiusModal)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _importMode ? LucideIcons.folderInput : LucideIcons.hardDriveDownload,
                    size: 16,
                    color: palette.acc,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _importMode ? l10n.runtimeImportTitle : l10n.runtimePickTitle,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 14),
                    color: palette.ink2,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _importMode ? l10n.runtimeImportDesc : l10n.runtimePickDesc,
                style: TextStyle(fontSize: 11, height: 1.6, color: palette.ink2),
              ),
              const SizedBox(height: 14),
              // 目录行
              Container(
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
                            _importMode ? l10n.runtimeImportPick : l10n.runtimePickDefault,
                            style: TextStyle(fontSize: 9, color: palette.mut),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            _dir,
                            maxLines: 2,
                            style: TextStyle(fontSize: 10.5, color: palette.ink, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _pickDir,
                      child: Text(l10n.runtimePickChange, style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
              // 导入模式：校验结果
              if (_importMode && _checked) ...[const SizedBox(height: 10), _ValidationHint(missing: _missing)],
              const SizedBox(height: 14),
              // 模式切换
              TextButton.icon(
                onPressed: _toggleImportMode,
                icon: Icon(_importMode ? LucideIcons.download : LucideIcons.folderInput, size: 13),
                label: Text(
                  _importMode ? l10n.runtimePickTitle : l10n.runtimeImport,
                  style: const TextStyle(fontSize: 11),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: palette.acc,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.actionCancel, style: const TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: valid
                        ? () => Navigator.of(context).pop(RuntimePickResult(dir: _dir, imported: _importMode))
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.acc,
                      foregroundColor: palette.onAcc,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    child: Text(_importMode ? l10n.runtimeImportOk : l10n.runtimePickConfirm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 校验提示 —— 如实说明「只做了浅检查」。
class _ValidationHint extends StatelessWidget {
  const _ValidationHint({required this.missing});

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final ok = missing.isEmpty;
    final tone = ok ? palette.good : palette.bad;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        border: Border.all(color: tone.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? LucideIcons.circleCheck : LucideIcons.circleAlert, size: 13, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok
                      ? l10n.runtimeImportOk
                      : '${l10n.runtimeImportInvalid} · ${l10n.runtimeImportMissing(missing.join(', '))}',
                  style: TextStyle(fontSize: 11, color: tone),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 🔴 如实告知：只做了结构检查，不是完整性校验。
          Text(l10n.runtimeNotVerifiedHint, style: TextStyle(fontSize: 9.5, height: 1.5, color: palette.mut)),
        ],
      ),
    );
  }
}
