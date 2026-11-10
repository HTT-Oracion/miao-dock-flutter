import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import 'reader_prefs.dart';

/// 条漫连续滚动舞台：漫画库与在线阅读器共用。
///
/// 交互口径以漫画库为准：纵向无缝滚动、中心点按呼出/收起工具栏、
/// 自动滚动（触摸即断 600ms 续播）、左下角计页 chip、滚到底出章末卡。
class ReaderWebtoonStage extends ConsumerStatefulWidget {
  const ReaderWebtoonStage({
    super.key,
    required this.pageCount,
    required this.pageBuilder,
    required this.onCenterTap,
    this.endCard,
  });

  final int pageCount;
  final Widget Function(BuildContext context, int seq) pageBuilder;
  final VoidCallback onCenterTap;
  final Widget? endCard;

  @override
  ConsumerState<ReaderWebtoonStage> createState() => _ReaderWebtoonStageState();
}

class _ReaderWebtoonStageState extends ConsumerState<ReaderWebtoonStage> {
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
    final page = (_scroll.offset / max * (widget.pageCount - 1)).round() + 1;
    if (page != _page) setState(() => _page = page.clamp(1, widget.pageCount));
  }

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
    final total = widget.pageCount;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
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
            itemCount: total + 1,
            itemBuilder: (context, i) {
              if (i == total) {
                return SizedBox(height: 320, child: widget.endCard ?? const SizedBox.shrink());
              }
              return widget.pageBuilder(context, i + 1);
            },
          ),
        ),
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
