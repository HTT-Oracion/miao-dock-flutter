import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/buttons.dart';
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
    this.onVerifyRemote,
    this.onOpenRemoteSettings,
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

  /// 【校验远程配置】：直接探测已保存的远程地址、令牌与对面引擎。
  final VoidCallback? onVerifyRemote;

  /// 【去设置远程配置】：跳到设置页的「翻译服务」分组。
  final VoidCallback? onOpenRemoteSettings;

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
  /// 返回 true 才算导出成功（用户取消 = false）。
  final Future<bool> Function(String text, String suggestedName)? onExportLogs;

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
            // 窄屏走精简版：移动端不跑本地引擎，分层状态 / 三步教程 / 日志框
            // 全是桌面排查用的噪音，只保留「结论 + 一个按钮」（D-138）。
            child: context.isMobile
                ? _MobileNotReadyCard(
                    view: view,
                    onPrimary: onPrimary,
                    onSecondary: onSecondary,
                    onVerifyRemote: onVerifyRemote,
                    onOpenRemoteSettings: onOpenRemoteSettings,
                    onRetryService: onRetryService,
                    onTogglePause: onTogglePause,
                    paused: paused,
                    onImportLocal: onImportLocal,
                    onBrowseLibrary: onBrowseLibrary,
                  )
                : _NotReadyCard(
                    view: view,
                    onPrimary: onPrimary,
                    onSecondary: onSecondary,
                    onVerifyRemote: onVerifyRemote,
                    onOpenRemoteSettings: onOpenRemoteSettings,
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
    this.onVerifyRemote,
    this.onOpenRemoteSettings,
  });

  final NotReadyView view;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;
  final VoidCallback? onVerifyRemote;
  final VoidCallback? onOpenRemoteSettings;
  final VoidCallback onRetryService;
  final VoidCallback? onTogglePause;
  final bool paused;

  /// 返回 true 才算导出成功（用户取消 = false）。
  final Future<bool> Function(String text, String suggestedName)? onExportLogs;
  final VoidCallback? onImportLocal;
  final VoidCallback? onBrowseLibrary;
  final List<InstallEntry> downloadEntries;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final meta = _metaOf(l10n, view);
    final remoteBlocked =
        view.state != NotReadyState.degraded &&
        view.source == TranslateSource.remote &&
        !view.remoteVerification.isReady;

    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
      ),
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(icon: meta.icon, title: meta.title, chip: meta.chip, chipTone: meta.tone, desc: meta.desc),
          const SizedBox(height: 24),
          _LayerStrip(view: view),
          const SizedBox(height: 24),
          if (view.state != NotReadyState.downloading) ...[
            _StepsRow(remote: remoteBlocked),
            const SizedBox(height: 32),
          ],
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
            onVerifyRemote: onVerifyRemote,
            onOpenRemoteSettings: onOpenRemoteSettings,
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
    NotReadyView view,
  ) {
    if (view.state != NotReadyState.degraded &&
        view.source == TranslateSource.remote &&
        !view.remoteVerification.isReady) {
      return switch (view.remoteVerification) {
        RemoteVerificationState.checking => (
          icon: LucideIcons.loader,
          title: l10n.remoteGateCheckingTitle,
          desc: l10n.remoteGateDesc,
          chip: l10n.remoteChecking,
          tone: _Tone.warn,
        ),
        RemoteVerificationState.failed => (
          icon: LucideIcons.cloudOff,
          title: l10n.remoteGateFailedTitle,
          desc: l10n.remoteGateDesc,
          chip: l10n.remoteFail,
          tone: _Tone.bad,
        ),
        _ => (
          icon: LucideIcons.shieldCheck,
          title: l10n.remoteGateTitle,
          desc: l10n.remoteGateDesc,
          chip: l10n.remoteGateUnverified,
          tone: _Tone.warn,
        ),
      };
    }

    return switch (view.state) {
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
        // 原型：36×36 图标块（浅色底 + 主色图标），不再用 64 的大块。
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: chipTone == _Tone.bad ? tone.withValues(alpha: 0.12) : palette.accSoft,
            borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
          ),
          child: Icon(icon, size: 20, color: chipTone == _Tone.bad ? tone : palette.acc),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w600, color: palette.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: tone.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      chip,
                      style: TextStyle(fontSize: AppFont.px12, color: tone),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                style: TextStyle(fontSize: AppFont.px11_5, height: 1.65, color: palette.ink2),
              ),
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
    final remote = view.source == TranslateSource.remote;
    final engineReady = remote ? view.remoteVerification.isReady : view.engine.isReady;
    final remoteFailed = view.remoteVerification == RemoteVerificationState.failed;
    var remoteStatus = l10n.remoteGateUnverified;
    if (engineReady) {
      remoteStatus = l10n.remoteOk;
    } else if (remoteFailed) {
      remoteStatus = l10n.remoteFail;
    }
    var serviceColor = palette.good;
    if (serviceBroken || remoteFailed) {
      serviceColor = palette.bad;
    } else if (remote && !engineReady) {
      serviceColor = palette.warn;
    }
    var serviceStatus = l10n.engineReady;
    if (serviceBroken) {
      serviceStatus = l10n.nrChipDegraded;
    } else if (remote) {
      serviceStatus = remoteStatus;
    }
    var engineColor = palette.mut;
    if (engineReady) {
      engineColor = palette.good;
    } else if (view.engine == EngineRuntimeState.failed || remoteFailed) {
      engineColor = palette.bad;
    }

    // 图标对应原型三卡：远程连接=link / 引擎+大模型=cpu / 翻译来源=cloud。
    final rows = <(Color, IconData, String, String, String)>[
      (
        serviceColor,
        remote ? LucideIcons.link : LucideIcons.server,
        remote ? l10n.remoteTitle : l10n.nrLayerService,
        serviceStatus,
        remote ? l10n.sourceRemote : l10n.nrLayerServiceSub,
      ),
      (
        engineColor,
        LucideIcons.cpu,
        l10n.nrLayerEngine,
        engineReady ? l10n.engineReady : l10n.engineNotReady,
        remote ? l10n.remoteGateEngineSub : l10n.nrLayerEngineSub,
      ),
      (
        palette.blue,
        LucideIcons.cloud,
        l10n.nrLayerSource,
        _sourceLabel(l10n, view.source),
        _sourceSub(l10n, view.source),
      ),
    ];

    // 三列状态卡（原型 .status-grid）：均分三列，窄屏由外层走精简卡。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: _StatusCard(icon: r.$2, color: r.$1, title: r.$3, value: r.$4, desc: r.$5),
          ),
        ],
      ],
    );
  }
}

