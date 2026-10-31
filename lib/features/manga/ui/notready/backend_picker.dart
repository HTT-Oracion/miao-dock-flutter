import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:protocol/protocol.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';

/// 推理后端选择（D-027 / D-034）。
///
/// ## 只在 Windows / Linux 出现
/// macOS 只有一种构建（自带 Metal），给用户一个「后端」下拉只会造成困惑。
///
/// ## 为什么把体积写在选项上
/// CUDA（约 626 MB，含 cudart）与 Vulkan（约 32 MB）差 **20 倍**。
/// 不写清楚，用户会在下载开始后才发现要等很久。
///
/// ## 为什么没有 DirectML
/// llama.cpp 官方 release 没有该构建（实测 b11417 资产清单）。给一个下不了的后端
/// 等于挖坑 —— 用户选了必然「下载失败」。
class LlamaBackendPicker extends StatelessWidget {
  const LlamaBackendPicker({super.key, required this.probe, this.current = LlamaBackend.auto});

  final BackendProbe probe;
  final LlamaBackend current;

  /// 返回选中的后端；取消返回 null。
  static Future<LlamaBackend?> show(
    BuildContext context, {
    required BackendProbe probe,
    LlamaBackend current = LlamaBackend.auto,
  }) {
    return showDialog<LlamaBackend>(
      context: context,
      builder: (_) => LlamaBackendPicker(probe: probe, current: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

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
                  Icon(LucideIcons.cpu, size: 16, color: palette.acc),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.enginePickBackendTitle,
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
              Text(l10n.enginePickBackendDesc, style: TextStyle(fontSize: 11, height: 1.6, color: palette.ink2)),
              const SizedBox(height: 12),
              // 探测结论：让「自动」不是一个黑盒。
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: palette.accSoft,
                  borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.sparkles, size: 12, color: palette.acc),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        backendReasonText(l10n, probe),
                        style: TextStyle(fontSize: 10.5, color: palette.ink2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Option(
                backend: LlamaBackend.auto,
                label: l10n.engineBackendAuto,
                note: backendReasonText(l10n, probe),
                selected: current == LlamaBackend.auto,
                onTap: () => Navigator.of(context).pop(LlamaBackend.auto),
              ),
              for (final b in const [LlamaBackend.cpu, LlamaBackend.vulkan, LlamaBackend.cuda12])
                _Option(
                  backend: b,
                  label: _labelOf(l10n, b),
                  note: b == LlamaBackend.cuda12 ? l10n.engineBackendCudaNote : null,
                  sizeMb: b.approxMb,
                  selected: current == b,
                  onTap: () => Navigator.of(context).pop(b),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _labelOf(AppLocalizations l10n, LlamaBackend b) => switch (b) {
    LlamaBackend.cpu => l10n.engineBackendCpu,
    LlamaBackend.vulkan => l10n.engineBackendVulkan,
    LlamaBackend.cuda12 => l10n.engineBackendCuda,
    LlamaBackend.auto => l10n.engineBackendAuto,
  };
}

class _Option extends StatelessWidget {
  const _Option({
    required this.backend,
    required this.label,
    required this.selected,
    required this.onTap,
    this.note,
    this.sizeMb,
  });

  final LlamaBackend backend;
  final String label;
  final String? note;
  final int? sizeMb;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? palette.acc : palette.line),
          borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
        ),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.circleDot : LucideIcons.circle,
              size: 13,
              color: selected ? palette.acc : palette.mut,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.ink),
                  ),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(note!, style: TextStyle(fontSize: 9.5, color: palette.mut)),
                    ),
                ],
              ),
            ),
            if (sizeMb != null && sizeMb! > 0)
              Text(l10n.engineBackendSize(sizeMb!), style: TextStyle(fontSize: 10, color: palette.ink2)),
          ],
        ),
      ),
    );
  }
}

/// 探测结论的**可读文案**（UI 层拼，探测本身只给结构化结论）。
String backendReasonText(AppLocalizations l10n, BackendProbe probe) {
  if (probe.recommended == LlamaBackend.cuda12) return l10n.backendReasonCudaNvidia;
  if (probe.recommended == LlamaBackend.cpu) return l10n.backendReasonCpu;
  return probe.vendor == null ? l10n.backendReasonVulkanNoNvidia : l10n.backendReasonVulkanDevice;
}

/// 是否需要让用户选后端（只有 Windows / Linux）。
bool get backendSelectable => Platform.isWindows || Platform.isLinux;

/// 探测后端。**只在 Windows / Linux 有意义**。
///
/// 判断顺序：NVIDIA 运行时可执行 → CUDA；否则若有可用的图形设备 → Vulkan；
/// 都没有 → CPU。不引入 `rocm` / `sycl`（D-027 定案：先不暴露）。
Future<BackendProbe> probeBackend({Future<bool> Function(String exe, List<String> args)? runnable}) async {
  final run = runnable ?? _canRun;
  if (Platform.isWindows) {
    if (await run('nvidia-smi', ['--query-gpu=name', '--format=csv,noheader'])) {
      return const BackendProbe(recommended: LlamaBackend.cuda12, reason: '', vendor: 'nvidia');
    }
    return const BackendProbe(recommended: LlamaBackend.vulkan, reason: '');
  }
  // Linux
  if (await run('nvidia-smi', ['-L'])) {
    return const BackendProbe(recommended: LlamaBackend.cuda12, reason: '', vendor: 'nvidia');
  }
  if (Directory('/dev/dri').existsSync()) {
    return const BackendProbe(recommended: LlamaBackend.vulkan, reason: '');
  }
  return const BackendProbe(recommended: LlamaBackend.cpu, reason: '');
}

Future<bool> _canRun(String exe, List<String> args) async {
  try {
    final r = await Process.run(exe, args).timeout(const Duration(seconds: 3));
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
