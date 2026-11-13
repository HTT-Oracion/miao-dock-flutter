import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_switch.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_player.dart';
import '../widgets/music_source_manager.dart';
import '../../controller/music_providers.dart';
import '../../controller/music_session.dart';
import '../../domain/music_models.dart';
import '../widgets/music_shared.dart';
import '../widgets/platform_logo.dart';
import 'mini_bar.dart' show TapScaleButton;

/// 移动端底部抽屉集合（M07/M12/M14）：队列 / 音质 / 样式 / 更多 / 账号。
///
/// 统一用自绘 [_SheetLayer]：底部上滑（[AppMotion.drawer] 380ms）、圆角顶部
/// [AppMetrics.radiusSheetTop]、拖把手 + 点遮罩关、最大 82% 高、内容可滚。
/// 不用 showAppSheet —— 桌面端宽屏会分流成右侧抽屉，移动端这里要的是
/// 原型 `.m-sheet` 的精确规格。
///
/// 边界不带动背后页面：抽屉是 Stack 兄弟节点，手势竞技场只命中抽屉自身
/// 的滚动视图，Flutter 里天然不会把边界滚动传给背后内容（对应原型
/// `overscroll-behavior: contain`），无需额外判定。
class MusicSheetsHost extends ConsumerStatefulWidget {
  const MusicSheetsHost({super.key, required this.moreOpen, required this.onMoreClose});

  /// 「更多」抽屉没有 musicUiProvider 位，由容器本地态驱动（偏差记入报告）。
  final bool moreOpen;
  final VoidCallback onMoreClose;

  @override
  ConsumerState<MusicSheetsHost> createState() => _MusicSheetsHostState();
}

class _MusicSheetsHostState extends ConsumerState<MusicSheetsHost> {
  // 队列清空的「撤销」：快照放在 host 态，抽屉关掉也能恢复（N15：6 秒内有效）。
  List<MusicSong>? _undoSnapshot;
  int _undoIdx = 0;
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  void _clearQueue() {
    final l10n = AppLocalizations.of(context);
    final player = ref.read(playerProvider);
    final snapshot = ref.read(playerProvider.notifier).clearQueueKeepCurrent();
    if (snapshot.isEmpty) return; // 队列本来为空，不给假成功提示
    _undoIdx = player.idx;
    _undoTimer?.cancel();
    setState(() => _undoSnapshot = snapshot);
    _undoTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _undoSnapshot = null);
    });
    showAppToast(context, l10n.musicQueueCleared, tone: ToastTone.info);
  }

  void _restoreQueue() {
    final snapshot = _undoSnapshot;
    if (snapshot == null) return;
    ref.read(playerProvider.notifier).restoreQueue(snapshot, _undoIdx);
    _undoTimer?.cancel();
    setState(() => _undoSnapshot = null);
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(musicUiProvider);
    return Stack(
      // 宿主撑满：_SheetLayer 是非定位子件，收缩会让遮罩 / 面板塌掉。
      fit: StackFit.expand,
      children: [
        _SheetLayer(
          open: ui.queueOpen,
          onClose: () => ref.read(musicUiProvider.notifier).setQueue(false),
          header: _QueueHeader(onClear: _clearQueue, onClose: () => ref.read(musicUiProvider.notifier).setQueue(false)),
          content: _QueueBody(undoSnapshot: _undoSnapshot, onUndo: _restoreQueue),
        ),
        _SheetLayer(
          open: ui.qualitySheetOpen,
          onClose: () => ref.read(musicUiProvider.notifier).setQualitySheet(false),
          header: _SheetHeader(title: AppLocalizations.of(context).musicQualitySheetTitle),
          content: const _QualityBody(),
        ),
        _SheetLayer(
          open: ui.styleSheetOpen,
          onClose: () => ref.read(musicUiProvider.notifier).setStyleSheet(false),
          header: _SheetHeader(title: AppLocalizations.of(context).musicSkinTitle),
          content: const _StyleBody(),
        ),
        _SheetLayer(
          open: widget.moreOpen,
          onClose: widget.onMoreClose,
          header: _SheetHeader(title: AppLocalizations.of(context).musicMoreAria),
          content: _MoreBody(onDone: widget.onMoreClose),
        ),
        // M10：移动端账号与音源抽屉由顶栏平台 logo 打开（accountSheetOpen）；
        // 与桌面账号菜单（accountMenuOpen）是两份状态，别混用 —— 否则点 logo 无反应。
        _SheetLayer(
          open: ui.accountSheetOpen,
          onClose: () => ref.read(musicUiProvider.notifier).setAccountSheet(false),
          header: _SheetHeader(title: AppLocalizations.of(context).musicAccountSheetTitle),
          content: const _AccountBody(),
        ),
      ],
    );
  }
}

