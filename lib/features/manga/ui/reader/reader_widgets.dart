import 'dart:math' as math;
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
import 'reader_image_cache.dart';
import 'reader_slider.dart';
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
    this.toggleLabel = '',
    this.onToggle,
    required this.onClose,
    required this.pageValue,
    required this.pageCount,
    required this.onPageChanged,
    this.onSettings,
    this.onCompare,
    this.onCompareActive = false,
    required this.onGrid,
    required this.onGridActive,
    this.zoom,
    this.onFullscreen,
    this.onHelp,
    this.extra,
  });

  final String title;
  final String pageText;
  final String toggleLabel;
  final VoidCallback? onToggle;
  final VoidCallback onClose;

  /// 页码滑条（重设计稿顶栏：快速跳页）。
  final int pageValue;
  final int pageCount;
  final ValueChanged<int> onPageChanged;

  /// 设置抽屉入口（重设计稿顶栏齿轮）。
  final VoidCallback? onSettings;

  /// 对照模式（桌面）：开关与激活态。
  final VoidCallback? onCompare;
  final bool onCompareActive;

  /// 网格总览（桌面）：开关与激活态。
  final VoidCallback onGrid;
  final bool onGridActive;

  /// 缩放调节器（桌面专属，D-164）：null = 不渲染（移动端靠双指捏合）。
  final ReaderZoom? zoom;

  /// 全屏 / 快捷键速查（桌面专属）：null = 不渲染。
  final VoidCallback? onFullscreen;
  final VoidCallback? onHelp;

  /// 数据侧扩展动作（在线源的章节入口等）；漫画库不传。
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      // 设计稿 `.rbar`：48px 玻璃工具带（原 42px 实色，和页面抢注意力）。
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.92),
        border: Border(bottom: BorderSide(color: palette.line2.withValues(alpha: 0.7))),
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
          // 页码滑条：与移动端同一颗组件（拖动出气泡、竖拖微调）。
          SizedBox(
            width: 168,
            child: PageSlider(value: pageValue, count: pageCount, onChanged: onPageChanged),
          ),
          const SizedBox(width: 4),
          Text(
            pageText,
            style: TextStyle(fontSize: AppFont.px11_5, color: palette.textSecondary),
          ),
          const SizedBox(width: 10),
          if (zoom != null) ...[ZoomChip(zoom: zoom!), const SizedBox(width: 10)],
          if (onToggle != null)
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
            if (onCompare != null) ...[
              GestureDetector(
                onTap: onCompare,
                child: Icon(
                  LucideIcons.columns2,
                  size: 15,
                  color: onCompareActive ? palette.accent : palette.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
            ],
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
          if (onHelp != null) ...[
            _BarIcon(icon: LucideIcons.circleHelp, tooltip: l10n.readerHelp, onTap: onHelp!),
            const SizedBox(width: 10),
          ],
          if (onFullscreen != null) ...[
            _BarIcon(icon: LucideIcons.maximize, tooltip: l10n.readerFullscreen, onTap: onFullscreen!),
            const SizedBox(width: 10),
          ],
          if (extra != null) ...[extra!, const SizedBox(width: 10)],
          if (onSettings != null) ...[
            GestureDetector(
              onTap: onSettings,
              child: Icon(LucideIcons.settings, size: 15, color: palette.textSecondary),
            ),
            const SizedBox(width: 10),
          ],
          GestureDetector(
            onTap: onClose,
            child: Icon(LucideIcons.x, size: 15, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onTap: onTap,
        child: Icon(icon, size: 15, color: palette.textSecondary),
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
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换原图/译文后必须重新取图，否则画面不变。
    if (oldWidget.showOriginal != widget.showOriginal || oldWidget.seq != widget.seq) {
      setState(() {
        _bytes = null;
        _loading = true;
      });
      _resolve();
    }
  }

  String get _cacheKey => readerImageKey(
    bookKey: widget.session.key,
    chapterNo: widget.session.chapterNo,
    seq: widget.seq,
    translated: _wantTranslated,
  );

  /// 显示原图时**不请求译文**；显示译文时按该页是否有译文取。
  bool get _wantTranslated => !widget.showOriginal && widget.session.translated.contains(widget.seq);

  void _resolve() {
    // 缓存命中就**同步**出图：翻页那一帧不再先画 loading（用户看到的「闪一下」）。
    final cached = ReaderImageCache.get(_cacheKey);
    if (cached != null) {
      _bytes = cached;
      _loading = false;
      return;
    }
    _fetch();
  }

  Future<void> _fetch() async {
    final key = _cacheKey;
    final client = ref.read(mangaSvcClientProvider);
    final s = widget.session;
    try {
      final bytes = s.chapterNo == null
          ? await client.getBookFile(s.key, widget.seq, translated: _wantTranslated)
          : await client.getChapterFile(s.key, s.chapterNo!, widget.seq, translated: _wantTranslated);
      if (bytes.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final data = Uint8List.fromList(bytes);
      ReaderImageCache.put(key, data);
      if (!mounted) return;
      setState(() {
        _bytes = data;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bytes = _bytes;
    if (bytes != null) {
      // 缩放/平移由外层舞台页负责（桌面 ZoomablePage / 移动 MobileReaderStage），
      // 这里只画图 —— 两套缩放叠在一起会互相打架（D-164）。
      return Center(child: ReaderPageImage(bytes: bytes));
    }
    if (_loading) {
      return Center(child: ReaderSpinner(color: palette.textSecondary));
    }
    return Center(
      child: Text(
        AppLocalizations.of(context).shelfNoMatch,
        style: TextStyle(fontSize: AppFont.px12, color: palette.textSecondary),
      ),
    );
  }
}

/// 页图：`contain` 铺满舞台，首帧淡入（120ms）避免解码那一下硬跳。
class ReaderPageImage extends StatelessWidget {
  const ReaderPageImage({super.key, required this.bytes, this.fit = BoxFit.contain, this.width, this.height});

  final Uint8List bytes;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      bytes,
      fit: fit,
      width: width,
      height: height,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: AppMotion.fast,
          curve: AppMotion.easeOutCubic,
          child: child,
        );
      },
    );
  }
}

/// 阅读器 loading：自绘 260° 圆弧，1.6s 一圈匀速转。
///
/// 不用 [CircularProgressIndicator]：它自带「伸长—缩短」的四段相位，
/// 视觉上是猛转一圈再顿一下，页图这种「等一两百毫秒」的场景显得很急。
class ReaderSpinner extends StatefulWidget {
  const ReaderSpinner({super.key, required this.color, this.size = 20, this.strokeWidth = 2});

  final Color color;
  final double size;
  final double strokeWidth;

  @override
  State<ReaderSpinner> createState() => _ReaderSpinnerState();
}

class _ReaderSpinnerState extends State<ReaderSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppMotion.spinner)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _ArcPainter(color: widget.color, strokeWidth: widget.strokeWidth),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(strokeWidth / 2, strokeWidth / 2) & Size(size.width - strokeWidth, size.height - strokeWidth);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    // 260° 留一个缺口，转起来才看得出方向。
    canvas.drawArc(rect, 0, 260 * math.pi / 180, false, paint);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => old.color != color || old.strokeWidth != strokeWidth;
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
    this.onTapAt,
  });

  final String title;
  final bool showOriginal;
  final ReaderSession session;
  final int seq;

  /// 点这一栏：参数是**本栏内**的局部坐标。
  ///
  /// 分区（上一页 / 下一页 / 呼出工具栏）由屏幕按整舞台宽度换算 ——
  /// `ComparePane` 只占一半，自己判断会得出「左栏右缘 = 下一页」这种怪区。
  final void Function(Offset localPosition)? onTapAt;

  @override
  ConsumerState<ComparePane> createState() => _ComparePaneState();
}

