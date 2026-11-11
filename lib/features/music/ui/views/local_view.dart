import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_providers.dart';
import '../../controller/music_player.dart';
import '../../domain/music_models.dart';
import '../widgets/fail_magic.dart';
import '../widgets/music_scroll_memory.dart';
import '../widgets/music_empty_state.dart';
import '../widgets/song_row.dart';

/// 本地音乐（N25/N30）：工具条（选择文件 / 选择文件夹 / 清空）+ 拖放区 + 曲目列表。
///
/// 导入：file_selector 拿文件名 → musicLocalProvider.importNames → 成功吐司；
/// 清空：clearKeepSnapshot → 吐司 + 顶部撤销条 6 秒（撤销调 restore）。
class LocalView extends ConsumerStatefulWidget {
  const LocalView({super.key});

  @override
  ConsumerState<LocalView> createState() => _LocalViewState();
}

class _LocalViewState extends ConsumerState<LocalView> {
  bool _dragOver = false;
  bool _importing = false;
  List<MusicSong>? _undoSnapshot;
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  /// 文件名兜底提取（file_selector 给绝对路径；不引 path 包，手切分隔符）。
  static String _basename(String path) {
    final s = path.replaceAll('\\', '/');
    return s.substring(s.lastIndexOf('/') + 1);
  }

