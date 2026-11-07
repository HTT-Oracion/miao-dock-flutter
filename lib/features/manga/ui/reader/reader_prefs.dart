import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/shell_prefs.dart';

/// 阅读器偏好（重设计稿设置抽屉的状态面）：
/// 模式（翻页/条漫）、翻页方向、点按翻页、翻页动画、夜间四档 + 强度、亮度、
/// 舞台背景、显示页码、保持常亮、沉浸式状态栏、预载页数、音量键。
/// 持久化统一走 shell_prefs（`miao.reader-*`）。
enum ReaderMode { paged, webtoon }

enum ReaderNight { off, warm, black, red }

/// 点按翻页收尾动画（拖拽跟手永远是 1:1，不受它影响）。
enum ReaderTurnAnim { none, push, fade }

/// 舞台背景（页间留白颜色）。
enum ReaderStageBg { black, dark, paper, cream }

@immutable
class ReaderPrefs {
  const ReaderPrefs({
    this.mode = ReaderMode.paged,
    this.night = ReaderNight.off,
    this.nightIntensity = 0.4,
    this.brightness = 1.0,
    this.autoScroll = false,
    this.rtl = false,
    this.tapTurn = true,
    this.turnAnim = ReaderTurnAnim.push,
    this.stageBg = ReaderStageBg.black,
    this.pageNum = true,
    this.volumeKeys = true,
    this.awake = false,
    this.immersive = true,
    this.preload = 2,
  });

  final ReaderMode mode;
  final ReaderNight night;

  /// 夜间滤镜强度 0.2–1.0（`.tint` 的 opacity 来源）。
  final double nightIntensity;

  final double brightness;
  final bool autoScroll;

  /// 翻页方向：true = RTL（日漫从右往左）——点按分区与音量键语义镜像。
  final bool rtl;

  /// 左右 30% 点按翻页（关掉后只有中心点按呼出工具栏）。
  final bool tapTurn;

  final ReaderTurnAnim turnAnim;

  final ReaderStageBg stageBg;

  /// 页码 OSD / 自绘状态栏开关。
  final bool pageNum;

  /// 音量键翻页（仅安卓）。
  final bool volumeKeys;

  /// 保持常亮。
  final bool awake;

  /// 沉浸式状态栏。
  final bool immersive;

  /// 前后各预载页数 1–6。
  final int preload;

  ReaderPrefs copyWith({
    ReaderMode? mode,
    ReaderNight? night,
    double? nightIntensity,
    double? brightness,
    bool? autoScroll,
    bool? rtl,
    bool? tapTurn,
    ReaderTurnAnim? turnAnim,
    ReaderStageBg? stageBg,
    bool? pageNum,
    bool? volumeKeys,
    bool? awake,
    bool? immersive,
    int? preload,
  }) => ReaderPrefs(
    mode: mode ?? this.mode,
    night: night ?? this.night,
    nightIntensity: nightIntensity ?? this.nightIntensity,
    brightness: brightness ?? this.brightness,
    autoScroll: autoScroll ?? this.autoScroll,
    rtl: rtl ?? this.rtl,
    tapTurn: tapTurn ?? this.tapTurn,
    turnAnim: turnAnim ?? this.turnAnim,
    stageBg: stageBg ?? this.stageBg,
    pageNum: pageNum ?? this.pageNum,
    volumeKeys: volumeKeys ?? this.volumeKeys,
    awake: awake ?? this.awake,
    immersive: immersive ?? this.immersive,
    preload: preload ?? this.preload,
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
    nightIntensity: readReaderNightIntensity(),
    brightness: readReaderBrightness(),
    tapTurn: readReaderTapTurn(),
    turnAnim: switch (readReaderTurnAnim()) {
      'fade' => ReaderTurnAnim.fade,
      'none' => ReaderTurnAnim.none,
      _ => ReaderTurnAnim.push,
    },
    stageBg: switch (readReaderStageBg()) {
      'dark' => ReaderStageBg.dark,
      'paper' => ReaderStageBg.paper,
      'cream' => ReaderStageBg.cream,
      _ => ReaderStageBg.black,
    },
    pageNum: readReaderPageNum(),
    volumeKeys: readReaderVolumeKeys(),
    awake: readReaderAwake(),
    immersive: readReaderImmersive(),
    preload: readReaderPreload(),
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

  void setNightIntensity(double v) {
    state = state.copyWith(nightIntensity: v.clamp(0.2, 1.0));
    persistReaderNightIntensity(v);
  }

  void setBrightness(double v) {
    state = state.copyWith(brightness: v.clamp(0.2, 1.0));
    persistReaderBrightness(v);
  }

  /// 亮度增量（亮度边缘手势用；连续调用要落到同一个 clamp）。
  void nudgeBrightness(double delta) => setBrightness(state.brightness + delta);

  void toggleAutoScroll() => state = state.copyWith(autoScroll: !state.autoScroll);

  void toggleRtl() => state = state.copyWith(rtl: !state.rtl);

  void toggleTapTurn() {
    state = state.copyWith(tapTurn: !state.tapTurn);
    persistReaderTapTurn(state.tapTurn);
  }

  void setTurnAnim(ReaderTurnAnim anim) {
    state = state.copyWith(turnAnim: anim);
    persistReaderTurnAnim(switch (anim) {
      ReaderTurnAnim.push => 'push',
      ReaderTurnAnim.fade => 'fade',
      ReaderTurnAnim.none => 'none',
    });
  }

  void setStageBg(ReaderStageBg bg) {
    state = state.copyWith(stageBg: bg);
    persistReaderStageBg(switch (bg) {
      ReaderStageBg.black => 'black',
      ReaderStageBg.dark => 'dark',
      ReaderStageBg.paper => 'paper',
      ReaderStageBg.cream => 'cream',
    });
  }

  void togglePageNum() {
    state = state.copyWith(pageNum: !state.pageNum);
    persistReaderPageNum(state.pageNum);
  }

  void toggleVolumeKeys() {
    state = state.copyWith(volumeKeys: !state.volumeKeys);
    persistReaderVolumeKeys(state.volumeKeys);
  }

  void toggleAwake() {
    state = state.copyWith(awake: !state.awake);
    persistReaderAwake(state.awake);
  }

  void toggleImmersive() {
    state = state.copyWith(immersive: !state.immersive);
    persistReaderImmersive(state.immersive);
  }

  void setPreload(int n) {
    state = state.copyWith(preload: n.clamp(1, 6));
    persistReaderPreload(n);
  }
}
