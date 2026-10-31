import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/log_box.dart';
import '../../controller/engine_install_controller.dart';
import '../../domain/not_ready_state.dart';

/// 启动引导页（D-012）—— 取代设计稿原 `guide` / `download` 两个独立整屏。
///
/// ## 它住在右侧主体区，不是独立整屏
/// 进入本页**不切掉侧栏**：用户随时能去设置排查，这是服务出问题时最需要的。
/// URL 仍是 `/manga/*`，刷新与深链行为不变。
///
/// ## 六态一张卡
/// 未装配 / 下载中 / 已装未启动 / 启动中 / 失败 / 服务异常。
/// 每态的主操作不同 —— 尤其**失败态给的是「重新下载模型」而非「重启」**：
/// 引擎运行时坏了时重启毫无意义。
class NotReadyScreen extends StatelessWidget {
  const NotReadyScreen({
    super.key,
    required this.view,
    required this.onPrimary,
    required this.onSecondary,
    required this.onRetryService,
    this.onImportLocal,
    this.onBrowseLibrary,
    this.downloadEntries = const [],
    this.onTogglePause,
    this.paused = false,
    this.onExportLogs,
  });

  final NotReadyView view;

  /// 主操作（下载 / 启动 / 重试 / 重启服务）。
  final VoidCallback onPrimary;

  /// 次操作（去设置 / 重新下载）。
  final VoidCallback? onSecondary;

  /// 服务异常时的重启。
  final VoidCallback onRetryService;

  /// 导入本地运行时（仅未装配态可用）。
  final VoidCallback? onImportLocal;

  /// 下载中的逐条目状态（设计稿：下载卡是「一列文件 + 每行进度条」）。
  final List<InstallEntry> downloadEntries;

  /// 门禁卡片上的「只读出口」：去漫画库（阅读已译作品不需要引擎）。
  ///
  /// 🔴 它**不是**当初被删掉的「稍后再说」——那个跳的是同样需要引擎的队列，会死循环。
  final VoidCallback? onBrowseLibrary;

  /// 下载中：暂停 / 继续。
  final VoidCallback? onTogglePause;
  final bool paused;

  /// 导出日志（桌面端接文件保存对话框）。
  final void Function(String text, String suggestedName)? onExportLogs;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      color: palette.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: _NotReadyCard(
              view: view,
              onPrimary: onPrimary,
              onSecondary: onSecondary,
              onRetryService: onRetryService,
              onTogglePause: onTogglePause,
              paused: paused,
              downloadEntries: downloadEntries,
              onExportLogs: onExportLogs,
              onImportLocal: onImportLocal,
              onBrowseLibrary: onBrowseLibrary,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotReadyCard extends StatelessWidget {
  const _NotReadyCard({
    required this.view,
    required this.onPrimary,
    required this.onSecondary,
    required this.onRetryService,
    required this.onTogglePause,
    required this.paused,
    required this.onExportLogs,
    required this.onImportLocal,
    required this.onBrowseLibrary,
    required this.downloadEntries,
  });

  final NotReadyView view;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;
  final VoidCallback onRetryService;
  final VoidCallback? onTogglePause;
  final bool paused;
  final void Function(String text, String suggestedName)? onExportLogs;
  final VoidCallback? onImportLocal;
  final VoidCallback? onBrowseLibrary;
  final List<InstallEntry> downloadEntries;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final meta = _metaOf(l10n, view.state);

    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(icon: meta.icon, title: meta.title, chip: meta.chip, chipTone: meta.tone, desc: meta.desc),
          const SizedBox(height: 18),
          _LayerStrip(view: view),
          const SizedBox(height: 20),
          if (view.state != NotReadyState.downloading) ...[_StepsRow(), const SizedBox(height: 18)],
          if (view.state == NotReadyState.downloading) ...[
            _DownloadSection(view: view, entries: downloadEntries),
            const SizedBox(height: 16),
          ],
          if (view.state == NotReadyState.failed || view.state == NotReadyState.degraded) ...[
            LogBox(lines: view.logs, title: l10n.logBoxTitle, onExport: onExportLogs),
            const SizedBox(height: 16),
          ],
          _Actions(
            view: view,
            onPrimary: onPrimary,
            onSecondary: onSecondary,
            onRetryService: onRetryService,
            onTogglePause: onTogglePause,
            paused: paused,
            onImportLocal: onImportLocal,
            onBrowseLibrary: onBrowseLibrary,
          ),
        ],
      ),
    );
  }

  /// 演示日志 —— 真实日志接入后由 `view.logs` 覆盖。
  ///
  /// 🔴 不写死假数据上屏：这里只在**没有任何日志来源时**给结构性占位，
  /// 并在 P0-C 接入真实日志后移除。
  static ({IconData icon, String title, String desc, String chip, _Tone tone}) _metaOf(
    AppLocalizations l10n,
    NotReadyState state,
  ) => switch (state) {
    NotReadyState.uninstalled => (
      icon: LucideIcons.download,
      title: l10n.nrTitleUninstalled,
      desc: l10n.nrDescUninstalled,
      chip: l10n.nrChipUninstalled,
      tone: _Tone.warn,
    ),
    NotReadyState.downloading => (
      icon: LucideIcons.download,
      title: l10n.nrTitleDownloading,
      desc: l10n.nrDescDownloading,
      chip: l10n.nrChipDownloading,
      tone: _Tone.warn,
    ),
    NotReadyState.installed => (
      icon: LucideIcons.power,
      title: l10n.nrTitleInstalled,
      desc: l10n.nrDescInstalled,
      chip: l10n.nrChipNotStarted,
      tone: _Tone.warn,
    ),
    NotReadyState.starting => (
      icon: LucideIcons.loader,
      title: l10n.nrTitleStarting,
      desc: l10n.nrDescStarting,
      chip: l10n.nrChipStarting,
      tone: _Tone.warn,
    ),
    NotReadyState.failed => (
      icon: LucideIcons.triangleAlert,
      title: l10n.nrTitleFailed,
      desc: l10n.nrDescFailed,
      chip: l10n.nrChipFailed,
      tone: _Tone.bad,
    ),
    NotReadyState.degraded => (
      icon: LucideIcons.cloudOff,
      title: l10n.nrTitleDegraded,
      desc: l10n.nrDescDegraded,
      chip: l10n.nrChipDegraded,
      tone: _Tone.bad,
    ),
  };
}

