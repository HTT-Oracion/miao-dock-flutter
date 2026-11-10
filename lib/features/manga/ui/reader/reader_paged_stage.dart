import 'package:flutter/material.dart';

import 'reader_zoom.dart';

/// 桌面单页舞台：漫画库与在线阅读器共用。
///
/// 交互口径与漫画库完全一致：未放大时 [PageView] 跟手翻页；放大后关闭
/// PageView 滚动，拖动交给 [ZoomablePage] 平移；页码由外部 index 驱动，
/// 滑条 / 键盘 / 换话都能把舞台同步到目标页。
class PagedReaderStage extends StatefulWidget {
  const PagedReaderStage({
    super.key,
    required this.controller,
    required this.zoom,
    required this.pageCount,
    required this.index,
    required this.pageBuilder,
    required this.onPageChanged,
    this.onTap,
  });

  final PageController controller;
  final ReaderZoom zoom;
  final int pageCount;

  /// 0 基当前页。
  final int index;
  final Widget Function(BuildContext context, int index) pageBuilder;
  final ValueChanged<int> onPageChanged;
  final VoidCallback? onTap;

  @override
  State<PagedReaderStage> createState() => _PagedReaderStageState();
}

class _PagedReaderStageState extends State<PagedReaderStage> {
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PagedReaderStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _sync();
  }

  void _sync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.controller.hasClients) return;
      if (widget.controller.page?.round() != widget.index) {
        widget.controller.jumpToPage(widget.index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.zoom,
      builder: (context, _) => PageView.builder(
        controller: widget.controller,
        physics: widget.zoom.zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
        itemCount: widget.pageCount,
        onPageChanged: (index) {
          widget.zoom.reset();
          widget.onPageChanged(index);
        },
        itemBuilder: (context, index) => ZoomablePage(
          key: ValueKey('paged-reader-$index'),
          zoom: widget.zoom,
          onTap: widget.onTap,
          child: widget.pageBuilder(context, index),
        ),
      ),
    );
  }
}
