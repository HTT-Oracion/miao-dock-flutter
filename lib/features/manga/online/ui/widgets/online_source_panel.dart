import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/storage/shell_prefs.dart';
import '../../../../../core/theme/tokens.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/widgets/app_dialog.dart';
import '../../../../../shared/widgets/app_switch.dart';
import '../../../../../shared/widgets/buttons.dart';
import '../../../../../shared/widgets/skeleton.dart';
import '../../../../../shared/widgets/source_import_box.dart';
import '../../../../../shared/widgets/source_list_header.dart';
import '../../../../../shared/widgets/toast.dart';
import '../../controller/online_sources_controller.dart';
import '../../data/legacy_source_manifest.dart';
import '../../data/source_import.dart';
import '../../data/source_package.dart';
import '../../domain/online_source.dart';
import 'online_common.dart';
import 'online_link_import.dart';
import '../../../../../shared/responsive.dart';
import '../../../../../shared/widgets/app_dropdown.dart';

/// 漫画源管理面板（设置 › 漫画源 / 移动端 sheet / 桌面弹窗共用）。
class OnlineSourcePanel extends ConsumerStatefulWidget {
  const OnlineSourcePanel({super.key, this.sheetMode = false, this.maxVisibleSources});

  /// sheet 模式：移动端底部抽屉里内距更紧凑，不出现拖拽文案。
  final bool sheetMode;

  /// 已装源列表最多可见几条；null = 不限（设置页整页滚动）。
  /// 弹窗里传 4，超过后列表区自身滚动。
  final int? maxVisibleSources;

  @override
  ConsumerState<OnlineSourcePanel> createState() => _OnlineSourcePanelState();
}

class _OnlineSourcePanelState extends ConsumerState<OnlineSourcePanel> {
  bool _importing = false;
  bool _dragging = false;

  SourceImporter get _importer => ref.read(sourceImporterProvider);