// ── 抽屉通用骨架 ─────────────────────────────────────────────────────────────
/// 单层抽屉：遮罩渐隐 + 面板上滑（380ms）。open=false 时反向播放后再卸载。
class _SheetLayer extends StatefulWidget {
  const _SheetLayer({required this.open, required this.onClose, required this.header, required this.content});

  final bool open;
  final VoidCallback onClose;
  final Widget header;
  final Widget content;

  @override
  State<_SheetLayer> createState() => _SheetLayerState();
}

class _SheetLayerState extends State<_SheetLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppMotion.drawer, value: 0);
  bool _mounted = false;
  final ValueNotifier<double> _dragDy = ValueNotifier(0);
  double _dy = 0;

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      _mounted = true;
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _SheetLayer old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open) {
      setState(() => _mounted = true);
      _c.forward();
    } else if (!widget.open && old.open) {
      _c.reverse().whenComplete(() {
        if (mounted) setState(() => _mounted = false);
      });
    }
  }

  @override
  void dispose() {
    _dragDy.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_mounted) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    // M07：最大 82% 高。按**宿主约束**算而不是屏幕高度 —— 抽屉挂在模块内容区里
    // （底部还有迷你条 / 一级导航），用屏幕高度会算出一个放不下的面板，末行被裁掉。
    return LayoutBuilder(
      builder: (context, box) {
        final maxHeight = box.maxHeight * 0.82;
        return _buildLayer(context, palette, maxHeight);
      },
    );
  }

  Widget _buildLayer(BuildContext context, AppPalette palette, double maxHeight) {
    return Stack(
      // 遮罩（非定位子件）需要紧约束铺满；Align 面板贴底。
      fit: StackFit.expand,
      children: [
        // 遮罩：点外关（M07）。
        FadeTransition(
          opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(color: palette.shadow.withValues(alpha: 0.45)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ValueListenableBuilder(
            valueListenable: _dragDy,
            builder: (context, dy, child) =>
                Transform.translate(offset: Offset(0, dy + (1 - _c.value) * 52), child: child),
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _c, curve: AppMotion.morphCurve),
              child: Container(
                constraints: BoxConstraints(maxHeight: maxHeight),
                decoration: BoxDecoration(
                  color: palette.panel,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppMetrics.radiusSheetTop)),
                  border: Border(top: BorderSide(color: palette.line2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 拖把手：跟随下移，超过 120px 松手关闭，未过阈值回弹。
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (d) {
                        _dy = (_dy + d.delta.dy).clamp(0.0, 400.0);
                        _dragDy.value = _dy;
                      },
                      onVerticalDragEnd: (_) {
                        final over = _dy > 120;
                        _dy = 0;
                        if (over) {
                          widget.onClose();
                          _dragDy.value = 0;
                        } else {
                          _dragDy.value = 0;
                        }
                      },
                      child: Center(
                        child: Container(
                          width: 38,
                          height: 26,
                          alignment: Alignment.center,
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(color: palette.line2, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                    widget.header,
                    Flexible(child: widget.content),
                    SizedBox(height: MediaQuery.paddingOf(context).bottom), // M09 安全区
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 抽屉标题行（队列抽屉另带垃圾桶 + ✕ —— M12）。
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w700, color: palette.ink),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// 标题栏右侧 icon 键（M12：热区 ≥32、间距 10、aria-label 文字说明）。
class _SheetIconButton extends StatelessWidget {
  const _SheetIconButton({required this.icon, required this.semantics, required this.onTap, this.tooltip});

  final IconData icon;
  final String semantics;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = TapScaleButton(
      onTap: onTap,
      semantics: semantics,
      child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 17, color: AppPalette.of(context).mut)),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// 抽屉内选项行：图标块 + 主/副两行 + 尾部（勾选 / 徽标）。
class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.selected = false,
    this.danger = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = danger ? palette.bad : (selected ? palette.accInk : palette.ink);
    final lead =
        leading ??
        (icon != null
            ? Icon(icon, size: 16, color: danger ? palette.bad : (selected ? palette.acc : palette.ink2))
            : null);
    return TapScaleButton(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            if (lead != null) ...[lead, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w400, color: fg),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

// ── 队列抽屉 ────────────────────────────────────────────────────────────────
class _QueueHeader extends ConsumerWidget {
  const _QueueHeader({required this.onClear, required this.onClose});

  final VoidCallback onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(playerProvider.select((p) => p.queue.length));
    return _SheetHeader(
      title: '${l10n.musicQueueTitle} · ${l10n.musicCountSongs(count)}',
      actions: [
        // M12：垃圾桶 + ✕ 收进标题栏右端，间距 10，热区 32。
        _SheetIconButton(
          icon: LucideIcons.trash2,
          semantics: l10n.musicQueueClear,
          tooltip: l10n.musicQueueClear,
          onTap: onClear,
        ),
        const SizedBox(width: 10),
        // ARB 缺口：无通用「关闭」词条，✕ 用通用 actionCancel 作语义标签。
        _SheetIconButton(icon: LucideIcons.x, semantics: AppLocalizations.of(context).actionCancel, onTap: onClose),
        const SizedBox(width: 6),
      ],
    );
  }
}

class _QueueBody extends ConsumerWidget {
  const _QueueBody({required this.undoSnapshot, required this.onUndo});

  final List<MusicSong>? undoSnapshot;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final player = ref.watch(playerProvider);
    final queue = player.queue;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (undoSnapshot != null)
          // 撤销条（N15）：6 秒内可完整恢复顺序与当前索引。
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: palette.accSoft,
                borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.musicQueueCleared,
                      style: TextStyle(fontSize: AppFont.px11, color: palette.accInk),
                    ),
                  ),
                  TapScaleButton(
                    onTap: onUndo,
                    semantics: l10n.musicUndo,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        l10n.musicUndo,
                        style: TextStyle(fontSize: AppFont.px11, fontWeight: FontWeight.w700, color: palette.accInk),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (queue.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Column(
              children: [
                Text(
                  l10n.musicQueueEmptyTitle,
                  style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w600, color: palette.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.musicQueueEmptyDesc,
                  style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                ),
              ],
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: queue.length,
              itemBuilder: (context, i) {
                final s = queue[i];
                final on = i == player.idx;
                return InkWell(
                  onTap: () => ref.read(playerProvider.notifier).playAt(i),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    color: on ? palette.accSoft : Colors.transparent,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text(
                            on ? '♪' : '${i + 1}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: AppFont.px11,
                              color: on ? palette.acc : palette.mut,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppFont.px12_5,
                                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                                  color: on ? palette.accInk : palette.ink,
                                ),
                              ),
                              Text(
                                s.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatSongDuration(s.duration),
                          style: TextStyle(
                            fontSize: AppFont.px10_5,
                            color: palette.mut,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 4),
                        TapScaleButton(
                          onTap: () => ref.read(playerProvider.notifier).removeAt(i),
                          semantics: l10n.musicQueueRemoveAria,
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(LucideIcons.x, size: 16, color: palette.mut),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ── 音质抽屉（N11/M07）──────────────────────────────────────────────────────
class _QualityBody extends ConsumerWidget {
  const _QualityBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(playerProvider.select((p) => p.quality));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final q in QualityTier.values)
          _SheetOption(
            icon: LucideIcons.audioLines,
            title: qualityLabel(l10n, q),
            subtitle: '${qualitySub(l10n, q)}${_limitSuffix(l10n, q)}',
            selected: q == current,
            trailing: q == current ? Icon(LucideIcons.check, size: 16, color: AppPalette.of(context).acc) : null,
            onTap: () {
              ref.read(playerProvider.notifier).setQuality(q);
              ref.read(musicUiProvider.notifier).setQualitySheet(false);
              showAppToast(context, l10n.musicQualityNow(qualityLabel(l10n, q)));
            },
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  String _limitSuffix(AppLocalizations l10n, QualityTier q) {
    final limit = qualityLimit(l10n, q);
    return limit == null ? '' : ' · $limit';
  }
}

// ── 样式抽屉（N17/M07）──────────────────────────────────────────────────────
class _StyleBody extends ConsumerStatefulWidget {
  const _StyleBody();

  @override
  ConsumerState<_StyleBody> createState() => _StyleBodyState();
}

class _StyleBodyState extends ConsumerState<_StyleBody> {
  // 「动态」开关仅现代样式出现（N17）；无 provider 位，抽屉内本地态（偏差记入报告）。
  bool _dynamic = true;

  static Widget _swatch(PlayerStyle s, BuildContext context) {
    final palette = AppPalette.of(context);
    final colors = switch (s) {
      PlayerStyle.modern => [palette.accSoft, palette.bg],
      PlayerStyle.cover => [palette.coverEnd, palette.card],
      PlayerStyle.vinyl => [const Color(0xFF0B0E12), const Color(0xFF1B222A)],
      PlayerStyle.spectrum => [palette.acc, palette.bg],
      PlayerStyle.immersive => [palette.bg, palette.accSoft],
      PlayerStyle.glass => [palette.card, palette.panel],
    };
    return Container(
      width: 22,
      height: 16,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: palette.line2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final current = ref.watch(playerStyleProvider);
    final entries = <(PlayerStyle, String, String)>[
      (PlayerStyle.modern, l10n.musicSkinModern, l10n.musicSkinModernDesc),
      (PlayerStyle.cover, l10n.musicSkinCover, l10n.musicSkinCoverDesc),
      (PlayerStyle.vinyl, l10n.musicSkinVinyl, l10n.musicSkinVinylDesc),
      (PlayerStyle.spectrum, l10n.musicSkinSpectrum, l10n.musicSkinSpectrumDesc),
      (PlayerStyle.immersive, l10n.musicSkinImmersive, l10n.musicSkinImmersiveDesc),
      (PlayerStyle.glass, l10n.musicSkinGlass, l10n.musicSkinGlassDesc),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (style, name, desc) in entries)
          _SheetOption(
            leading: _swatch(style, context),
            title: name,
            subtitle: desc,
            selected: style == current,
            trailing: style == current ? Icon(LucideIcons.check, size: 16, color: palette.acc) : null,
            onTap: () {
              ref.read(playerStyleProvider.notifier).set(style);
              ref.read(musicUiProvider.notifier).setStyleSheet(false); // 点选生效即关（M07）
            },
          ),
        // 「动态」开关仅现代样式出现（N17：其余样式没有可动元素）。
        if (current == PlayerStyle.modern)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.musicSkinDynamic,
                    style: TextStyle(fontSize: AppFont.px13, color: palette.ink),
                  ),
                ),
                AppSwitch(value: _dynamic, onChanged: (v) => setState(() => _dynamic = v)),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── 更多抽屉（M14）──────────────────────────────────────────────────────────
class _MoreBody extends ConsumerWidget {
  const _MoreBody({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final song = ref.watch(playerProvider.select((p) => p.current));

    Widget item({required IconData icon, required String title, String? subtitle, required VoidCallback onTap}) =>
        _SheetOption(icon: icon, title: title, subtitle: subtitle, onTap: onTap);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        item(
          icon: LucideIcons.palette,
          title: l10n.musicMoreStyle,
          subtitle: l10n.musicSkinModernDesc,
          onTap: () {
            onDone();
            ref.read(musicUiProvider.notifier).setStyleSheet(true);
          },
        ),
        // 加入歌单：无真实动作，无「已加入」词条（ARB 缺口，报告）——
        // 以动作名作轻提示占位。
        item(
          icon: LucideIcons.listPlus,
          title: l10n.musicMoreAddTo,
          onTap: () {
            onDone();
            showAppToast(context, l10n.musicMoreAddTo);
          },
        ),
        item(
          icon: LucideIcons.link2,
          title: l10n.musicMoreCopy,
          onTap: () {
            onDone();
            Clipboard.setData(const ClipboardData(text: 'miao-dock://music/demo-song'));
            showAppToast(context, l10n.musicCopied);
          },
        ),
        // 设为铃声 / 睡眠定时：演示占位，无结果词条（ARB 缺口，报告）。
        item(
          icon: LucideIcons.music2,
          title: l10n.musicMoreRingtone,
          onTap: () {
            onDone();
            showAppToast(context, l10n.musicMoreRingtone);
          },
        ),
        item(
          icon: LucideIcons.timer,
          title: l10n.musicMoreSleep,
          onTap: () {
            onDone();
            showAppToast(context, l10n.musicMoreSleep);
          },
        ),
        item(
          icon: LucideIcons.info,
          title: l10n.musicMoreInfo,
          subtitle: song == null ? null : l10n.musicSongInfoLine(song.album, song.qualityLabel ?? ''),
          onTap: () {
            onDone();
            if (song == null) return;
            showAppToast(context, l10n.musicSongInfoLine(song.album, song.qualityLabel ?? l10n.musicQualityStd));
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── 账号抽屉（M10/N40）──────────────────────────────────────────────────────
class _AccountBody extends ConsumerWidget {
  const _AccountBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final acc = ref.watch(musicAccountProvider);

    String badgeOf(String p) {
      if (p == acc.cur) return l10n.musicBadgeCur;
      return acc.isLogged(p) ? l10n.musicBadgeLogged : l10n.musicBadgeOff;
    }

    // 🔴 平台行只列**已导入源**的平台；无源时整个平台列表换成导入入口。
    final available = ref.watch(musicPlatformInfosProvider);

    void tapPlatform(String p) {
      final notifier = ref.read(musicUiProvider.notifier);
      // 未登录优先：当前源未登录（如网易云）点自己也要能拉起登录。
      if (!acc.isLogged(p)) {
        notifier.setAccountSheet(false);
        notifier.openLogin(p);
        return;
      }
      if (p == acc.cur) return;
      // 到这里一定是「已登录且不是当前源」：切换并播报。
      ref.read(musicAccountProvider.notifier).switchPlatform(p);
      showAppToast(context, l10n.musicSwitchSourceToast(platformLabel(l10n, p, infos: available)));
      notifier.setAccountSheet(false);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Row(
            children: [
              MusicPlatformBadge(info: platformInfoById(acc.cur, available), size: 40),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      acc.logged ? (acc.nick ?? l10n.musicNotLogged) : l10n.musicNotLogged,
                      style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      l10n.musicCurSourceAria(platformLabel(l10n, acc.cur)),
                      style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (available.isEmpty)
          _SheetOption(
            leading: Icon(LucideIcons.disc3, size: 18, color: palette.mut),
            title: l10n.musicSourceMgrOpen,
            trailing: const SizedBox.shrink(),
            onTap: () {
              ref.read(musicUiProvider.notifier).setAccountSheet(false);
              MusicSourceManagerModal.open(context);
            },
          )
        else
          for (final info in available)
            _SheetOption(
              leading: MusicPlatformBadge(info: info, size: 18),
              title: info.label,
              trailing: Text(
                badgeOf(info.id),
                style: TextStyle(fontSize: AppFont.px10_5, color: info.id == acc.cur ? palette.accInk : palette.mut),
              ),
              onTap: () => tapPlatform(info.id),
            ),
        if (acc.logged) ...[
          Container(height: 1, color: palette.line, margin: const EdgeInsets.symmetric(vertical: 6)),
          _SheetOption(
            icon: LucideIcons.logOut,
            title: l10n.musicLogout,
            danger: true,
            onTap: () {
              ref.read(musicAccountProvider.notifier).logout();
              ref.read(musicUiProvider.notifier).setAccountSheet(false);
              showAppToast(context, l10n.musicLogout);
            },
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
