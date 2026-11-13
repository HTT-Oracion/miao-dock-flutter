import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/storage/shell_prefs.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/app_dropdown.dart';
import '../../../../shared/widgets/app_input.dart';
import '../../../../shared/widgets/app_switch.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_providers.dart';
import '../../data/sources/js/music_source_import.dart';
import '../../data/sources/js/music_source_remote.dart';
import '../../domain/js_music_source.dart';
import '../../domain/music_source_manifest.dart';

/// 音乐源管理弹窗（账号菜单 / 登录引导入口）。
class MusicSourceManagerModal extends ConsumerStatefulWidget {
  const MusicSourceManagerModal({super.key});

  static Future<void> open(BuildContext context) =>
      showAppDialog<void>(context: context, builder: (_) => const MusicSourceManagerModal());

  @override
  ConsumerState<MusicSourceManagerModal> createState() => _MusicSourceManagerModalState();
}

class _MusicSourceManagerModalState extends ConsumerState<MusicSourceManagerModal> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppDialog(
      title: l10n.musicSourceMgrTitle,
      onClose: () => Navigator.of(context).maybePop(),
      child: const SizedBox(width: 480, child: MusicSourcePanel()),
    );
  }
}

/// 音乐源管理面板：与漫画源面板同结构（导入盒 / 已装卡片 / 详情 / 卸载确认），
/// 弹窗与设置页「数据源 › 音乐源」共用。
class MusicSourcePanel extends ConsumerStatefulWidget {
  const MusicSourcePanel({super.key});

  @override
  ConsumerState<MusicSourcePanel> createState() => _MusicSourcePanelState();
}

