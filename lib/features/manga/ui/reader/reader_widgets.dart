import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../controller/library_controller.dart';
import '../../controller/queue_controller.dart';
import 'reader_zoom.dart';

/// 阅读器拆分件（重设计稿 P4 目录归位，D-152 方式重做）：
/// ReaderBar（顶栏）/ ReaderPage（页图）/ NightTint（夜间滤镜）/ SheetLabel（抽屉标签）/
/// ComparePane（对照双栏）/ GridCell（网格总览单元）。
/// 缩放相关（ReaderZoom / ZoomablePage / PinchPage / ZoomChip / ZoomOsd）在 reader_zoom.dart；
/// 状态装配与手势编排仍在 reader_screen.dart。
class ReaderBar extends StatelessWidget {
  const ReaderBar({
    super.key,
    required this.title,
    required this.pageText,
    required this.toggleLabel,
    required this.onToggle,
    required this.onClose,
    required this.pageValue,
    required this.pageCount,
    required this.onPageChanged,
    required this.onSettings,
    required this.onCompare,
    required this.onCompareActive,
    required this.onGrid,
    required this.onGridActive,
    this.zoom,
  });

  final String title;
  final String pageText;
  final String toggleLabel;
  final VoidCallback onToggle;
  final VoidCallback onClose;

  /// 页码滑条（重设计稿顶栏：快速跳页）。
  final int pageValue;
  final int pageCount;
  final ValueChanged<int> onPageChanged;

  /// 设置抽屉入口（重设计稿顶栏齿轮）。
  final VoidCallback onSettings;

  /// 对照模式（桌面）：开关与激活态。
  final VoidCallback onCompare;
  final bool onCompareActive;

  /// 网格总览（桌面）：开关与激活态。
  final VoidCallback onGrid;
  final bool onGridActive;

  /// 缩放调节器（桌面专属，D-164）：null = 不渲染（移动端靠双指捏合）。
  final ReaderZoom? zoom;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.navBg,
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onClose,
            child: Row(
              children: [
                Icon(LucideIcons.chevronLeft, size: 14, color: palette.textSecondary),
                SizedBox(width: 2),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFont.px12_5, color: palette.textPrimary),
            ),
          ),
          // 页码滑条（重设计稿顶栏）：快速跳页。
          SizedBox(
            width: 120,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: palette.accent,
                inactiveTrackColor: palette.progressTrack,
                thumbColor: palette.accent,
              ),
              child: Slider(
                value: pageCount <= 1 ? 0 : pageValue / (pageCount - 1),
                max: 1,
                onChanged: (v) => onPageChanged((v * (pageCount - 1)).round()),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            pageText,
            style: TextStyle(fontSize: AppFont.px11_5, color: palette.textSecondary),
          ),
          const SizedBox(width: 10),
          if (zoom != null) ...[ZoomChip(zoom: zoom!), const SizedBox(width: 10)],
          AppButton(
            label: toggleLabel,
            onTap: onToggle,
            variant: AppButtonVariant.ghost,
            height: 24,
            horizontalPadding: 9,
            fontSize: AppFont.px10_5,
          ),
          const SizedBox(width: 10),
          if (!context.isMobile) ...[
            GestureDetector(
              onTap: onCompare,
              child: Icon(
                LucideIcons.columns2,
                size: 15,
                color: onCompareActive ? palette.accent : palette.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onGrid,
              child: Icon(
                LucideIcons.layoutGrid,
                size: 15,
                color: onGridActive ? palette.accent : palette.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
          ],
          GestureDetector(
            onTap: onSettings,
            child: Icon(LucideIcons.settings, size: 15, color: palette.textSecondary),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onClose,
            child: Icon(LucideIcons.x, size: 15, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.session, required this.seq, required this.showOriginal});

  final ReaderSession session;
  final int seq;

  /// true = 取原图；false = 取译文（缺译文时服务端自动回退原图）。
  final bool showOriginal;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换原图/译文后必须重新取图，否则画面不变。
    if (oldWidget.showOriginal != widget.showOriginal) {
      setState(() => _future = _load());
    }
  }

  Future<Uint8List?> _load() async {
    final client = ref.read(mangaSvcClientProvider);
    final s = widget.session;
    // 🔴 显示原图时**不请求译文**；显示译文时按该页是否有译文取。
    final wantTranslated = !widget.showOriginal && s.translated.contains(widget.seq);
    try {
      final bytes = s.chapterNo == null
          ? await client.getBookFile(s.key, widget.seq, translated: wantTranslated)
          : await client.getChapterFile(s.key, s.chapterNo!, widget.seq, translated: wantTranslated);
      if (bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: palette.textSecondary),
            ),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return Center(
            child: Text(
              AppLocalizations.of(context).shelfNoMatch,
              style: TextStyle(fontSize: AppFont.px12, color: palette.textSecondary),
            ),
          );
        }
        // 缩放/平移由外层舞台页负责（桌面 ZoomablePage / 移动 PinchPage），
        // 这里只画图 —— 两套缩放叠在一起会互相打架（D-164）。
        return Center(child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true));
      },
    );
  }
}

