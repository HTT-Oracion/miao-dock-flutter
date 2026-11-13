import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// 音乐后台播放初始化（音频会话 + 系统媒体控制）。
///
/// 为什么必须在 `runApp` 之前：`JustAudioBackground.init` 会向系统注册
/// `audio_service` 的后台会话。晚于首帧注册时，Android 拿不到前台服务、
/// iOS 拿不到后台音频通道，切到后台 / 锁屏后播放会被系统直接掐断。
///
/// 平台差异：
/// · Android / iOS / macOS：由 `audio_service` 承担后台会话与通知 / 锁屏控制；
/// · Web / 其它：没有后台概念，跳过（也不该让初始化失败阻断启动）。
Future<void> initMusicBackgroundPlayback() async {
  if (kIsWeb) return;
  if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) return;
  try {
    // 先配音频会话：声明「音乐」用途，系统才会把本 App 当作可后台播放的媒体应用，
    // 并按音乐语义处理来电 / 其它 App 播放时的打断与恢复。
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    // 通知渠道名是系统级展示文案（出现在系统设置里），属于产品固定名而非可切换
    // 界面文案；此处不随界面语言变化，故不走 ARB。
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.miao.dock.audio',
      androidNotificationChannelName: 'Music playback',
      // 让通知常驻：暂停时也不消失，用户能从通知栏直接恢复播放。
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    );
  } on Object catch (e) {
    // 后台能力不可用小问题，不该阻断整个应用启动；前台播放仍可用。
    debugPrint('[bootstrap] just_audio_background init failed: $e');
  }
}