  Future<void> _pickAndImport() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'source', extensions: ['json', 'js']),
        ],
      );
      if (file == null) return;
      await _importPath(file.path);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, AppLocalizations.of(context).onlineImportFileMissing, tone: ToastTone.bad);
    }
  }

  Future<void> _importDropped(List<DropItem> items) async {
    String? path;
    for (final item in items) {
      final candidate = item.path;
      if (candidate.endsWith('/source.json') || candidate.endsWith('\\source.json') || candidate.endsWith('.js')) {
        path = candidate;
        break;
      }
      try {
        final dir = Directory(candidate);
        if (await dir.exists()) {
          final manifest = File('${dir.path}/source.json');
          if (await manifest.exists()) {
            path = manifest.path;
            break;
          }
        }
      } catch (_) {
        // 非目录路径忽略。
      }
    }
    if (path != null) await _importPath(path);
  }

  Future<void> _importPath(String path) async {
    setState(() => _importing = true);
    SourceImportResult result;
    if (path.endsWith('.js')) {
      try {
        final js = await File(path).readAsString();
        final manifest = legacyManifestFromScript(js, scriptUri: Uri.file(path));
        result = await _importer.installPackage(
          SourcePackageData(manifest: manifest, js: js, sourceUrl: Uri.file(path).toString()),
        );
      } catch (_) {
        result = const SourceImportResult(errors: [SourceIssue('invalidJson', 'js')]);
      }
    } else {
      result = await _importer.importManifest(path);
    }
    if (!mounted) return;
    setState(() => _importing = false);
    await _handleResult(result);
  }

  Future<void> _handleResult(SourceImportResult result) async {
    if (!result.ok) {
      await _showImportResult(result, error: true);
      return;
    }
    final source = result.source!;
    final existing = ref.read(onlineSourcesProvider).value?.where((item) => item.id == source.id).toList();
    final l10n = AppLocalizations.of(context);
    if (existing != null && existing.isNotEmpty) {
      final confirmed = await showAppDialog<bool>(
        context: context,
        builder: (context) => AppDialog(
          title: l10n.onlineConfirmOverwriteTitle,
          icon: LucideIcons.alertTriangle,
          width: 420,
          actions: [
            AppButton(
              label: l10n.onlineCancel,
              onTap: () => Navigator.of(context).pop(false),
              variant: AppButtonVariant.secondary,
              height: 32,
            ),
            AppButton(
              label: l10n.onlineOverwrite,
              onTap: () => Navigator.of(context).pop(true),
              variant: AppButtonVariant.primary,
              height: 32,
            ),
          ],
          child: Text(
            l10n.onlineConfirmOverwriteBody(source.name),
            style: TextStyle(fontSize: AppFont.px12, height: 1.7, color: AppPalette.of(context).ink2),
          ),
        ),
      );
      if (confirmed != true) return;
    }
    await ref.read(onlineSourcesProvider.notifier).addOrReplace(source);
    if (!mounted) return;
    if (result.warnings.isNotEmpty) {
      await _showImportResult(result, error: false);
    } else {
      showAppToast(context, l10n.onlineImportSuccessToast(source.name), tone: ToastTone.good);
    }
  }

  Future<void> _showImportResult(SourceImportResult result, {required bool error}) async {
    final l10n = AppLocalizations.of(context);
    final title = error
        ? l10n.onlineImportRejectedTitle
        : (result.warnings.isNotEmpty ? l10n.onlineImportWarningTitle : l10n.onlineImportSuccess);
    await showAppDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: title,
        icon: error
            ? LucideIcons.circleX
            : (result.warnings.isNotEmpty ? LucideIcons.alertTriangle : LucideIcons.circleCheck),
        width: 480,
        onClose: () => Navigator.of(context).pop(),
        actions: [
          AppButton(
            label: l10n.onlineImportClose,
            onTap: () => Navigator.of(context).pop(),
            variant: AppButtonVariant.primary,
            height: 32,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.errors.isNotEmpty) ...[
              _IssueList(issues: result.errors, error: true),
              const SizedBox(height: 8),
            ],
            if (result.warnings.isNotEmpty) _IssueList(issues: result.warnings, error: false),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (!error && result.source != null) {
      showAppToast(context, l10n.onlineImportWarningTitle, tone: ToastTone.warn);
    } else if (error) {
      showAppToast(context, l10n.onlineImportRejectedTitle, tone: ToastTone.bad);
    }
  }

  Future<void> _openSourceDirectory() async {
    final l10n = AppLocalizations.of(context);
    final root = onlineStateDirectory();
    if (root == null) {
      showAppToast(context, l10n.onlineSourceOpenFailed, tone: ToastTone.bad);
      return;
    }
    final sourcesDir = Directory('${root.path}/sources');
    if (!sourcesDir.existsSync()) sourcesDir.createSync(recursive: true);
    final ok = await _importer.openDirectory(sourcesDir.path);
    if (!mounted) return;
    if (!ok) showAppToast(context, l10n.onlineSourceOpenFailed, tone: ToastTone.bad);
  }

  Future<void> _toggle(OnlineSource source, bool enabled) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(onlineSourcesProvider.notifier).toggle(source.id, enabled);
    if (!mounted) return;
    showAppToast(
      context,
      enabled ? l10n.onlineSourceEnableToast : l10n.onlineSourceDisableToast,
      tone: enabled ? ToastTone.good : ToastTone.info,
    );
  }

  Future<void> _copyId(OnlineSource source) async {
    await Clipboard.setData(ClipboardData(text: source.id));
    if (!mounted) return;
    showAppToast(context, AppLocalizations.of(context).onlineSourceIdCopied, tone: ToastTone.good);
  }

  Future<void> _export(OnlineSource source) => _exportAll([source]);

  Future<void> _exportAll(List<OnlineSource> sources) async {
    final l10n = AppLocalizations.of(context);
    try {
      final dir = await getDirectoryPath(confirmButtonText: l10n.onlineSourceExportPickDir);
      if (dir == null) return;
      var exported = 0;
      for (final source in sources) {
        if (await _importer.exportSource(source, dir) != null) exported++;
      }
      if (!mounted) return;
      if (exported == 0) {
        showAppToast(context, l10n.onlineExportFailed, tone: ToastTone.bad);
      } else {
        showAppToast(context, l10n.onlineSourceExportSuccess(dir), tone: ToastTone.good);
      }
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, l10n.onlineExportFailed, tone: ToastTone.bad);
    }
  }

  Future<void> _reimport(OnlineSource source) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'source', extensions: ['json', 'js']),
        ],
      );
      if (file == null) return;
      await _importPath(file.path);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, AppLocalizations.of(context).onlineImportFileMissing, tone: ToastTone.bad);
    }
  }

  Future<void> _delete(OnlineSource source) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.onlineDeleteConfirmTitle,
        icon: LucideIcons.trash2,
        width: 420,
        actions: [
          AppButton(
            label: l10n.onlineCancel,
            onTap: () => Navigator.of(context).pop(false),
            variant: AppButtonVariant.secondary,
            height: 32,
          ),
          AppButton(
            label: l10n.onlineDelete,
            onTap: () => Navigator.of(context).pop(true),
            variant: AppButtonVariant.danger,
            height: 32,
          ),
        ],
        child: Text(
          l10n.onlineDeleteConfirmBody,
          style: TextStyle(fontSize: AppFont.px12, height: 1.7, color: AppPalette.of(context).ink2),
        ),
      ),
    );
    if (confirmed != true) return;
    await ref.read(onlineSourcesProvider.notifier).remove(source.id);
    if (!mounted) return;
    showAppToast(context, l10n.onlineSourceDeleted(source.name), tone: ToastTone.info);
  }

  void _showDetail(OnlineSource source) {
    final l10n = AppLocalizations.of(context);
    showAppDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.onlineSourceDetailTitle(source.name),
        icon: LucideIcons.info,
        width: 520,
        onClose: () => Navigator.of(context).pop(),
        actions: [
          AppButton(
            label: l10n.onlineClose,
            onTap: () => Navigator.of(context).pop(),
            variant: AppButtonVariant.secondary,
            height: 32,
          ),
        ],
        child: _SourceDetail(source: source),
      ),
    );
  }

  void _showLanguage(OnlineSource source) {
    showAppDialog<void>(
      context: context,
      builder: (_) => _SourceLanguageDialog(source: source),
    );
  }

  void _handleAction(String action, OnlineSource source) {
    switch (action) {
      case 'detail':
        _showDetail(source);
        break;
      case 'language':
        _showLanguage(source);
        break;
      case 'copy':
        _copyId(source);
        break;
      case 'export':
        _export(source);
        break;
      case 'reimport':
        _reimport(source);
        break;
      case 'delete':
        _delete(source);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final sources = ref.watch(onlineSourcesProvider);
    final mobile = context.isMobile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sources.when(
          skipLoadingOnRefresh: true,
          loading: () => Column(
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  border: Border.all(color: palette.line2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    SkeletonBox(width: 160, height: 12),
                    SizedBox(height: 10),
                    SkeletonBox(width: 240, height: 9),
                    SizedBox(height: 8),
                    SkeletonBox(width: 200, height: 9),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.onlineImporting,
                style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
              ),
            ],
          ),
          error: (error, _) => OnlineErrorBox(
            error: error,
            title: l10n.onlinePlatformLoadFailed,
            description: l10n.onlinePlatformLoadFailedHint,
            onRetry: () => ref.read(onlineSourcesProvider.notifier).refresh(),
          ),
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const OnlineLinkImport(),
              const SizedBox(height: 12),
              _dragWrapper(
                SourceImportBox(
                  importing: _importing,
                  mobile: mobile,
                  onImport: _pickAndImport,
                  onOpenDir: mobile ? null : _openSourceDirectory,
                  title: l10n.onlineImportTitle,
                  description: l10n.onlineImportDesc,
                  descriptionMobile: l10n.onlineImportDescMobile,
                  steps: l10n.onlineImportSteps,
                  importLabel: l10n.onlineImportSource,
                  importLabelMobile: l10n.onlineSelectFileVerify,
                  openDirLabel: l10n.onlineOpenSourceDir,
                  importingLabel: l10n.onlineImporting,
                  waitLabel: l10n.onlineWaitImport,
                ),
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OnlineStateBox(
                    icon: LucideIcons.inbox,
                    title: l10n.onlineSourceEmpty,
                    description: l10n.onlineSourceEmptyHintShort,
                    compact: true,
                  ),
                )
              else ...[
                SourceListHeader(
                  title: l10n.onlineImportedTitle,
                  count: items.length,
                  exportLabel: l10n.onlineExportSource,
                  onExport: () => _exportAll(items),
                ),
                _sourceList(
                  items.map(
                    (source) => SourceListItemPadding(
                      child: _SourceRow(
                        source: source,
                        mobile: mobile,
                        onToggle: (enabled) => _toggle(source, enabled),
                        onDetail: () => _showDetail(source),
                        onAction: (action) => _handleAction(action, source),
                      ),
                    ),
                  ),
                ),
              ],
              SourceDisclaimerBar(text: l10n.onlineSourceDisclaimerShort),
            ],
          ),
        ),
      ],
    );
  }

  /// 已装源列表：设置页直铺（随页面滚动）；弹窗里超过
  /// [OnlineSourcePanel.maxVisibleSources] 条时，列表区自身滚动。
  ///
  /// 🔴 移动端不做内层滚动：弹窗在窄屏降级为 [AppSheet] 底部抽屉，它已经用
  /// `Flexible + SingleChildScrollView` 包住整个内容区。再套一层固定高度的滚动区
  /// 会造成双滚动与手势争夺。限制高度只在桌面生效。
  Widget _sourceList(Iterable<Widget> children) {
    final items = children.toList();
    final limit = widget.maxVisibleSources;
    final column = Column(mainAxisSize: MainAxisSize.min, children: items);
    if (limit == null || items.length <= limit) return column;
    if (context.isMobile) return column;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: kSourceRowExtent * limit),
      child: SingleChildScrollView(child: column),
    );
  }

  Widget _dragWrapper(Widget child) {
    if (kIsWeb || context.isMobile || !_isDesktopHost) return child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        _importDropped(details.files);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _dragging ? AppPalette.of(context).acc : Colors.transparent),
        ),
        child: child,
      ),
    );
  }

  bool get _isDesktopHost => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.mobile,
    required this.onToggle,
    required this.onDetail,
    required this.onAction,
  });

  final OnlineSource source;
  final bool mobile;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDetail;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final subtitle = source.isAbnormal
        ? l10n.onlineSourceSummaryAbnormal(source.version, source.capabilities.length)
        : l10n.onlineSourceSummary(source.version, source.capabilities.length);
    final actions = [
      AppDropdownItem(value: 'detail', label: l10n.onlineSourceDetail, icon: LucideIcons.info),
      AppDropdownItem(value: 'language', label: l10n.onlineSourceLanguageEdit, icon: LucideIcons.languages),
      AppDropdownItem(value: 'copy', label: l10n.onlineCopyId, icon: LucideIcons.copy),
      AppDropdownItem(value: 'export', label: l10n.onlineExportSource, icon: LucideIcons.externalLink),
      AppDropdownItem(value: 'reimport', label: l10n.onlineOverwrite, icon: LucideIcons.refreshCw),
      const AppDropdownItem.divider(),
      AppDropdownItem(value: 'delete', label: l10n.onlineDeleteSource, icon: LucideIcons.trash2, danger: true),
    ];
    return SourceCardShell(
      mobile: mobile,
      child: Row(
        children: [
          OnlineSourceLogo(glyph: source.glyph, size: mobile ? 32 : 38, radius: 9, tone: 0),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: mobile ? AppFont.px11_5 : AppFont.px12_5,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                    ),
                    if (source.isAbnormal) ...[
                      const SizedBox(width: 6),
                      OnlineTag(l10n.onlineSourceAbnormal, tone: OnlineTagTone.bad),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                ),
                if (!mobile)
                  Text(
                    source.host,
                    style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          AppSwitch(value: source.enabled, onChanged: (value) => onToggle(value)),
          AppDropdownMenu(
            items: actions,
            onSelected: onAction,
            child: AppButton(
              icon: LucideIcons.moreHorizontal,
              onTap: null,
              variant: AppButtonVariant.ghost,
              border: false,
              width: mobile ? 44 : 34,
              height: mobile ? 44 : 34,
              horizontalPadding: 0,
              fontSize: AppFont.px15,
              color: palette.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

String _sourceLanguageLabel(AppLocalizations l10n, String? language) => switch (language) {
  'zh' => l10n.onlineSourceLanguageZh,
  'ja' => l10n.onlineSourceLanguageJa,
  'en' => l10n.onlineSourceLanguageEn,
  _ => l10n.onlineSourceLanguageUnset,
};

class _SourceDetail extends StatelessWidget {
  const _SourceDetail({required this.source});

  final OnlineSource source;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manifest = source.manifest;
    final rows = <(String, String)>[
      (l10n.onlineFieldSpecVersion, '${manifest.specVersion}'),
      (l10n.onlineFieldId, manifest.id),
      (l10n.onlineFieldVersion, manifest.version),
      (l10n.onlineFieldLang, _sourceLanguageLabel(l10n, source.sourceLanguage)),
      (l10n.onlineFieldBaseUrl, manifest.baseUrl),
      (l10n.onlineFieldEntryClass, manifest.entryClass),
      (l10n.onlineFieldSourceFile, manifest.sourceFile),
      (l10n.onlineFieldHosts, manifest.hosts.join(', ')),
      (l10n.onlineFieldTimeout, l10n.onlineUnitMs(manifest.timeoutMs)),
      (l10n.onlineFieldRate, l10n.onlineUnitConcurrency(manifest.rateLimitIntervalMs, manifest.rateLimitConcurrency)),
      (l10n.onlineFieldHeaders, '${manifest.headers.length}'),
      (l10n.onlineFieldCaps, source.capabilities.join(', ')),
      if (source.sourceUrl != null) (l10n.onlineSourceSourceUrl, source.sourceUrl!),
      if (source.libraryId != null) (l10n.onlineSourceLibraryTitle, source.libraryId!),
    ];
    return SizedBox(
      width: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (manifest.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                manifest.description,
                style: TextStyle(fontSize: AppFont.px11_5, height: 1.7, color: AppPalette.of(context).ink2),
              ),
            ),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      label,
                      style: TextStyle(fontSize: AppFont.px10_5, color: AppPalette.of(context).mut),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      value,
                      style: TextStyle(fontSize: AppFont.px11, height: 1.5, color: AppPalette.of(context).ink2),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _IssueList extends StatelessWidget {
  const _IssueList({required this.issues, required this.error});

  final List<SourceIssue> issues;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          error ? l10n.onlineImportErrorsCount(issues.length) : l10n.onlineImportWarningsCount(issues.length),
          style: TextStyle(
            fontSize: AppFont.px11,
            fontWeight: FontWeight.w600,
            color: error ? palette.bad : palette.warn,
          ),
        ),
        const SizedBox(height: 6),
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  error ? LucideIcons.circleX : LucideIcons.alertTriangle,
                  size: 13,
                  color: error ? palette.bad : palette.warn,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    sourceIssueText(l10n, issue),
                    style: TextStyle(fontSize: AppFont.px11, height: 1.5, color: palette.ink2),
                  ),
                ),
              ],
            ),
          ),
        if (!error && issues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l10n.onlineImportWarnDetail,
              style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
            ),
          ),
      ],
    );
  }
}