/// 单张状态卡（原型 `.status-card`）：小图标 + 标题 / 值 / 说明。
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.desc,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final warn = color == palette.warn;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: palette.mut),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFont.px11, color: palette.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFont.px14,
              fontWeight: FontWeight.w600,
              color: warn ? palette.warn : palette.ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            desc,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppFont.px10_5, height: 1.4, color: palette.mut),
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
            ? Text(
                l10n.nrDescDownloading,
                style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
              )
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
                  style: TextStyle(
                    fontSize: AppFont.px10_5,
                    color: entry.state == 'waiting' ? palette.mut : palette.ink,
                  ),
                ),
              ),
              Text(
                '${entry.sizeMb.toStringAsFixed(0)} MB',
                style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
              ),
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
                    fontSize: AppFont.px8_5,
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
    this.onVerifyRemote,
    this.onOpenRemoteSettings,
  });

  final NotReadyView view;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;
  final VoidCallback? onVerifyRemote;
  final VoidCallback? onOpenRemoteSettings;
  final VoidCallback onRetryService;
  final VoidCallback? onTogglePause;
  final bool paused;
  final VoidCallback? onImportLocal;
  final VoidCallback? onBrowseLibrary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final remoteBlocked =
        view.state != NotReadyState.degraded &&
        view.source == TranslateSource.remote &&
        !view.remoteVerification.isReady;
    final remoteChecking = view.remoteVerification == RemoteVerificationState.checking;
    // 主按钮原地探测；配置缺失或失败时由次按钮进入设置页修正。
    final primary = remoteBlocked
        ? (remoteChecking ? l10n.remoteChecking : l10n.remoteGateActionVerify)
        : switch (view.state) {
            NotReadyState.uninstalled => l10n.nrActionDownload,
            NotReadyState.installed => l10n.nrActionStart,
            NotReadyState.starting => l10n.nrActionStarting,
            NotReadyState.failed => l10n.nrActionRetry,
            NotReadyState.degraded => l10n.nrActionRestartService,
            NotReadyState.downloading => paused ? l10n.nrActionResume : l10n.nrActionPause,
          };

    // 主操作与次要操作**分行**：原来并排时主按钮和「重新下载」同高同宽，
    // 视觉上没有主次，用户得逐个读文字才知道点哪个（桌面端实测反馈）。
    // 现在主按钮独占一行且更宽更高，次要操作降为一行小字链接。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 200,
          child: AppButton(
            label: primary,
            // 校验中显示 spinner（用户要求）：`loading` 自带转圈且禁用点击。
            loading: remoteChecking,
            onTap: view.state == NotReadyState.starting || remoteChecking
                ? null
                : (remoteBlocked
                      ? onVerifyRemote
                      : (view.state == NotReadyState.degraded
                            ? onRetryService
                            : (view.state == NotReadyState.downloading ? onTogglePause : onPrimary))),
            clickable: view.state != NotReadyState.starting && !remoteChecking,
            variant: AppButtonVariant.primary,
            height: 36,
            horizontalPadding: 24,
            fontSize: AppFont.px12_5,
          ),
        ),
        if (_secondaryActions(context, l10n, remoteBlocked).isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _secondaryActions(context, l10n, remoteBlocked),
          ),
        ],
      ],
    );
  }

  /// 次要操作（统一降级为 link，不与主按钮争视觉）。
  List<Widget> _secondaryActions(BuildContext context, AppLocalizations l10n, bool remoteBlocked) {
    final out = <Widget>[];
    if (remoteBlocked && (onOpenRemoteSettings ?? onSecondary) != null) {
      out.add(
        AppButton(
          label: l10n.remoteGateActionSettings,
          onTap: onOpenRemoteSettings ?? onSecondary,
          variant: AppButtonVariant.link,
          fontSize: AppFont.px10_5,
        ),
      );
    }
    if (!remoteBlocked && view.state == NotReadyState.failed && onSecondary != null) {
      out.add(
        AppButton(
          label: l10n.nrActionRedownload,
          onTap: onSecondary,
          variant: AppButtonVariant.link,
          fontSize: AppFont.px10_5,
        ),
      );
    }
    if (view.state == NotReadyState.uninstalled && onImportLocal != null) {
      out.add(
        AppButton(
          label: l10n.runtimeImport,
          onTap: onImportLocal,
          variant: AppButtonVariant.link,
          fontSize: AppFont.px10_5,
        ),
      );
    }
    if (onBrowseLibrary != null) {
      out.add(
        AppButton(
          label: l10n.engineBrowseLibrary,
          onTap: onBrowseLibrary,
          variant: AppButtonVariant.link,
          fontSize: AppFont.px10_5,
        ),
      );
    }
    return out;
  }
}