enum _Tone { warn, bad }

/// 头部：插画 + 标题 + 状态胶囊 + 说明。
class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.title,
    required this.desc,
    required this.chip,
    required this.chipTone,
  });

  final IconData icon;
  final String title;
  final String desc;
  final String chip;
  final _Tone chipTone;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tone = chipTone == _Tone.bad ? palette.bad : palette.warn;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: chipTone == _Tone.bad ? tone.withValues(alpha: 0.12) : palette.accSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 26, color: chipTone == _Tone.bad ? tone : palette.acc),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: palette.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                    ),
                    child: Text(chip, style: TextStyle(fontSize: 9.5, color: tone)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(desc, style: TextStyle(fontSize: 11.5, height: 1.65, color: palette.ink2)),
            ],
          ),
        ),
      ],
    );
  }
}

/// 三层状态条：服务 / 引擎+大模型 / 来源。
class _LayerStrip extends StatelessWidget {
  const _LayerStrip({required this.view});

  final NotReadyView view;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final serviceBroken = view.state == NotReadyState.degraded;
    final engineReady = view.engine.isReady;

    final rows = <(Color, String, String, String)>[
      (
        serviceBroken ? palette.bad : palette.good,
        l10n.nrLayerService,
        serviceBroken ? l10n.nrChipDegraded : l10n.engineReady,
        l10n.nrLayerServiceSub,
      ),
      (
        engineReady ? palette.good : (view.engine == EngineRuntimeState.failed ? palette.bad : palette.mut),
        l10n.nrLayerEngine,
        engineReady ? l10n.engineReady : l10n.engineNotStarted,
        l10n.nrLayerEngineSub,
      ),
      (palette.blue, l10n.nrLayerSource, _sourceLabel(l10n, view.source), _sourceSub(l10n, view.source)),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: palette.line)),
        child: Column(
          children: [
            for (final (i, r) in rows.indexed) ...[
              if (i > 0) Container(height: 1, color: palette.line),
              Container(
                color: palette.card,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: r.$1, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 96,
                      child: Text(r.$2, style: TextStyle(fontSize: 10.5, color: palette.ink2)),
                    ),
                    Expanded(
                      child: Text(
                        r.$3,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.ink),
                      ),
                    ),
                    Text(r.$4, style: TextStyle(fontSize: 9.5, color: palette.mut)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _sourceLabel(AppLocalizations l10n, TranslateSource s) => switch (s) {
    TranslateSource.local => l10n.sourceLocal,
    TranslateSource.llm => l10n.sourceLlm,
    TranslateSource.remote => l10n.sourceRemote,
  };

  static String _sourceSub(AppLocalizations l10n, TranslateSource s) => switch (s) {
    TranslateSource.local => l10n.sourceLocalSub,
    TranslateSource.llm => l10n.sourceLlmSub,
    TranslateSource.remote => l10n.sourceRemoteSub,
  };
}

/// 三步说明（把原 guide 三大段压成一行）。
class _StepsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final steps = [l10n.nrStep1, l10n.nrStep2, l10n.nrStep3];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        children: [
          for (final (i, s) in steps.indexed)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: palette.accSoft, shape: BoxShape.circle),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: palette.acc),
                  ),
                ),
                const SizedBox(width: 7),
                Text(s, style: TextStyle(fontSize: 10, color: palette.ink2)),
              ],
            ),
        ],
      ),
    );
  }
}

