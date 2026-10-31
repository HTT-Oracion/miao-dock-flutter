import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/storage/engine_inspect.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/log_box.dart';
import '../../manga/ui/notready/runtime_picker.dart';
import '../../manga/controller/engine_ready_controller.dart';
import '../controller/engine_dir_controller.dart';

/// 设置页「引擎与模型」小节的**部件表**（D-027）。
///
/// ## 三件事放在一起
/// 1. **目录**：当前引擎目录 + 更改 + 导入本地（导入必须校验）；
/// 2. **部件状态**：七个部件逐行显示在 / 缺；
/// 3. **校验**：手动触发（会起子进程，慢），失败才展开日志并给「重新下载缺失部件」。
///
/// 🔴 「没校验」与「校验通过」必须长得不一样：把未校验画成绿色，
/// 等于告诉用户「没问题」，而实际上我们什么都没检查。
class EnginePartsSection extends ConsumerWidget {
  const EnginePartsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final dir = ref.watch(engineDirProvider);
    final inspection = ref.watch(engineInspectionProvider);
    final busy = inspection.isLoading;

    final result = inspection.value;
    final hasError = inspection.hasError;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 目录行 ───────────────────────────────────────────────
          Row(
            children: [
              const SizedBox(width: 8),
              Text(l10n.engineDirLabel, style: TextStyle(fontSize: 10.5, color: palette.ink2)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dir,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: palette.mut, fontFamily: 'monospace'),
                ),
              ),
              TextButton(
                onPressed: busy ? null : () => _changeDir(context, ref),
                child: Text(l10n.runtimePickChange, style: const TextStyle(fontSize: 10.5)),
              ),
              TextButton.icon(
                onPressed: busy ? null : () => _importDir(context, ref),
                icon: const Icon(LucideIcons.folderInput, size: 12),
                label: Text(l10n.runtimeImport, style: const TextStyle(fontSize: 10.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ── 校验按钮 + 结论 ───────────────────────────────────────
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => ref.read(engineInspectionProvider.notifier).run(),
                icon: busy
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.shieldCheck, size: 12),
                label: Text(busy ? l10n.engineChecking : l10n.engineCheck, style: const TextStyle(fontSize: 10.5)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              const SizedBox(width: 8),
              // 轻量重查：只重做门禁用的快检（毫秒级），不起子进程。
              TextButton(
                onPressed: busy ? null : () => ref.read(enginePresenceProvider.notifier).refresh(),
                style: TextButton.styleFrom(minimumSize: const Size(0, 30)),
                child: Text(l10n.engineRecheck, style: const TextStyle(fontSize: 10.5)),
              ),
              const SizedBox(width: 10),
              Expanded(child: _Verdict(inspection: inspection)),
            ],
          ),
          // ── 部件列表 ─────────────────────────────────────────────
          if (result != null) ...[
            const SizedBox(height: 12),
            _PartsGrid(inspection: result, l10n: l10n),
            if (!result.ok) ...[
              const SizedBox(height: 10),
              // 失败才出日志：成功时刷屏没有价值。
              LogBox(lines: result.logLines, title: l10n.engineCheckLog, maxHeight: 170),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () => _redownload(context, ref, result),
                    icon: const Icon(LucideIcons.download, size: 12),
                    label: Text(l10n.engineRedownloadMissing, style: const TextStyle(fontSize: 10.5)),
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.acc,
                      foregroundColor: palette.onAcc,
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.engineRedownloadHint(result.failedRequired.map((c) => c.part.id).join(', ')),
                      style: TextStyle(fontSize: 9.5, height: 1.5, color: palette.mut),
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (hasError) ...[
            const SizedBox(height: 8),
            Text('${inspection.error}', style: TextStyle(fontSize: 10, color: palette.bad)),
          ],
        ],
      ),
    );
  }

  Future<void> _changeDir(BuildContext context, WidgetRef ref) async {
    final r = await RuntimePickerDialog.show(context, initialDir: ref.read(engineDirProvider));
    if (r == null) return;
    ref.read(engineDirProvider.notifier).set(r.dir);
    ref.read(engineInspectionProvider.notifier).invalidate();
  }

  Future<void> _importDir(BuildContext context, WidgetRef ref) async {
    final r = await RuntimePickerDialog.show(context, initialDir: ref.read(engineDirProvider), importMode: true);
    if (r == null) return;
    ref.read(engineDirProvider.notifier).set(r.dir);
    // 导入时已校验过，直接沿用结论，不再让用户点第二次。
    if (r.inspection != null) {
      ref.read(engineInspectionProvider.notifier).adopt(r.inspection!);
    }
  }

  Future<void> _redownload(BuildContext context, WidgetRef ref, EngineInspection result) async {
    // D-027：重新下载与直接下载一致 —— **先选目录**。
    final r = await RuntimePickerDialog.show(context, initialDir: ref.read(engineDirProvider));
    if (r == null) return;
    ref.read(engineDirProvider.notifier).set(r.dir);
    ref.read(engineInspectionProvider.notifier).invalidate();
  }
}

/// 校验结论（区分「未校验」「通过」「失败」三态）。
class _Verdict extends StatelessWidget {
  const _Verdict({required this.inspection});

  final AsyncValue<EngineInspection?> inspection;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    if (inspection.isLoading) {
      return Text(l10n.engineChecking, style: TextStyle(fontSize: 10.5, color: palette.mut));
    }
    final r = inspection.value;
    if (r == null) {
      // 🔴 未校验不能画成绿：我们什么都没检查过。
      return Text(l10n.engineNotChecked, style: TextStyle(fontSize: 10.5, color: palette.mut));
    }
    return Text(
      r.ok ? l10n.engineCheckPassed : l10n.engineCheckFailed(r.failedRequired.length),
      style: TextStyle(fontSize: 10.5, color: r.ok ? palette.good : palette.bad),
    );
  }
}

/// 七个部件的紧凑状态行。
class _PartsGrid extends StatelessWidget {
  const _PartsGrid({required this.inspection, required this.l10n});

  final EngineInspection inspection;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in inspection.checks)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: palette.bg,
              border: Border.all(color: c.ok ? palette.line2 : palette.bad.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  c.ok ? LucideIcons.circleCheck : (c.part.required ? LucideIcons.circleX : LucideIcons.circleMinus),
                  size: 11,
                  color: c.ok ? palette.good : (c.part.required ? palette.bad : palette.mut),
                ),
                const SizedBox(width: 5),
                Text(c.part.id, style: TextStyle(fontSize: 9.5, color: palette.ink2)),
                if (!c.part.required) ...[
                  const SizedBox(width: 4),
                  Text(l10n.enginePartOptional, style: TextStyle(fontSize: 8.5, color: palette.mut)),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
