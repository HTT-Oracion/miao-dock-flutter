import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 阅读器「专注模式」（桌面 F / 顶栏全屏按钮）。
///
/// 语义 = **应用级别的全屏**：窗口真的全屏（`windowManager.setFullScreen`），
/// 同时不渲染壳层（侧栏、工具条、页签），阅读器独占整个屏幕。
///
/// 早先版本用的是 `maximize()`，但 macOS 的 `maximize` 实际是 `zoom:` ——
/// 只是把窗口切到「标准大小」，既不铺满屏幕、也不隐藏菜单栏，
/// 用户看到的就是「变大了但没全屏」。全屏必须走 `setFullScreen`。
final readerFocusProvider = NotifierProvider<ReaderFocusNotifier, bool>(ReaderFocusNotifier.new);

class ReaderFocusNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }

  void toggle() => state = !state;
}

/// 专注模式下窗口是否**真的全屏**（`setFullScreen` 的结果，而不是「请求了全屏」）。
///
/// 用途只有一个：顶部让位。真全屏时系统标题栏 / 红绿灯都被隐藏，
/// 阅读器不需要让位；某些平台全屏失败、退化成普通窗口时，
/// 仍按平台让位（macOS 28），避免红绿灯压住阅读器顶栏。
final readerFullscreenProvider = NotifierProvider<ReaderFullscreenNotifier, bool>(ReaderFullscreenNotifier.new);

class ReaderFullscreenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}
