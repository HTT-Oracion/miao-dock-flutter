import 'package:flutter/foundation.dart';

/// 当前播放曲目（音乐域的只读快照）。
///
/// 设计稿 MiniPlayer / 播放条需要「曲名 + 艺人 + 进度 + 播放态」四项，
/// 这里只放这四项 —— 不预置音乐域其余字段，等 `features/music` 落地再扩。
@immutable
class NowPlaying {
  const NowPlaying({
    required this.title,
    required this.artist,
    required this.position,
    required this.duration,
    required this.playing,
  });

  final String title;
  final String artist;
  final Duration position;
  final Duration duration;
  final bool playing;

  /// 播放进度 0–1；时长为 0 时按 0 处理（不做除零兜底以外的猜测）。
  double get progress =>
      duration.inMilliseconds <= 0 ? 0 : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
}