  Future<void> _import({required bool folder}) async {
    if (_importing) return;
    setState(() => _importing = true);
    final l10n = AppLocalizations.of(context);
    try {
      final names = <String>[];
      if (folder) {
        final dir = await getDirectoryPath();
        if (dir != null) names.add(_basename(dir));
      } else {
        final files = await openFiles();
        for (final f in files) {
          names.add(_basename(f.path));
        }
      }
      if (!mounted || names.isEmpty) return;
      await ref.read(musicLocalProvider.notifier).importNames(names);
      if (!mounted) return;
      showAppToast(context, AppLocalizations.of(context).musicImportDone(names.length), tone: ToastTone.good);
    } on Object {
      if (mounted) showAppToast(context, l10n.musicImportFail, tone: ToastTone.bad);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _clear() async {
    final snapshot = await ref.read(musicLocalProvider.notifier).clearKeepSnapshot();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    _undoTimer?.cancel();
    setState(() => _undoSnapshot = snapshot);
    _undoTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _undoSnapshot = null);
    });
    showAppToast(context, l10n.musicLocalCleared, tone: ToastTone.info);
  }

  void _restore() {
    final snapshot = _undoSnapshot;
    if (snapshot == null) return;
    _undoTimer?.cancel();
    ref.read(musicLocalProvider.notifier).restore(snapshot);
    setState(() => _undoSnapshot = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final local = ref.watch(musicLocalProvider);
    final player = ref.watch(playerProvider);

    final songs = local.value ?? const <MusicSong>[];
    final hasList = songs.isNotEmpty;

    final mobile = context.isMobile;
    // 设计稿：移动端工具条只留标题 + 计数；空态的两个导入按钮放在空态图下方
    // （整宽按钮，拇指可达），不在工具条里再重复一遍。
    final toolbar = Row(
      children: [
        Text(
          l10n.viewLocal,
          style: TextStyle(
            fontSize: mobile ? AppFont.px15 : AppFont.px15,
            fontWeight: FontWeight.w700,
            color: palette.ink,
          ),
        ),
        SizedBox(width: mobile ? 8 : 10),
        Text(
          l10n.musicCountSongs(songs.length),
          style: TextStyle(fontSize: mobile ? AppFont.px11 : AppFont.px11, color: palette.mut),
        ),
        const Spacer(),
        if (!mobile || hasList) ...[
          AppButton(
            label: l10n.musicImportFolder,
            icon: LucideIcons.folderPlus,
            variant: AppButtonVariant.ghost,
            height: 26,
            fontSize: AppFont.px11_5,
            clickable: !_importing,
            onTap: () => _import(folder: true),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: _importing ? l10n.musicImporting : l10n.musicImportFiles,
            icon: _importing ? LucideIcons.loader : LucideIcons.filePlus,
            variant: AppButtonVariant.primary,
            height: 26,
            fontSize: AppFont.px11_5,
            clickable: !_importing,
            onTap: () => _import(folder: false),
          ),
          if (hasList) ...[
            const SizedBox(width: 8),
            AppButton(
              label: l10n.musicLocalClear,
              icon: LucideIcons.trash2,
              variant: AppButtonVariant.ghost,
              height: 26,
              fontSize: AppFont.px11_5,
              color: palette.bad,
              onTap: _clear,
            ),
          ],
        ],
      ],
    );

    final Widget body;
    if (local.hasError && local.value == null) {
      // N28：首次加载失败 → 魔法阵。
      body = Center(
        child: FailMagicCircle(
          reason: l10n.musicFailReasonNetwork,
          lastSyncLabel: l10n.musicFailLastSync(_hhmm()),
          queueHint: l10n.musicFailQueueHint(player.queue.length),
          retryLabel: l10n.musicRetry,
          onRetry: () => ref.invalidate(musicLocalProvider),
        ),
      );
    } else if (!hasList && !local.isLoading) {
      // N30：空态（与失败分开画）。移动端用「单环 + 音符轨道」空态图 + 整宽按钮
      // （设计稿 `.m-state`），桌面端空态即拖放区（虚线框 + 两个选择按钮）。
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toolbar,
          SizedBox(height: mobile ? 0 : 14),
          Expanded(
            child: mobile
                ? MusicEmptyState(
                    title: l10n.musicEmptyLocalTitle,
                    description: l10n.musicEmptyLocalDesc,
                    meta: l10n.musicEmptyLocalFormats,
                    actionLabel: l10n.musicImportFiles,
                    onAction: () => _import(folder: false),
                    secondaryActionLabel: l10n.musicImportFolder,
                    onSecondaryAction: () => _import(folder: true),
                    mobileStacked: true,
                  )
                : Center(
                    child: SizedBox(
                      height: 268,
                      child: _DropZone(
                        over: _dragOver,
                        onOver: (v) => setState(() => _dragOver = v),
                        onDrop: (names) => _importNames(names),
                        compact: false,
                        onImportFile: () => _import(folder: false),
                        onImportFolder: () => _import(folder: true),
                      ),
                    ),
                  ),
          ),
        ],
      );
    } else if (local.isLoading) {
      // N27：骨架按真实布局占位（复用共享 SkeletonBox）。
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toolbar,
          const SizedBox(height: 12),
          for (var i = 0; i < 6; i++)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10), child: _SkeletonRowLine()),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toolbar,
          const SizedBox(height: 12),
          _DropZone(
            over: _dragOver,
            onOver: (v) => setState(() => _dragOver = v),
            onDrop: (names) => _importNames(names),
            compact: true,
          ),
          const SizedBox(height: 6),
          Expanded(
            // N03：切视图后回来恢复滚动位置。
            child: MusicScrollMemory(
              storageKey: 'local',
              builder: (context, controller) => ListView(
                controller: controller,
                padding: EdgeInsets.zero,
                children: [
                  for (final (i, s) in songs.indexed)
                    SongRow(
                      song: s,
                      index: i,
                      current: player.current?.id == s.id,
                      liked: player.likedIds.contains(s.id),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_undoSnapshot != null) ...[
          _UndoBar(text: l10n.musicLocalCleared, undoLabel: l10n.musicUndo, onUndo: _restore),
          const SizedBox(height: 10),
        ],
        Expanded(child: body),
      ],
    );
  }

  Future<void> _importNames(List<String> names) async {
    if (names.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(musicLocalProvider.notifier).importNames(names);
      if (mounted) {
        showAppToast(context, AppLocalizations.of(context).musicImportDone(names.length), tone: ToastTone.good);
      }
    } on Object {
      if (mounted) showAppToast(context, l10n.musicImportFail, tone: ToastTone.bad);
    }
  }

  static String _hhmm() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

/// 拖放导入（N25）：拖入虚线框变实线橙框 + 浅橙底。
class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.over,
    required this.onOver,
    required this.onDrop,
    required this.compact,
    this.onImportFile,
    this.onImportFolder,
  });

  final bool over;
  final ValueChanged<bool> onOver;
  final ValueChanged<List<String>> onDrop;

  /// true = 列表非空时的紧凑条；false = 空态大拖放区。
  final bool compact;
  final VoidCallback? onImportFile;
  final VoidCallback? onImportFolder;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(compact ? AppMetrics.radiusCardLg : 14);
    return DropTarget(
      onDragEntered: (_) => onOver(true),
      onDragExited: (_) => onOver(false),
      onDragDone: (details) {
        onOver(false);
        onDrop([for (final f in details.files) f.name]);
      },
      child: CustomPaint(
        // 拖入：虚线 → 实线橙框（设计稿 `.dropzone.over`）。Flutter 没有虚线 Border，
        // 用 painter 画在内容之上，保证空态 / 紧凑条共用同一套描边。
        foregroundPainter: _DashedBorderPainter(
          color: over ? palette.acc : palette.line2,
          radius: compact ? AppMetrics.radiusCardLg : 14,
          dashed: !over,
          strokeWidth: 1.5,
        ),
        child: AnimatedContainer(
          duration: AppMotion.hover,
          // 空态 = 虚线拖放区（设计稿 `.dropzone`：min-height 268、内距 26 20、圆角 14）；
          // 列表非空时是 64 高的紧凑条。
          height: compact ? 64 : null,
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: compact ? 0 : 26),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: radius,
            // 拖入：浅橙底（N25）。
            color: over ? palette.accSoft : Colors.transparent,
          ),
          child: compact
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.music, size: 18, color: over ? palette.acc : palette.mut),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        l10n.musicEmptyLocalDesc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: palette.card),
                      child: Icon(LucideIcons.music, size: 22, color: palette.acc),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.musicEmptyLocalTitle,
                      style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(
                        l10n.musicEmptyLocalDesc,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: AppFont.px11, height: 1.6, color: palette.mut),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (onImportFile != null)
                          AppButton(
                            label: l10n.musicImportFiles,
                            icon: LucideIcons.filePlus,
                            variant: AppButtonVariant.ghost,
                            height: 30,
                            fontSize: AppFont.px11_5,
                            onTap: onImportFile,
                          ),
                        if (onImportFolder != null)
                          AppButton(
                            label: l10n.musicImportFolder,
                            icon: LucideIcons.folderPlus,
                            variant: AppButtonVariant.ghost,
                            height: 30,
                            fontSize: AppFont.px11_5,
                            onTap: onImportFolder,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.musicEmptyLocalFormats,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 虚线描边 painter（`.dropzone` 的 1.5px dashed；拖入时调用方切实线）。
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashed,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final bool dashed;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );
    if (!dashed) {
      canvas.drawRRect(rrect, paint);
      return;
    }
    final path = Path()..addRRect(rrect);
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius || old.dashed != dashed;
}

/// 撤销条（toast 无 action 参数的补位方案）：6 秒自动消失，撤销由调用方执行。
class _UndoBar extends StatelessWidget {
  const _UndoBar({required this.text, required this.undoLabel, required this.onUndo});

  final String text;
  final String undoLabel;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: palette.accSoft,
        border: Border.all(color: palette.acc.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 14, color: palette.accInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppFont.px11_5, color: palette.ink2),
            ),
          ),
          AppButton(
            label: undoLabel,
            variant: AppButtonVariant.link,
            height: 26,
            fontSize: AppFont.px11_5,
            fontWeight: FontWeight.w600,
            onTap: onUndo,
          ),
        ],
      ),
    );
  }
}

/// 骨架行（与 SongRow 同布局；骨架原子块复用 shared SkeletonBox）。
class _SkeletonRowLine extends StatelessWidget {
  const _SkeletonRowLine();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
      ),
      child: const Row(
        children: [
          SizedBox(width: 22, child: Center(child: SkeletonBox(width: 12, height: 11))),
          SizedBox(width: 8),
          Expanded(child: SkeletonBox(height: 11)),
          SizedBox(width: 16),
          SkeletonBox(width: 36, height: 11),
        ],
      ),
    );
  }
}