class _ComparePaneState extends ConsumerState<ComparePane> {
  Uint8List? _bytes;
  bool _loading = true;

  /// 请求代次：连续翻页时旧的请求不能覆盖新页。
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ComparePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seq != widget.seq || oldWidget.showOriginal != widget.showOriginal) {
      // `didUpdateWidget` 之后必有一次 build，这里直接改字段即可，不用 setState。
      _resolve();
    }
  }

  bool get _wantTranslated => !widget.showOriginal && widget.session.translated.contains(widget.seq);

  String get _cacheKey => readerImageKey(
    bookKey: widget.session.key,
    chapterNo: widget.session.chapterNo,
    seq: widget.seq,
    translated: _wantTranslated,
  );

  /// 缓存命中就**同步**出图：对照里翻页不该先闪一帧加载圈（与 D-167 同口径）。
  void _resolve() {
    final cached = ReaderImageCache.get(_cacheKey);
    _bytes = cached;
    _loading = cached == null;
    if (cached != null) return;
    _fetch(++_token);
  }

  Future<void> _fetch(int token) async {
    final key = _cacheKey;
    final client = ref.read(mangaSvcClientProvider);
    final s = widget.session;
    final wantTranslated = _wantTranslated;
    Uint8List? data;
    try {
      final bytes = s.chapterNo == null
          ? await client.getBookFile(s.key, widget.seq, translated: wantTranslated)
          : await client.getChapterFile(s.key, s.chapterNo!, widget.seq, translated: wantTranslated);
      if (bytes.isNotEmpty) {
        data = Uint8List.fromList(bytes);
        ReaderImageCache.put(key, data);
      }
    } catch (_) {
      data = null;
    }
    if (!mounted || token != _token) return;
    setState(() {
      _bytes = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: widget.onTapAt == null ? null : (d) => widget.onTapAt!(d.localPosition),
      child: Column(
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
            child: switch ((_loading, _bytes)) {
              (true, _) => Center(child: ReaderSpinner(color: palette.textSecondary)),
              (false, null) => Center(
                child: Text(
                  AppLocalizations.of(context).shelfNoMatch,
                  style: TextStyle(fontSize: AppFont.px11, color: palette.textSecondary),
                ),
              ),
              (false, final bytes?) => InteractiveViewer(
                maxScale: 5,
                child: Center(child: ReaderPageImage(bytes: bytes)),
              ),
            },
          ),
        ],
      ),
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
    final key = readerImageKey(bookKey: s.key, chapterNo: s.chapterNo, seq: widget.seq, translated: wantTranslated);
    final cached = ReaderImageCache.get(key);
    if (cached != null) return cached;
    try {
      final bytes = s.chapterNo == null
          ? await client.getBookFile(s.key, widget.seq, translated: wantTranslated)
          : await client.getChapterFile(s.key, s.chapterNo!, widget.seq, translated: wantTranslated);
      if (bytes.isEmpty) return null;
      final data = Uint8List.fromList(bytes);
      ReaderImageCache.put(key, data);
      return data;
    } catch (_) {
      return null;
    }
  }

  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        // 设计稿 `.gcell:hover`：1.05；当前页额外一圈主色描边 + 角标。
        scale: _hover ? 1.05 : 1,
        duration: AppMotion.fast,
        curve: AppMotion.morphCurve,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.current ? palette.accent : (_hover ? palette.line2 : Colors.transparent),
                width: widget.current ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.data == null) {
                        return ColoredBox(color: palette.card, child: const SizedBox.expand());
                      }
                      return ReaderPageImage(bytes: snap.data!, fit: BoxFit.cover);
                    },
                  ),
                  if (widget.current)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: palette.accent,
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(5)),
                        ),
                        child: Text(
                          AppLocalizations.of(context).readerGridCurrent,
                          style: TextStyle(fontSize: AppFont.px8_5, fontWeight: FontWeight.w700, color: palette.onAcc),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 章末衔接卡（翻页模式拖到末页继续拖 / 条漫滚到底）。
///
/// 两个平台共用：`onClose` 为 null 时不出 ×（条漫里卡片是列表尾巴，
/// 没有「关掉」这回事）；翻页模式是浮层，必须有 ×，点遮罩也能关。
class ReaderEndCard extends StatelessWidget {
  const ReaderEndCard({super.key, required this.onNext, this.onBack, this.onClose, this.nextLabel, this.backLabel});

  final VoidCallback onNext;

  /// 副按钮；null = 不渲染（例如单话里它和主按钮同为「回书架」，重复没意义）。
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final String? nextLabel;
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.line2),
        boxShadow: [BoxShadow(color: palette.shadow.withValues(alpha: 0.45), blurRadius: 30)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.readerEndcardOver,
                  style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
                ),
              ),
              if (onClose != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: SizedBox(width: 26, height: 26, child: Icon(LucideIcons.x, size: 15, color: palette.mut)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          AppButton(
            label: nextLabel ?? l10n.readerEndcardNext,
            onTap: onNext,
            variant: AppButtonVariant.primary,
            height: 34,
            horizontalPadding: 18,
          ),
          if (onBack != null) ...[
            const SizedBox(height: 8),
            AppButton(
              label: backLabel ?? l10n.readerEndcardBack,
              onTap: onBack!,
              variant: AppButtonVariant.ghost,
              height: 34,
              horizontalPadding: 18,
            ),
          ],
        ],
      ),
    );
  }
}