class NightTint extends StatelessWidget {
  const NightTint({super.key, required this.color, required this.child, this.desaturate = false});

  final Color color;
  final Widget child;
  final bool desaturate;

  @override
  Widget build(BuildContext context) {
    final content = desaturate
        ? ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.28, 0.55, 0.17, 0, 0, //
              0.28, 0.55, 0.17, 0, 0, //
              0.28, 0.55, 0.17, 0, 0, //
              0, 0, 0, 1, 0,
            ]),
            child: child,
          )
        : child;
    return Stack(
      children: [
        Positioned.fill(child: content),
        Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: color)),
        ),
      ],
    );
  }
}

class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Text(
        text,
        style: TextStyle(fontSize: AppFont.px10, letterSpacing: 1, color: AppPalette.of(context).accent),
      ),
    );
  }
}

class ComparePane extends ConsumerStatefulWidget {
  const ComparePane({
    super.key,
    required this.title,
    required this.showOriginal,
    required this.session,
    required this.seq,
  });

  final String title;
  final bool showOriginal;
  final ReaderSession session;
  final int seq;

  @override
  ConsumerState<ComparePane> createState() => _ComparePaneState();
}

class _ComparePaneState extends ConsumerState<ComparePane> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant ComparePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seq != widget.seq || oldWidget.showOriginal != widget.showOriginal) {
      setState(() => _future = _load());
    }
  }

  Future<Uint8List?> _load() async {
    final client = ref.read(mangaSvcClientProvider);
    final s = widget.session;
    final wantTranslated = !widget.showOriginal && s.translated.contains(widget.seq);
    try {
      final bytes = s.chapterNo == null
          ? await client.getBookFile(s.key, widget.seq, translated: wantTranslated)
          : await client.getChapterFile(s.key, s.chapterNo!, widget.seq, translated: wantTranslated);
      if (bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 24,
          color: palette.card,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.showOriginal ? palette.textSecondary : palette.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.title,
                style: TextStyle(fontSize: AppFont.px10, color: palette.ink2),
              ),
              const Spacer(),
              Text(
                '${widget.seq}',
                style: TextStyle(fontSize: AppFont.px9_5, color: palette.textSecondary),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Uint8List?>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: palette.textSecondary),
                  ),
                );
              }
              final bytes = snap.data;
              if (bytes == null) {
                return Center(
                  child: Text(
                    AppLocalizations.of(context).shelfNoMatch,
                    style: TextStyle(fontSize: AppFont.px11, color: palette.textSecondary),
                  ),
                );
              }
              return InteractiveViewer(
                maxScale: 5,
                child: Center(child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class GridCell extends ConsumerStatefulWidget {
  const GridCell({
    super.key,
    required this.session,
    required this.seq,
    required this.showOriginal,
    required this.current,
    required this.onTap,
  });

  final ReaderSession session;
  final int seq;
  final bool showOriginal;
  final bool current;
  final VoidCallback onTap;

  @override
  ConsumerState<GridCell> createState() => _GridCellState();
}

class _GridCellState extends ConsumerState<GridCell> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Uint8List?> _load() async {
    final client = ref.read(mangaSvcClientProvider);
    final s = widget.session;
    final wantTranslated = !widget.showOriginal && s.translated.contains(widget.seq);
    try {
      final bytes = s.chapterNo == null
          ? await client.getBookFile(s.key, widget.seq, translated: wantTranslated)
          : await client.getChapterFile(s.key, s.chapterNo!, widget.seq, translated: wantTranslated);
      if (bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: widget.current ? palette.accent : palette.line2, width: widget.current ? 2 : 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: FutureBuilder<Uint8List?>(
            future: _future,
            builder: (context, snap) {
              if (snap.data == null) {
                return ColoredBox(color: palette.card, child: const SizedBox.expand());
              }
              return Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true);
            },
          ),
        ),
      ),
    );
  }
}