/// 窄屏引导卡（D-138）：只讲**结论 + 一个动作**。
///
/// 移动端不跑本地引擎 —— 分层状态 / 三步教程 / 日志框都是桌面排查用的，
/// 塞进手机只会让用户不知道点哪。保留下来的三样是真正有用的：
/// 远程校验失败原因（一行）、下载进度（防"以为卡死"）、浏览书架出口。
class _MobileNotReadyCard extends StatelessWidget {
  const _MobileNotReadyCard({
    required this.view,
    required this.onPrimary,
    required this.onSecondary,
    required this.onRetryService,
    required this.onTogglePause,
    required this.paused,
    required this.onImportLocal,
    required this.onBrowseLibrary,
    this.onVerifyRemote,
    this.onOpenRemoteSettings,
  });

  final NotReadyView view;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;
  final VoidCallback? onVerifyRemote;
  final VoidCallback? onOpenRemoteSettings;
  final VoidCallback onRetryService;
  final VoidCallback? onTogglePause;
  final bool paused;
  final VoidCallback? onImportLocal;
  final VoidCallback? onBrowseLibrary;

  /// 结构化失败 → 一行人话（UI 层查 ARB；controller 不带中文）。
  static String _failureText(AppLocalizations l10n, ({RemoteVerifyIssue kind, String? detail}) f) => switch (f.kind) {
    RemoteVerifyIssue.configIncomplete => l10n.remoteVerifyConfigIncomplete,
    RemoteVerifyIssue.engineNotReady => l10n.remoteVerifyEngineNotReady,
    RemoteVerifyIssue.probeFailed => f.detail == null ? l10n.remoteFail : '${l10n.remoteFail}：${f.detail}',
  };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final meta = _NotReadyCard._metaOf(l10n, view);
    final remoteBlocked =
        view.state != NotReadyState.degraded &&
        view.source == TranslateSource.remote &&
        !view.remoteVerification.isReady;
    final remoteChecking = view.remoteVerification == RemoteVerificationState.checking;
    final busy = view.state == NotReadyState.starting || remoteChecking;