/// 桌面底部提示条（设计稿 `.foot`，34px）：把最常用的几组键摆在手边。
class ReaderFootBar extends StatelessWidget {
  const ReaderFootBar({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: palette.line2.withValues(alpha: 0.7))),
      ),
      child: Text(
        AppLocalizations.of(context).readerFootHint,
        style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
      ),
    );
  }
}

/// 快捷键速查卡（设计稿 `.help`，`?` 呼出）：每行 = 键 + 说明。
///
/// 说明文案整句进 ARB（含键名），不做「键列 / 说明列」两段拼装 ——
/// 键名里有「滚轮」这种中文，拆列就得为键名再造一批词条。
class ReaderHelpCard extends StatelessWidget {
  const ReaderHelpCard({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final rows = [
      l10n.readerHelpTurn,
      l10n.readerHelpWheelZoom,
      l10n.readerHelpWheelTurn,
      l10n.readerHelpStepZoom,
      l10n.readerHelpCompare,
      l10n.readerHelpOriginal,
      l10n.readerHelpGrid,
      l10n.readerHelpFullscreen,
      l10n.readerHelpTap,
      l10n.readerHelpEsc,
      l10n.readerHelpOpenHint,
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: ColoredBox(
        color: palette.shadow.withValues(alpha: 0.72),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
              decoration: BoxDecoration(
                color: palette.panel,
                borderRadius: BorderRadius.circular(AppMetrics.radiusModal),
                border: Border.all(color: palette.line2),
                boxShadow: [BoxShadow(color: palette.shadow.withValues(alpha: 0.5), blurRadius: 40)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.readerHelpTitle,
                          style: TextStyle(fontSize: AppFont.px14, fontWeight: FontWeight.w700, color: palette.ink),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onClose,
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Icon(LucideIcons.x, size: 16, color: palette.mut),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              row,
                              style: TextStyle(fontSize: AppFont.px12, color: palette.ink2),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
