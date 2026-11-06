import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/shell_prefs.dart';

/// 阅读器偏好（重设计稿设置抽屉的状态面）：
/// 模式（翻页/条漫）、夜间三档、亮度、自动滚动。持久化走 shell_prefs。
enum ReaderMode { paged, webtoon }

enum ReaderNight { off, warm, black, red }

@immutable
class ReaderPrefs {
  const ReaderPrefs({
    this.mode = ReaderMode.paged,
    this.night = ReaderNight.off,
    this.brightness = 1.0,
    this.autoScroll = false,
    this.rtl = false,
  });

  final ReaderMode mode;
  final ReaderNight night;
  final double brightness;
  final bool autoScroll;

  /// 翻页方向：true = RTL（日漫从右往左）——点按分区与音量键语义镜像。
  final bool rtl;

  ReaderPrefs copyWith({ReaderMode? mode, ReaderNight? night, double? brightness, bool? autoScroll, bool? rtl}) =>
      ReaderPrefs(
        mode: mode ?? this.mode,
        night: night ?? this.night,
        brightness: brightness ?? this.brightness,
        autoScroll: autoScroll ?? this.autoScroll,
        rtl: rtl ?? this.rtl,
      );
}

final readerPrefsProvider = NotifierProvider<ReaderPrefsNotifier, ReaderPrefs>(ReaderPrefsNotifier.new);

class ReaderPrefsNotifier extends Notifier<ReaderPrefs> {
  @override
  ReaderPrefs build() => ReaderPrefs(
    mode: readReaderMode() == 'webtoon' ? ReaderMode.webtoon : ReaderMode.paged,
    night: switch (readReaderNight()) {
      'warm' => ReaderNight.warm,
      'black' => ReaderNight.black,
      'red' => ReaderNight.red,
      _ => ReaderNight.off,
    },
    brightness: readReaderBrightness(),
  );

  void setMode(ReaderMode mode) {
    state = state.copyWith(mode: mode);
    persistReaderMode(mode == ReaderMode.webtoon ? 'webtoon' : 'paged');
  }

  void setNight(ReaderNight night) {
    state = state.copyWith(night: night);
    persistReaderNight(switch (night) {
      ReaderNight.warm => 'warm',
      ReaderNight.black => 'black',
      ReaderNight.red => 'red',
      _ => 'off',
    });
  }

  void setBrightness(double v) {
    state = state.copyWith(brightness: v.clamp(0.2, 1.0));
    persistReaderBrightness(v);
  }

  void toggleAutoScroll() => state = state.copyWith(autoScroll: !state.autoScroll);

  void toggleRtl() => state = state.copyWith(rtl: !state.rtl);
}