class _MusicSourcePanelState extends ConsumerState<MusicSourcePanel> {
  final _urlCtrl = TextEditingController();
  bool _busy = false;
  bool _dragging = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final mobile = context.isMobile;
    final installed = ref.watch(jsMusicSourceRegistryProvider);
    return _dragWrapper(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 远程链接导入（与漫画 OnlineLinkImport 同位）。
          Row(
            children: [
              Expanded(
                child: AppInput(hint: l10n.musicSourceMgrUrlHint, controller: _urlCtrl, enabled: !_busy),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: l10n.musicSourceMgrImport,
                variant: AppButtonVariant.primary,
                height: 36,
                loading: _busy,
                clickable: !_busy,
                onTap: _importUrl,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 本地导入盒：虚线拖拽框（与漫画 _ImportBox 同视觉）。
          _ImportBox(importing: _busy, mobile: mobile, onPickFile: _pickAndImport, onOpenDir: _openSourceDirectory),
          const SizedBox(height: 16),
          Text(
            l10n.musicSourceMgrInstalled(installed.length),
            style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.ink),
          ),
          const SizedBox(height: 8),
          if (installed.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l10n.musicSourcePanelEmptyHint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppFont.px11, height: 1.7, color: palette.mut),
              ),
            )
          else
            for (final source in installed)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _SourceCard(
                  key: ValueKey('${source.id}:${source.manifest.version}'),
                  source: source,
                  onToggle: (enabled) => _toggle(source, enabled),
                  onDetail: () => _showDetail(source),
                  onDelete: () => _delete(source),
                  onCopyId: () => _copyId(source),
                ),
              ),
        ],
      ),
    );
  }

  // ── 导入（远程 URL）──────────────────────────────────────────────────────

  Future<void> _importUrl() async {
    final l10n = AppLocalizations.of(context);
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() => _busy = true);
    try {
      final loader = MusicSourceRemoteLoader();
      final payload = await loader.inspect(url);
      switch (payload) {
        case MusicSourceScriptPayload():
          await _installScript(payload.js, fileName: payload.url.split('/').last);
        case MusicSourceCatalogPayload():
          final catalog = payload.catalog;
          // 目录导入：逐条抓 JS 装包；单条失败不影响其余。
          var ok = 0;
          for (final entry in catalog.entries) {
            try {
              final js = await loader.fetchText(entry.fileUrl);
              final accepted = await _installScript(
                js,
                fileName: Uri.parse(entry.fileUrl).pathSegments.last,
                catalogKey: entry.key,
                catalogName: entry.name,
                catalogVersion: entry.version,
                silent: true,
              );
              if (accepted) ok += 1;
            } catch (_) {
              // 单条失败继续导入其余。
            }
          }
          if (mounted) {
            showAppToast(context, l10n.musicSourceMgrCatalog(catalog.name, ok), tone: ToastTone.good);
          }
      }
      ref.read(jsMusicSourceRegistryProvider.notifier).refresh();
      _urlCtrl.clear();
    } on MusicSourceRemoteException catch (e) {
      if (mounted) showAppToast(context, _remoteError(l10n, e.code), tone: ToastTone.bad);
    } on Object catch (e) {
      debugPrint('[music.source.mgr] import failed: $e');
      if (mounted) showAppToast(context, l10n.musicSourceMgrErrNetwork, tone: ToastTone.bad);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 导入（本地）──────────────────────────────────────────────────────────

  /// 桌面拖拽包装（与漫画源同款：拖进来高亮，松手导入）。
  Widget _dragWrapper(Widget child) {
    if (kIsWeb || context.isMobile) return child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        _importLocalPaths([for (final f in details.files) f.path]);
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

  Future<void> _pickAndImport() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'source', extensions: ['json', 'js']),
        ],
      );
      if (file == null) return;
      setState(() => _busy = true);
      await _importLocalPaths([file.path]);
    } on Object catch (e) {
      debugPrint('[music.source.mgr] pick file failed: $e');
      if (mounted) {
        showAppToast(context, AppLocalizations.of(context).musicSourceMgrErrNetwork, tone: ToastTone.bad);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importLocalPaths(List<String> paths) async {
    final l10n = AppLocalizations.of(context);
    var ok = 0;
    var handled = false;
    for (final path in paths) {
      try {
        if (await Directory(path).exists()) {
          // 拖进来的是目录：扫描其中全部 .js。
          handled = true;
          for (final f in Directory(path).listSync().whereType<File>().where((f) => f.path.endsWith('.js'))) {
            final accepted = await _installScript(
              await f.readAsString(),
              fileName: f.uri.pathSegments.last,
              silent: true,
            );
            if (accepted) ok += 1;
          }
          continue;
        }
        if (path.endsWith('.js')) {
          handled = true;
          final accepted = await _installScript(
            await File(path).readAsString(),
            fileName: path.split('/').last,
            silent: true,
          );
          if (accepted) ok += 1;
          continue;
        }
        if (path.endsWith('.json')) {
          // 本地目录清单：index.json 与 JS 同目录，按 file:// 相对解析 fileName。
          final raw = await File(path).readAsString();
          final catalog = parseMusicSourceCatalog(raw, Uri.file(path).toString());
          handled = true;
          for (final entry in catalog.entries) {
            final entryPath = Uri.parse(entry.fileUrl).toFilePath();
            final accepted = await _installScript(
              await File(entryPath).readAsString(),
              fileName: entryPath.split('/').last,
              catalogKey: entry.key,
              catalogName: entry.name,
              catalogVersion: entry.version,
              silent: true,
            );
            if (accepted) ok += 1;
          }
        }
      } on MusicSourceIssue catch (e) {
        if (mounted) showAppToast(context, _issueError(l10n, e.code, e.detail), tone: ToastTone.bad);
      } on FormatException {
        if (mounted) showAppToast(context, l10n.musicSourceMgrErrInvalidJson, tone: ToastTone.bad);
      } on Object catch (e) {
        debugPrint('[music.source.mgr] local import failed: $e');
      }
    }
    if (ok > 0) {
      ref.read(jsMusicSourceRegistryProvider.notifier).refresh();
      if (mounted) showAppToast(context, l10n.musicSourceMgrImportOk('$ok'), tone: ToastTone.good);
    } else if (!handled && mounted) {
      showAppToast(context, l10n.musicSourceMgrErrUnsupported, tone: ToastTone.bad);
    }
  }

  /// 落盘（含覆盖确认）；返回是否实际导入。
  Future<bool> _installScript(
    String js, {
    required String fileName,
    String? catalogKey,
    String? catalogName,
    String? catalogVersion,
    bool silent = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    final importer = MusicSourceImporter();
    final (manifest, issues) = manifestFromScript(
      js,
      fileName,
      catalogKey: catalogKey,
      catalogName: catalogName,
      catalogVersion: catalogVersion,
    );
    if (!mounted) return false;
    if (manifest == null) {
      if (!silent) {
        final issue = issues.first;
        showAppToast(context, _issueError(l10n, issue, issue), tone: ToastTone.bad);
      }
      return false;
    }
    // 覆盖确认（与漫画源同交互）：同 id 已装 → 先问。
    final existing = ref.read(jsMusicSourceRegistryProvider).where((s) => s.id == manifest.id).toList();
    if (existing.isNotEmpty) {
      final confirmed = await _confirmOverwrite(manifest.name);
      if (!confirmed || !mounted) return false;
    }
    final result = await importer.importScript(
      js,
      fileName: fileName,
      catalogKey: catalogKey,
      catalogName: catalogName,
      catalogVersion: catalogVersion,
    );
    if (!mounted) return false;
    if (!result.ok) {
      if (!silent) {
        final issue = result.errors.first;
        showAppToast(context, _issueError(l10n, issue.code, issue.detail), tone: ToastTone.bad);
      }
      return false;
    }
    if (!silent) {
      showAppToast(context, l10n.musicSourceMgrImportOk(result.source!.name), tone: ToastTone.good);
    }
    return true;
  }

  Future<bool> _confirmOverwrite(String name) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.musicSourcePanelOverwriteTitle,
        icon: LucideIcons.alertTriangle,
        width: 420,
        actions: [
          AppButton(
            label: l10n.musicSourcePanelClose,
            onTap: () => Navigator.of(context).pop(false),
            variant: AppButtonVariant.secondary,
            height: 32,
          ),
          AppButton(
            label: l10n.musicSourcePanelOverwrite,
            onTap: () => Navigator.of(context).pop(true),
            variant: AppButtonVariant.primary,
            height: 32,
          ),
        ],
        child: Text(
          l10n.musicSourcePanelOverwriteBody(name),
          style: TextStyle(fontSize: AppFont.px12, height: 1.7, color: AppPalette.of(context).ink2),
        ),
      ),
    );
    return confirmed == true;
  }

  // ── 卡片动作 ─────────────────────────────────────────────────────────────

  Future<void> _toggle(JsMusicSource source, bool enabled) async {
    await MusicSourceImporter().setEnabled(source.id, enabled);
    ref.read(jsMusicSourceRegistryProvider.notifier).refresh();
  }

  void _copyId(JsMusicSource source) {
    Clipboard.setData(ClipboardData(text: source.id));
    showAppToast(context, AppLocalizations.of(context).musicSourcePanelCopyOk, tone: ToastTone.good);
  }

  Future<void> _delete(JsMusicSource source) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.musicSourcePanelDeleteTitle,
        icon: LucideIcons.trash2,
        width: 420,
        actions: [
          AppButton(
            label: l10n.musicSourcePanelClose,
            onTap: () => Navigator.of(context).pop(false),
            variant: AppButtonVariant.secondary,
            height: 32,
          ),
          AppButton(
            label: l10n.musicSourceMgrUninstall,
            onTap: () => Navigator.of(context).pop(true),
            variant: AppButtonVariant.danger,
            height: 32,
          ),
        ],
        child: Text(
          l10n.musicSourcePanelDeleteBody(source.name),
          style: TextStyle(fontSize: AppFont.px12, height: 1.7, color: AppPalette.of(context).ink2),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await MusicSourceImporter().uninstall(source.id);
    ref.read(jsMusicSourceRegistryProvider.notifier).refresh();
    if (mounted) {
      showAppToast(context, l10n.musicSourceMgrUninstallOk(source.name), tone: ToastTone.info);
    }
  }

  void _showDetail(JsMusicSource source) {
    final l10n = AppLocalizations.of(context);
    showAppDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.musicSourcePanelDetailTitle(source.name),
        icon: LucideIcons.info,
        width: 520,
        onClose: () => Navigator.of(context).pop(),
        actions: [
          AppButton(
            label: l10n.musicSourcePanelClose,
            onTap: () => Navigator.of(context).pop(),
            variant: AppButtonVariant.secondary,
            height: 32,
          ),
        ],
        child: _SourceDetail(source: source),
      ),
    );
  }

  void _openSourceDirectory() {
    final root = musicSourceStateDirectory();
    if (root == null || !root.existsSync()) return;
    final exe = switch (defaultTargetPlatform) {
      TargetPlatform.macOS => 'open',
      TargetPlatform.windows => 'explorer',
      _ => 'xdg-open',
    };
    Process.run(exe, [root.path]);
  }

  String _remoteError(AppLocalizations l10n, String code) => switch (code) {
    'invalidUrl' => l10n.musicSourceMgrErrInvalidUrl,
    'network' => l10n.musicSourceMgrErrNetwork,
    'invalidJson' => l10n.musicSourceMgrErrInvalidJson,
    'unsupported' => l10n.musicSourceMgrErrUnsupported,
    'tooLarge' => l10n.musicSourceMgrErrTooLarge,
    _ => l10n.musicSourceMgrErrNetwork,
  };

  String _issueError(AppLocalizations l10n, String code, String detail) => switch (code) {
    'entryClass' => l10n.musicSourceMgrErrEntry,
    'no_capability' => l10n.musicSourceMgrErrNoCapability,
    'js_too_large' => l10n.musicSourceMgrErrTooLarge,
    'platform' || 'key' || 'name' || 'baseUrl' || 'hosts' => l10n.musicSourceMgrErrField(code),
    _ => l10n.musicSourceMgrErrField(detail.isEmpty ? code : detail),
  };
}

