import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/app/music_autostart.dart';
import 'package:miao_dock_flutter/features/music/controller/music_audio_engine.dart';

/// 桌面音频后端接线（just_audio 在 Windows / Linux 无自带实现）。
///
/// 破坏点（用户实测「无法播放」）：不注册 `just_audio_media_kit` →
/// `AudioPlayer.init` 抛 `MissingPluginException`，点播放直接弹「无法播放」。
/// 单测进程没有 libmpv，无法真实出声；这里锁「什么时候必须注册」的判据，
/// 真机链路由 D-239 台账里的探针实测记录兜底。
void main() {
  test('Windows / Linux 桌面必须注册，Web 与测试进程不注册', () {
    bool need({bool isWeb = false, bool isFlutterTest = false, bool isWindows = true, bool isLinux = false}) =>
        shouldInitDesktopAudioBackend(
          isWeb: isWeb,
          isFlutterTest: isFlutterTest,
          isWindows: isWindows,
          isLinux: isLinux,
        );

    expect(need(), isTrue, reason: 'Windows 桌面缺后端 → 无法播放');
    expect(need(isWindows: false, isLinux: true), isTrue, reason: 'Linux 桌面缺后端 → 无法播放');
    // 破坏点：判据少写平台 / 测试守卫 → 下面几条会红（Web 上 Platform 调用崩溃、
    // 测试进程去加载原生库）。
    expect(need(isWeb: true), isFalse);
    expect(need(isFlutterTest: true), isFalse);
    expect(need(isWindows: false, isLinux: false), isFalse, reason: 'macOS/移动端由 just_audio 自带实现覆盖');
  });

  test('测试进程的音乐播放引擎回落静默实现（不连原生库）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // 破坏点：去掉 FLUTTER_TEST 分支 → 这里会创建 JustAudioEngine，单测环境必炸。
    expect(container.read(musicAudioEngineProvider), isA<SilentAudioEngine>());
  });
}