/// 下载进度区。
class _DownloadSection extends StatelessWidget {
  const _DownloadSection({required this.view, required this.entries});

  final NotReadyView view;
  final List<InstallEntry> entries;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    // 没有条目（还没拿到服务端状态）时退回单条总进度，避免空白。
    if (entries.isEmpty) {
      final p = view.downloadProgress;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
          color: palette.card,
        ),
        child: p == null
            ? Text(l10n.nrDescDownloading, style: TextStyle(fontSize: 10.5, color: palette.mut))
            : ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: p,
                  minHeight: 4,
                  backgroundColor: palette.hi,
                  valueColor: AlwaysStoppedAnimation(palette.warn),
                ),
              ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      ),
      child: Column(
        children: [
          for (final (i, e) in entries.indexed) ...[
            if (i > 0) Container(height: 1, color: palette.line),
            _DownloadRow(entry: e),
          ],
        ],
      ),
    );
  }
}

/// 下载卡里的一行（design.html `.dl-item`）。
class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.entry});

  final InstallEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final running = entry.state == 'running';
    final done = entry.state == 'done';
    final failed = entry.state == 'failed';

    final chipText = done
        ? l10n.engineEntryDone
        : failed
        ? l10n.engineEntryFailed
        : running
        ? '${((entry.percent ?? 0) * 100).round()}%'
        : l10n.engineEntryWaiting;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                done
                    ? LucideIcons.circleCheck
                    : failed
                    ? LucideIcons.circleX
                    : running
                    ? LucideIcons.download
                    : LucideIcons.circle,
                size: 13,
                color: done
                    ? palette.good
                    : failed
                    ? palette.bad
                    : running
                    ? palette.acc
                    : palette.mut,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: entry.state == 'waiting' ? palette.mut : palette.ink),
                ),
              ),
              Text('${entry.sizeMb.toStringAsFixed(0)} MB', style: TextStyle(fontSize: 9.5, color: palette.mut)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: done
                      ? palette.good.withValues(alpha: 0.12)
                      : running
                      ? palette.accSoft
                      : palette.hi,
                  borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                ),
                child: Text(
                  chipText,
                  style: TextStyle(
                    fontSize: 8.5,
                    color: done
                        ? palette.good
                        : running
                        ? palette.acc
                        : palette.mut,
                  ),
                ),
              ),
            ],
          ),
          if (running) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: entry.percent,
                minHeight: 3,
                backgroundColor: palette.hi,
                valueColor: AlwaysStoppedAnimation(palette.acc),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 动作区。
class _Actions extends StatelessWidget {
  const _Actions({
    required this.view,
    required this.onPrimary,
    required this.onSecondary,
    required this.onRetryService,
    required this.onTogglePause,
    required this.paused,
    required this.onImportLocal,
    required this.onBrowseLibrary,
  });

  final NotReadyView view;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;
  final VoidCallback onRetryService;
  final VoidCallback? onTogglePause;
  final bool paused;
  final VoidCallback? onImportLocal;
  final VoidCallback? onBrowseLibrary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = switch (view.state) {
      NotReadyState.uninstalled => l10n.nrActionDownload,
      NotReadyState.installed => l10n.nrActionStart,
      NotReadyState.starting => l10n.nrActionStarting,
      NotReadyState.failed => l10n.nrActionRetry,
      NotReadyState.degraded => l10n.nrActionRestartService,
      NotReadyState.downloading => paused ? l10n.nrActionResume : l10n.nrActionPause,
    };

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton(
          onPressed: view.state == NotReadyState.starting
              ? null
              : (view.state == NotReadyState.degraded
                    ? onRetryService
                    : (view.state == NotReadyState.downloading ? onTogglePause : onPrimary)),
          style: FilledButton.styleFrom(
            backgroundColor: AppPalette.of(context).acc,
            foregroundColor: AppPalette.of(context).onAcc,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppMetrics.radiusButton)),
            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          child: Text(primary),
        ),
        if (view.state == NotReadyState.failed && onSecondary != null)
          OutlinedButton(
            onPressed: onSecondary,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(fontSize: 9.5),
            ),
            child: Text(l10n.nrActionRedownload),
          ),
        // 导入本地运行时（D-015）：指向已有 runtimes，跳过下载。
        if (view.state == NotReadyState.uninstalled && onImportLocal != null)
          OutlinedButton.icon(
            onPressed: onImportLocal,
            icon: const Icon(LucideIcons.folderInput, size: 12),
            label: Text(l10n.runtimeImport),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(fontSize: 9.5),
            ),
          ),
        // 只读出口：不需要引擎，因此不会与「等引擎」形成死循环。
        if (onBrowseLibrary != null)
          TextButton(
            onPressed: onBrowseLibrary,
            style: TextButton.styleFrom(minimumSize: const Size(0, 34)),
            child: Text(l10n.engineBrowseLibrary, style: const TextStyle(fontSize: 11)),
          ),
      ],
    );
  }
}