/// 导入盒（与漫画 `_ImportBox` 同视觉：虚线框 + 上传图标 + 主/副按钮）。
class _ImportBox extends StatelessWidget {
  const _ImportBox({required this.importing, required this.mobile, required this.onPickFile, required this.onOpenDir});

  final bool importing;
  final bool mobile;
  final VoidCallback onPickFile;
  final VoidCallback onOpenDir;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return CustomPaint(
      painter: _ImportDashedPainter(color: palette.line2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
        decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Icon(LucideIcons.upload, size: 26, color: palette.acc),
            const SizedBox(height: 8),
            Text(
              l10n.musicSourcePanelImportTitle,
              style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.ink),
            ),
            const SizedBox(height: 4),
            Text(
              mobile
                  ? l10n.musicSourcePanelImportDesc
                  : '${l10n.musicSourcePanelImportDesc}\n${l10n.musicSourcePanelImportSteps}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppFont.px10_5, height: 1.6, color: palette.mut),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                AppButton(
                  label: l10n.musicSourcePanelSelectFile,
                  icon: LucideIcons.plus,
                  onTap: importing ? null : onPickFile,
                  variant: AppButtonVariant.primary,
                  loading: importing,
                  height: mobile ? 44 : 32,
                  horizontalPadding: 13,
                  fontSize: AppFont.px12,
                  fontWeight: FontWeight.w600,
                ),
                if (!mobile)
                  AppButton(
                    label: l10n.musicSourcePanelOpenDir,
                    icon: LucideIcons.folder,
                    onTap: onOpenDir,
                    variant: AppButtonVariant.ghost,
                    height: 32,
                    horizontalPadding: 13,
                    fontSize: AppFont.px12,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              importing ? l10n.musicSourcePanelImporting : l10n.musicSourcePanelWait,
              style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportDashedPainter extends CustomPainter {
  const _ImportDashedPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 4;
      }
    }
  }

