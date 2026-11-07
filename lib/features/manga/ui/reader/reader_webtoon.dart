import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../controller/library_controller.dart';
import '../../controller/queue_controller.dart';
import 'reader_image_cache.dart';
import 'reader_prefs.dart';
import 'reader_widgets.dart';

/// 条漫（webtoon）连续滚动视图（重设计稿 mobile.html 条漫语义）：
/// 纵向无缝滚动 · 中心点按呼出/收起工具栏 · 自动滚动（触摸即断 600ms 续播）·
/// 左下角计页 chip · 滚到底出章末衔接卡。
class ReaderWebtoonView extends ConsumerStatefulWidget {
  const ReaderWebtoonView({
    super.key,
    required this.session,
    required this.showOriginal,
    required this.onCenterTap,
    this.endCard,
  });

  final ReaderSession session;
  final bool showOriginal;
  final VoidCallback onCenterTap;

  /// 末尾衔接卡（由屏幕装配：文案与去向要跟翻页模式一致）。
  final Widget? endCard;

  @override
  ConsumerState<ReaderWebtoonView> createState() => _ReaderWebtoonViewState();
}

class _ReaderWebtoonViewState extends ConsumerState<ReaderWebtoonView> {
  final _scroll = ScrollController();
  Timer? _autoTimer;
  Timer? _resumeTimer;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _resumeTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    final page = (_scroll.offset / max * (widget.session.pages - 1)).round() + 1;
    if (page != _page) setState(() => _page = page.clamp(1, widget.session.pages));
  }

  /// 自动滚动（重设计稿：真匀速滚动；触摸即断，600ms 后续播）。
  void _setAuto(bool on) {
    ref.read(readerPrefsProvider.notifier).toggleAutoScroll();
    if (!on) {
      _autoTimer?.cancel();
      return;
    }
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (_scroll.offset >= max) {
        _setAutoOff();
        return;
      }
      _scroll.jumpTo((_scroll.offset + 0.6).clamp(0, max));
    });
  }

  void _setAutoOff() {
    if (ref.read(readerPrefsProvider).autoScroll) {
      ref.read(readerPrefsProvider.notifier).toggleAutoScroll();
    }
    _autoTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final auto = ref.watch(readerPrefsProvider).autoScroll;
    final total = widget.session.pages;

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            // 触摸即断：手指按下/拖动时暂停自动滚动，松手 600ms 后续播。
            if (auto && n is ScrollStartNotification) {
              _autoTimer?.cancel();
              _resumeTimer?.cancel();
              _resumeTimer = Timer(const Duration(milliseconds: 600), () {
                if (mounted && ref.read(readerPrefsProvider).autoScroll) _setAuto(true);
              });
            }
            return false;
          },
          child: ListView.builder(
            controller: _scroll,
            itemCount: total + 1, // 末尾 = 章末衔接卡
            itemBuilder: (context, i) {
              if (i == total) {
                return SizedBox(height: 320, child: widget.endCard ?? const SizedBox.shrink());
              }
              return _WebtoonPage(session: widget.session, seq: i + 1, showOriginal: widget.showOriginal);
            },
          ),
        ),
        // 计页 chip（重设计稿：左下角，滚动时出现、停止 800ms 后隐去——这里常驻简化）。
        Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$_page / $total',
              style: TextStyle(
                fontSize: AppFont.px10,
                color: palette.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        // 自动滚动指示（右下角小圆点 + 图标）。
        if (auto)
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
              child: Icon(LucideIcons.arrowDown, size: 14, color: palette.accent),
            ),
          ),
        // 中心点按：呼出/收起工具栏（左右两侧留白给系统手势与自由滚动）。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (d) {
              final rel = d.localPosition.dx / MediaQuery.sizeOf(context).width;
              if (rel > 0.3 && rel < 0.7) widget.onCenterTap();
            },
          ),
        ),
      ],
    );
  }
}

/// 条漫页：整宽自适应高度（与翻页模式的 contain 不同——条漫页要无缝相接）。
class _WebtoonPage extends ConsumerStatefulWidget {
  const _WebtoonPage({required this.session, required this.seq, required this.showOriginal});

  final ReaderSession session;
  final int seq;
  final bool showOriginal;

  @override
  ConsumerState<_WebtoonPage> createState() => _WebtoonPageState();
}

class _WebtoonPageState extends ConsumerState<_WebtoonPage> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _WebtoonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showOriginal != widget.showOriginal) {
      setState(() => _future = _load());
    }
  }

  Future<Uint8List?> _load() async {
    final client = ref.read(mangaSvcClientProvider);
    final s = widget.session;
    // 🔴 显示原图时不请求译文；显示译文时按该页是否有译文取（与翻页模式同语义）。
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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            height: 420,
            color: palette.card,
            alignment: Alignment.center,
            child: ReaderSpinner(color: palette.textSecondary),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return Container(
            height: 120,
            color: palette.card,
            alignment: Alignment.center,
            child: Text(
              AppLocalizations.of(context).shelfNoMatch,
              style: TextStyle(fontSize: AppFont.px11, color: palette.textSecondary),
            ),
          );
        }
        return ReaderPageImage(bytes: bytes, fit: BoxFit.fitWidth, width: double.infinity);
      },
    );
  }
}