    final primary = remoteBlocked
        ? (remoteChecking ? l10n.remoteChecking : l10n.remoteGateActionVerify)
        : switch (view.state) {
            NotReadyState.uninstalled => l10n.nrActionDownload,
            NotReadyState.installed => l10n.nrActionStart,
            NotReadyState.starting => l10n.nrActionStarting,
            NotReadyState.failed => l10n.nrActionRetry,
            NotReadyState.degraded => l10n.nrActionRestartService,
            NotReadyState.downloading => paused ? l10n.nrActionResume : l10n.nrActionPause,
          };

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(meta.icon, size: 22, color: meta.tone == _Tone.bad ? palette.bad : palette.acc),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  meta.title,
                  style: TextStyle(fontSize: AppFont.px14, fontWeight: FontWeight.w700, color: palette.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            meta.desc,
            style: TextStyle(fontSize: AppFont.px11_5, height: 1.6, color: palette.ink2),
          ),
          // 远程校验失败：把**原因**摆出来（一行，截断），否则用户只会看到"失败"。
          if (view.remoteVerification == RemoteVerificationState.failed && view.remoteFailure != null) ...[
            const SizedBox(height: 8),
            Text(
              _failureText(l10n, view.remoteFailure!),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFont.px10_5, height: 1.5, color: palette.bad),
            ),
          ],
          // 下载中：细进度条 + 百分比（没有反馈会被当成卡死）。
          if (view.state == NotReadyState.downloading) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: view.downloadProgress,
                  backgroundColor: palette.progressTrack,
                  valueColor: AlwaysStoppedAnimation(palette.acc),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              view.downloadProgress == null ? l10n.nrDownloading : '${(view.downloadProgress! * 100).round()}%',
              style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
            ),
          ],
          const SizedBox(height: 18),
          // 主按钮**占满整行**：窄屏上并排会窄成一条，单手也难点中。
          AppButton(
            label: primary,
            onTap: busy
                ? null
                : (remoteBlocked
                      ? onVerifyRemote
                      : (view.state == NotReadyState.degraded
                            ? onRetryService
                            : (view.state == NotReadyState.downloading ? onTogglePause : onPrimary))),
            clickable: !busy,
            variant: AppButtonVariant.primary,
            height: 42,
            fontSize: AppFont.px12_5,
          ),
          // 远程门禁的第二个动作：跳设置页「翻译服务」。
          if (remoteBlocked && (onOpenRemoteSettings ?? onSecondary) != null) ...[
            const SizedBox(height: 10),
            AppButton(
              label: l10n.remoteGateActionSettings,
              onTap: onOpenRemoteSettings ?? onSecondary,
              variant: AppButtonVariant.secondary,
              height: 40,
              fontSize: AppFont.px11_5,
            ),
          ],
          if (onBrowseLibrary != null) ...[
            const SizedBox(height: 10),
            AppButton(
              label: l10n.engineBrowseLibrary,
              onTap: onBrowseLibrary,
              variant: AppButtonVariant.link,
              fontSize: AppFont.px11,
            ),
          ],
        ],
      ),
    );
  }
}

/// 横向步骤条（原型 `.steps-wrap`）：序号圆点 + 文案，中间用短横线连接。
class _StepsRow extends StatelessWidget {
  const _StepsRow({this.remote = false});

  final bool remote;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final steps = remote
        ? [l10n.remoteGateStep1, l10n.remoteGateStep2, l10n.remoteGateStep3]
        : [l10n.nrStep1, l10n.nrStep2, l10n.nrStep3];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      ),
      child: Row(
        children: [
          for (final (i, s) in steps.indexed) ...[
            if (i > 0) ...[
              Container(width: 20, height: 1, color: palette.line2, margin: const EdgeInsets.symmetric(horizontal: 12)),
            ],
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: palette.accSoft, shape: BoxShape.circle),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(fontSize: AppFont.px10, fontWeight: FontWeight.w600, color: palette.acc),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      s,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px11_5, color: palette.ink2),
                    ),
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

/// 翻译来源的展示名。
String _sourceLabel(AppLocalizations l10n, TranslateSource source) => switch (source) {
  TranslateSource.local => l10n.sourceLocal,
  TranslateSource.llm => l10n.sourceLlm,
  TranslateSource.remote => l10n.sourceRemote,
};

/// 翻译来源的一句话说明。
String _sourceSub(AppLocalizations l10n, TranslateSource source) => switch (source) {
  TranslateSource.local => l10n.sourceLocalSub,
  TranslateSource.llm => l10n.sourceLlmSub,
  TranslateSource.remote => l10n.sourceRemoteSub,
};
