import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/theme/tokens.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/responsive.dart';
import '../../../../../shared/widgets/app_dialog.dart';
import '../../../../../shared/widgets/app_input.dart';
import '../../../../../shared/widgets/buttons.dart';
import '../../../../../shared/widgets/skeleton.dart';
import '../../../../../shared/widgets/toast.dart';
import '../../controller/online_library_controller.dart';
import '../../controller/online_sources_controller.dart';
import '../../data/source_import.dart';
import '../../data/source_remote.dart';
import '../../domain/online_source.dart';
import '../../domain/source_library.dart';
import 'online_common.dart';

/// 链接导入 + 用户源仓库（index.json）+ 仓库内源列表。
///
/// 文件导入仍走同级的源包导入框；这里负责「链接」入口，最终调用同一个
/// [SourceImporter.installPackage]，两条入口的校验与落盘一致。
class OnlineLinkImport extends ConsumerStatefulWidget {
  const OnlineLinkImport({super.key});

  @override
  ConsumerState<OnlineLinkImport> createState() => _OnlineLinkImportState();
}

class _OnlineLinkImportState extends ConsumerState<OnlineLinkImport> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _busyLibraryId;
  String? _error;

  SourceRemoteLoader get _loader => ref.read(sourceRemoteLoaderProvider);
  SourceImporter get _importer => ref.read(sourceImporterProvider);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final raw = _controller.text.trim();
    final l10n = AppLocalizations.of(context);
    if (!isValidSourceUrl(raw)) {
      setState(() => _error = l10n.onlineLinkInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = await _loader.inspect(raw);
      if (!mounted) return;
      switch (payload) {
        case SourceCatalogPayload():
          final library = SourceLibrary(id: stableSourceLibraryId(raw), name: payload.catalog.name, url: raw);
          ref.read(onlineLibrariesProvider.notifier).add(library);
          ref.read(onlineLibrariesProvider.notifier).markChecked(library.id);
          _controller.clear();
          setState(() => _busy = false);
          showAppToast(context, l10n.onlineSourceLibraryAdded(library.name), tone: ToastTone.good);
          await _openCatalog(library, payload.catalog);
        case SourceManifestPayload():
          final package = await _loader.loadManifest(raw);
          final result = await _importer.installPackage(package);
          if (!mounted) return;
          await _finishInstall(result);
          if (result.ok) _controller.clear();
        case SourceScriptPayload():
          final package = await _loader.loadScript(raw, payload.js);
          final result = await _importer.installPackage(package);
          if (!mounted) return;
          await _finishInstall(result);
          if (result.ok) _controller.clear();
      }
    } on SourceRemoteException catch (e) {
      if (!mounted) return;
      setState(() => _error = _remoteError(l10n, e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = l10n.onlineSourceRemoteNetwork);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _remoteError(AppLocalizations l10n, SourceRemoteException error) => switch (error.code) {
    'invalidUrl' => l10n.onlineLinkInvalid,
    'invalidJson' || 'unsupported' || 'emptyCatalog' => l10n.onlineSourceRemoteInvalid,
    'network' || 'http' => l10n.onlineSourceRemoteNetwork,
    _ => l10n.onlineSourceRemoteFailed,
  };

  Future<void> _finishInstall(SourceImportResult result) async {
    final l10n = AppLocalizations.of(context);
    if (!result.ok) {
      showAppToast(context, l10n.onlineImportRejectedTitle, tone: ToastTone.bad);
      await _showIssues(result);
      return;
    }
    final source = result.source!;
    final sources = ref.read(onlineSourcesProvider).value ?? const <OnlineSource>[];
    OnlineSource? existing;
    for (final item in sources) {
      if (item.id == source.id) existing = item;
    }
    if (existing != null) {
      final confirmed = await showAppDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: l10n.onlineConfirmOverwriteTitle,
          icon: LucideIcons.alertTriangle,
          width: 420,
          actions: [
            AppButton(
              label: l10n.onlineCancel,
              onTap: () => Navigator.of(dialogContext).pop(false),
              variant: AppButtonVariant.secondary,
              height: 32,
            ),
            AppButton(
              label: l10n.onlineOverwrite,
              onTap: () => Navigator.of(dialogContext).pop(true),
              variant: AppButtonVariant.primary,
              height: 32,
            ),
          ],
          child: Text(
            l10n.onlineConfirmOverwriteBody(source.name),
            style: TextStyle(fontSize: AppFont.px12, height: 1.7, color: AppPalette.of(dialogContext).ink2),
          ),
        ),
      );
      if (confirmed != true) return;
    }
    final keepsDisabled = existing != null && !existing.enabled;
    await ref
        .read(onlineSourcesProvider.notifier)
        .addOrReplace(keepsDisabled ? source.copyWith(enabled: false) : source);
    if (!mounted) return;
    showAppToast(context, l10n.onlineSourceInstallSuccess(source.name), tone: ToastTone.good);
  }

  Future<void> _showIssues(SourceImportResult result) async {
    final l10n = AppLocalizations.of(context);
    final text = [
      for (final issue in [...result.errors, ...result.warnings]) _issueText(l10n, issue),
    ].where((line) => line.isNotEmpty).join('\n');
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: l10n.onlineImportRejectedTitle,
        icon: LucideIcons.circleX,
        width: 460,
        onClose: () => Navigator.of(dialogContext).pop(),
        actions: [
          AppButton(
            label: l10n.onlineImportClose,
            onTap: () => Navigator.of(dialogContext).pop(),
            variant: AppButtonVariant.secondary,
            height: 32,
          ),
        ],
        child: Text(
          text,
          style: TextStyle(fontSize: AppFont.px11_5, height: 1.8, color: AppPalette.of(dialogContext).ink2),
        ),
      ),
    );
  }

  String _issueText(AppLocalizations l10n, SourceIssue issue) => switch (issue.code) {
    'invalidJson' || 'json' => l10n.onlineImportIssueJson,
    'field' => l10n.onlineImportIssueField(issue.detail),
    'path' => l10n.onlineImportIssuePath,
    'sourceMissing' => l10n.onlineImportIssueSourceMissing,
    'entryClass' => l10n.onlineImportIssueEntry(issue.detail),
    'tooLarge' => l10n.onlineImportIssueTooLarge,
    'fileSize' || 'iconTooLarge' => l10n.onlineImportIssueFileSize(int.tryParse(issue.detail) ?? 0),
    'capabilityMissing' => l10n.onlineImportIssueCapability(issue.detail),
    'capabilityOptional' => l10n.onlineImportIssueOptional(issue.detail),
    'iconMissing' => l10n.onlineImportIssueIconMissing,
    'persistFailed' => l10n.onlineImportIssuePersist,
    _ => issue.code,
  };

  Future<void> _openCatalog(SourceLibrary library, SourceCatalog catalog) async {
    if (!mounted) return;
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _SourceCatalogDialog(library: library, catalog: catalog, onInstall: (entry) => _installEntry(library, entry)),
    );
  }

  Future<bool> _installEntry(SourceLibrary library, SourceCatalogEntry entry) async {
    try {
      final package = await _loader.loadEntry(entry, libraryId: library.id);
      final result = await _importer.installPackage(package);
      if (!mounted) return false;
      await _finishInstall(result);
      return result.ok;
    } on SourceRemoteException catch (e) {
      if (!mounted) return false;
      showAppToast(context, _remoteError(AppLocalizations.of(context), e), tone: ToastTone.bad);
      return false;
    } catch (_) {
      if (!mounted) return false;
      showAppToast(context, AppLocalizations.of(context).onlineSourceRemoteNetwork, tone: ToastTone.bad);
      return false;
    }
  }

  Future<void> _browseLibrary(SourceLibrary library) async {
    setState(() => _busyLibraryId = library.id);
    try {
      final catalog = await _loader.loadCatalog(library.url);
      if (!mounted) return;
      ref.read(onlineLibrariesProvider.notifier).markChecked(library.id);
      await _openCatalog(library, catalog);
    } on SourceRemoteException catch (e) {
      if (!mounted) return;
      showAppToast(context, _remoteError(AppLocalizations.of(context), e), tone: ToastTone.bad);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, AppLocalizations.of(context).onlineSourceLibraryLoadFailed, tone: ToastTone.bad);
    } finally {
      if (mounted) setState(() => _busyLibraryId = null);
    }
  }

  Future<void> _deleteLibrary(SourceLibrary library) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: l10n.onlineSourceLibraryDelete,
        icon: LucideIcons.trash2,
        width: 420,
        actions: [
          AppButton(
            label: l10n.onlineCancel,
            onTap: () => Navigator.of(dialogContext).pop(false),
            variant: AppButtonVariant.secondary,
            height: 32,
          ),
          AppButton(
            label: l10n.onlineDelete,
            onTap: () => Navigator.of(dialogContext).pop(true),
            variant: AppButtonVariant.danger,
            height: 32,
          ),
        ],
        child: Text(
          l10n.onlineSourceLibraryDeleteBody,
          style: TextStyle(fontSize: AppFont.px12, height: 1.7, color: AppPalette.of(dialogContext).ink2),
        ),
      ),
    );
    if (confirmed != true) return;
    await ref.read(onlineLibrariesProvider.notifier).remove(library.id);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final libraries = ref.watch(onlineLibrariesProvider);
    final mobile = context.isMobile;
    return Container(
      padding: EdgeInsets.all(mobile ? 12 : 14),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.link, size: 15, color: palette.acc),
              const SizedBox(width: 7),
              Text(
                l10n.onlineLinkImportTitle,
                style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.ink),
              ),
              const Spacer(),
              Text(
                l10n.onlineSourcesLibraryTitle,
                style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.onlineSourceLibraryDesc,
            style: TextStyle(fontSize: AppFont.px10_5, height: 1.6, color: palette.mut),
          ),
          const SizedBox(height: 9),
          if (mobile) ...[
            AppInput(
              controller: _controller,
              hint: l10n.onlineLinkImportHint,
              onSubmitted: (_) => _import(),
              height: 44,
              prefixIcon: LucideIcons.link2,
              errorText: _error,
            ),
            const SizedBox(height: 8),
            AppButton(
              label: _busy ? l10n.onlineLinkImporting : l10n.onlineLinkImportAction,
              icon: LucideIcons.download,
              onTap: _busy ? null : _import,
              variant: AppButtonVariant.primary,
              loading: _busy,
              width: double.infinity,
              height: 44,
              fontSize: AppFont.px12,
              fontWeight: FontWeight.w600,
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppInput(
                    controller: _controller,
                    hint: l10n.onlineLinkImportHint,
                    onSubmitted: (_) => _import(),
                    height: 34,
                    prefixIcon: LucideIcons.link2,
                    errorText: _error,
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: _busy ? l10n.onlineLinkImporting : l10n.onlineLinkImportAction,
                  icon: LucideIcons.download,
                  onTap: _busy ? null : _import,
                  variant: AppButtonVariant.primary,
                  loading: _busy,
                  height: 34,
                  horizontalPadding: 12,
                  fontSize: AppFont.px11,
                  fontWeight: FontWeight.w600,
                ),
              ],
            ),
          const SizedBox(height: 12),
          libraries.when(
            skipLoadingOnRefresh: true,
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 180, height: 10)),
            ),
            error: (_, _) => Text(
              l10n.onlineSourceLibraryLoadFailed,
              style: TextStyle(fontSize: AppFont.px10_5, color: palette.bad),
            ),
            data: (items) => items.isEmpty
                ? Text(
                    l10n.onlineSourceLibraryEmpty,
                    style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                  )
                : Column(
                    children: [
                      for (final library in items)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _LibraryRow(
                            library: library,
                            busy: _busyLibraryId == library.id,
                            onBrowse: () => _browseLibrary(library),
                            onDelete: () => _deleteLibrary(library),
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

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({required this.library, required this.busy, required this.onBrowse, required this.onDelete});

  final SourceLibrary library;
  final bool busy;
  final VoidCallback onBrowse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final host = Uri.tryParse(library.url)?.host ?? library.url;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: palette.navBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.line2),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.library, size: 16, color: palette.acc),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: busy ? null : onBrowse,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    library.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px11_5, fontWeight: FontWeight.w600, color: palette.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                  ),
                ],
              ),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
            )
          else
            AppButton(
              icon: LucideIcons.refreshCw,
              onTap: onBrowse,
              variant: AppButtonVariant.ghost,
              width: 30,
              height: 30,
              horizontalPadding: 0,
            ),
          AppButton(
            icon: LucideIcons.trash2,
            onTap: onDelete,
            variant: AppButtonVariant.ghost,
            width: 30,
            height: 30,
            horizontalPadding: 0,
          ),
        ],
      ),
    );
  }
}

