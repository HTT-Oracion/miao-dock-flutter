import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader/reader_zoom.dart';

void main() {
  test('阅读器缩放上限 250%，放大后可平移', () {
    final zoom = ReaderZoom()..viewport = const Size(800, 600);
    expect(zoom.maxScale, 2.5);
    zoom.scaleAt(const Offset(400, 300), 10);
    expect(zoom.percent, 250);
    final before = zoom.offset;
    zoom.panBy(const Offset(24, 18));
    expect(zoom.offset, isNot(before));
    zoom.reset();
    expect(zoom.scale, 1);
    expect(zoom.offset, Offset.zero);
  });
}
