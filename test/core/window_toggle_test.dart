import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/window/window_controller.dart';

/// 标题栏第二个按钮（最大化 / 还原）的状态机。
///
/// 破坏点：
/// - 只判 `isMaximized` 不判全屏 → Windows 全屏下点击无效，退不出全屏（用户实际报的 bug）；
/// - 全屏时先 `unmaximize` → 窗口不是最大化态，原生 `Unmaximize()` 里
///   `showCmd != SW_NORMAL` 才发 SC_RESTORE，全屏态下行为不确定；
/// - 已最大化时仍 `maximize()` → 原生 `Maximize()` 在 `SW_MAXIMIZE` 时直接返回，点了没反应。
void main() {
  group('windowToggleAction', () {
    test('窗口化 → 最大化', () {
      expect(windowToggleAction(fullscreen: false, maximized: false), WindowToggleAction.maximize);
    });

    test('已最大化 → 还原', () {
      expect(windowToggleAction(fullscreen: false, maximized: true), WindowToggleAction.unmaximize);
    });

    test('全屏 → 先退出全屏（不看是否最大化）', () {
      // 破坏点：这里若返回 unmaximize，全屏就退不出来。
      expect(windowToggleAction(fullscreen: true, maximized: false), WindowToggleAction.exitFullScreen);
      expect(windowToggleAction(fullscreen: true, maximized: true), WindowToggleAction.exitFullScreen);
    });

    test('全屏优先级高于最大化', () {
      // 同一组 (fullscreen, maximized) 组合里，全屏永远压过最大化。
      final withFullScreen = windowToggleAction(fullscreen: true, maximized: true);
      final withoutFullScreen = windowToggleAction(fullscreen: false, maximized: true);
      expect(withFullScreen, isNot(withoutFullScreen));
    });
  });

  group('readerFocusTopInset 回归（不应被本次改动影响）', () {
    test('全屏时不让位', () {
      expect(readerFocusTopInset(macos: true, fullscreen: true), 0);
      expect(readerFocusTopInset(macos: false, fullscreen: true), 0);
    });
  });
}