  @override
  bool shouldRepaint(_ImportDashedPainter oldDelegate) => oldDelegate.color != color;
}

/// 已装源卡片（与漫画 `_SourceRow` 同布局：glyph 圆底 / 名称概要 / host / 开关 / 菜单）。
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    super.key,
    required this.source,
    required this.onToggle,
    required this.onDetail,
    required this.onDelete,
    required this.onCopyId,
  });

  final JsMusicSource source;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDetail;
  final VoidCallback onDelete;
  final VoidCallback onCopyId;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final mobile = context.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: mobile ? 12 : 14, vertical: mobile ? 10 : 12),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _GlyphBadge(source: source, size: mobile ? 32 : 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: mobile ? AppFont.px11_5 : AppFont.px12_5,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  l10n.musicSourcePanelSummary(source.manifest.version, source.capabilities.length),
                  style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                ),
                if (!mobile)
                  Text(
                    Uri.tryParse(source.manifest.baseUrl)?.host ?? '',
                    style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          AppSwitch(value: source.enabled, onChanged: onToggle),
          AppDropdownMenu(
            items: [
              AppDropdownItem(value: 'detail', label: l10n.musicSourcePanelDetail, icon: LucideIcons.info),
              AppDropdownItem(value: 'copy', label: l10n.musicSourcePanelCopyId, icon: LucideIcons.copy),
              const AppDropdownItem.divider(),
              AppDropdownItem(
                value: 'delete',
                label: l10n.musicSourcePanelDeleteMenu,
                icon: LucideIcons.trash2,
                danger: true,
              ),
            ],
            onSelected: (action) {
              switch (action) {
                case 'detail':
                  onDetail();
                case 'copy':
                  onCopyId();
                case 'delete':
                  onDelete();
              }
            },
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

/// glyph 圆底（名称首字派生；内置四平台无真实 logo——源是第三方身份，与漫画一致）。
class _GlyphBadge extends StatelessWidget {
  const _GlyphBadge({required this.source, required this.size});

  final JsMusicSource source;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final name = source.name.trim();
    final runes = name.runes.toList();
    String glyph = '?';
    if (runes.isNotEmpty) {
      final first = String.fromCharCode(runes.first);
      if (RegExp(r'[A-Za-z]').hasMatch(first)) {
        final latin = RegExp(r'[A-Za-z]').allMatches(name).map((m) => m.group(0)!).join();
        glyph = latin.length >= 2 ? latin.substring(0, 2).toUpperCase() : latin.toUpperCase();
      } else {
        glyph = first;
      }
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: palette.accSoft, borderRadius: BorderRadius.circular(9)),
      child: Text(
        glyph,
        style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: palette.accInk),
      ),
    );
  }
}

/// 源详情弹窗内容（与漫画 `_SourceDetail` 同布局：label 行 + 值）。
class _SourceDetail extends StatelessWidget {
  const _SourceDetail({required this.source});

  final JsMusicSource source;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manifest = source.manifest;
    final rows = <(String, String)>[
      (l10n.musicSourcePanelFieldId, manifest.id),
      (l10n.musicSourcePanelFieldPlatform, manifest.platform),
      (l10n.musicSourcePanelFieldVersion, manifest.version),
      (l10n.musicSourcePanelFieldEntry, manifest.entryClass),
      (l10n.musicSourcePanelFieldFile, manifest.sourceFile),
      (l10n.musicSourcePanelFieldHosts, manifest.hosts.join(', ')),
      (l10n.musicSourcePanelFieldCaps, source.capabilities.join(', ')),
    ];
    return SizedBox(
      width: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
