import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miao_dock_flutter/features/manga/controller/drop_controller.dart';

/// D-146：移动端选择结果必须先落盘成真实路径，否则被扩展名过滤丢掉。
void main() {
  test('真实图片路径可加入', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(dropController.notifier).addFiles(['/tmp/a/001.png', '/tmp/a/002.jpg']);
    expect(c.read(dropController).files.length, 2);
  });

  test('content:// URI 无扩展名 → 被过滤（证明必须 materialize）', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // 破坏点：把 content URI 直接丢给 addFiles → 列表为空，用户「选了没反应」。
    c.read(dropController.notifier).addFiles(['content://media/external/images/media/12345']);
    expect(c.read(dropController).files, isEmpty);
  });
}