/// 导入问题 → ARB。
String sourceIssueText(AppLocalizations l10n, SourceIssue issue) => switch (issue.code) {
  'invalidJson' || 'json' => l10n.onlineImportIssueJson,
  'field' => l10n.onlineImportIssueField(issue.detail),
  'path' => l10n.onlineImportIssuePath,
  'sourceMissing' => l10n.onlineImportIssueSourceMissing,
  'entryClass' => l10n.onlineImportIssueEntry(issue.detail),
  'tooLarge' => l10n.onlineImportIssueTooLarge,
  'fileSize' => l10n.onlineImportIssueFileSize(int.tryParse(issue.detail) ?? 0),
  'capabilityMissing' => l10n.onlineImportIssueCapability(issue.detail),
  'capabilityOptional' => l10n.onlineImportIssueOptional(issue.detail),
  'iconMissing' => l10n.onlineImportIssueIconMissing,
  'persistFailed' => l10n.onlineImportIssuePersist,
  _ => issue.code,
};

/// 源管理区块标题（设置页使用）。
class OnlineSourceSectionHeader extends StatelessWidget {
  const OnlineSourceSectionHeader({super.key, required this.title, this.blurb});

  final String title;
  final String? blurb;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: AppFont.px17, fontWeight: FontWeight.w700, color: palette.ink),
          ),
          if (blurb != null) ...[
            const SizedBox(height: 5),
            Text(
              blurb!,
              style: TextStyle(fontSize: AppFont.px11, height: 1.7, color: palette.mut),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceLanguageDialog extends ConsumerStatefulWidget {
  const _SourceLanguageDialog({required this.source});

  final OnlineSource source;

  @override
  ConsumerState<_SourceLanguageDialog> createState() => _SourceLanguageDialogState();
}

class _SourceLanguageDialogState extends ConsumerState<_SourceLanguageDialog> {
  late String _selected = widget.source.sourceLanguage ?? 'zh';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <String, String>{
      'zh': l10n.onlineSourceLanguageZh,
      'ja': l10n.onlineSourceLanguageJa,
      'en': l10n.onlineSourceLanguageEn,
    };
    return AppDialog(
      title: l10n.onlineSourceLanguageTitle(widget.source.name),
      icon: LucideIcons.languages,
      width: 420,
      onClose: () => Navigator.of(context).pop(),
      actions: [
        AppButton(
          label: l10n.onlineCancel,
          onTap: () => Navigator.of(context).pop(),
          variant: AppButtonVariant.secondary,
          height: 32,
        ),
        AppButton(
          label: l10n.onlineSave,
          onTap: () {
            ref.read(onlineSourcesProvider.notifier).setLanguage(widget.source.id, _selected);
            showAppToast(context, l10n.onlineSourceLanguageSaved, tone: ToastTone.good);
            Navigator.of(context).pop();
          },
          variant: AppButtonVariant.primary,
          height: 32,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.onlineSourceLanguageHint,
            style: TextStyle(fontSize: AppFont.px11, height: 1.7, color: AppPalette.of(context).ink2),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in options.entries)
                AppButton(
                  label: entry.value,
                  onTap: () => setState(() => _selected = entry.key),
                  variant: _selected == entry.key ? AppButtonVariant.primary : AppButtonVariant.ghost,
                  height: 34,
                  horizontalPadding: 16,
                  fontSize: AppFont.px12,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.source.sourceLanguage == null
                ? l10n.onlineSourceLanguageNoTranslation
                : _sourceLanguageLabel(l10n, widget.source.sourceLanguage),
            style: TextStyle(fontSize: AppFont.px10_5, color: AppPalette.of(context).mut),
          ),
        ],
      ),
    );
  }
}
