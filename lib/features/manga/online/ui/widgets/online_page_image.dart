import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/theme/tokens.dart';
import 'online_common.dart';

/// 真实页图渲染：保留原文/译文状态与扫描线，但不再合成漫画内容。
class OnlinePageImage extends StatefulWidget {
  const OnlinePageImage({
    super.key,
    required this.page,
    required this.bytes,
    required this.translated,
    this.scanning = false,
  });

  final int page;
  final Uint8List bytes;
  final bool translated;
  final bool scanning;

  @override
  State<OnlinePageImage> createState() => _OnlinePageImageState();
}

class _OnlinePageImageState extends State<OnlinePageImage> with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.scanning) _scan.repeat();
  }

  @override
  void didUpdateWidget(covariant OnlinePageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scanning && !_scan.isAnimating) {
      _scan.repeat();
    } else if (!widget.scanning && _scan.isAnimating) {
      _scan.stop();
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: ColoredBox(
        color: onlineReaderStageColor(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              widget.bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) =>
                  Center(child: Icon(LucideIcons.imageOff, size: 28, color: palette.ink2)),
            ),
            if (widget.translated)
              Positioned.fill(
                child: IgnorePointer(child: ColoredBox(color: palette.blue.withValues(alpha: 0.035))),
              ),
            if (widget.scanning)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _scan,
                    builder: (context, _) => Align(
                      alignment: Alignment(0, -1 + _scan.value * 2),
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              palette.blue.withValues(alpha: 0),
                              palette.blue.withValues(alpha: 0.9),
                              palette.blue.withValues(alpha: 0),
                            ],
                          ),
                          boxShadow: [BoxShadow(color: palette.blue.withValues(alpha: 0.5), blurRadius: 8)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