class _SourceCatalogDialog extends ConsumerStatefulWidget {
  const _SourceCatalogDialog({required this.library, required this.catalog, required this.onInstall});

  final SourceLibrary library;
  final SourceCatalog catalog;
  final Future<bool> Function(SourceCatalogEntry entry) onInstall;

  @override
  ConsumerState<_SourceCatalogDialog> createState() => _SourceCatalogDialogState();
}

class _SourceCatalogDialogState extends ConsumerState<_SourceCatalogDialog> {
  String? _busyKey;

  Future<void> _install(SourceCatalogEntry entry) async {
    setState(() => _busyKey = entry.key);
    try {
      await widget.onInstall(entry);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final sources = ref.watch(onlineSourcesProvider).value ?? const <OnlineSource>[];
    return AppDialog(
      title: widget.library.name,
      subtitle: l10n.onlineSourceCatalogSourceCount(widget.catalog.entries.length),
      icon: LucideIcons.library,
      width: 560,
      onClose: () => Navigator.of(context).pop(),
      actions: [
        AppButton(
          label: l10n.onlineClose,
          onTap: () => Navigator.of(context).pop(),
          variant: AppButtonVariant.secondary,
          height: 32,
        ),
      ],
      child: SizedBox(
        width: double.infinity,
        height: widget.catalog.entries.isEmpty ? 140 : 320,
        child: widget.catalog.entries.isEmpty
            ? Center(
                child: Text(
                  l10n.onlineSourceCatalogEmpty,
                  style: TextStyle(fontSize: AppFont.px12, color: palette.mut),
                ),
              )
            : ListView.separated(
                itemCount: widget.catalog.entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = widget.catalog.entries[index];
                  OnlineSource? installed;
                  for (final source in sources) {
                    if (source.id == entry.key) installed = source;
                  }
                  final busy = _busyKey == entry.key;
                  final needsUpdate = installed != null && installed.version != entry.version;
                  return Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: palette.navBg,
                      border: Border.all(color: palette.line2),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      entry.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: AppFont.px12,
                                        fontWeight: FontWeight.w600,
                                        color: palette.ink,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  OnlineTag('v${entry.version}'),
                                  if (needsUpdate) ...[
                                    const SizedBox(width: 5),
                                    OnlineTag(l10n.onlineSourceCatalogUpdate(entry.version), tone: OnlineTagTone.warn),
                                  ],
                                ],
                              ),
                              if (entry.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  entry.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: AppFont.px10_5, height: 1.5, color: palette.mut),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (installed != null && !needsUpdate)
                          OnlineTag(l10n.onlineSourceCatalogInstalled, tone: OnlineTagTone.good)
                        else
                          AppButton(
                            label: needsUpdate
                                ? l10n.onlineSourceCatalogUpdate(entry.version)
                                : l10n.onlineSourceCatalogInstall,
                            onTap: busy ? null : () => _install(entry),
                            variant: AppButtonVariant.primary,
                            loading: busy,
                            height: context.isMobile ? 44 : 30,
                            horizontalPadding: 10,
                            fontSize: AppFont.px10_5,
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
