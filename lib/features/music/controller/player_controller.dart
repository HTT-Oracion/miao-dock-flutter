import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/now_playing.dart';

/// 当前播放曲目。
///
/// 音乐域（`just_audio` 接入 / 四平台音源）尚未落地，故**当前恒为 null**：
/// 不预置任何假曲目 —— 侧栏 MiniPlayer 在 null 时渲染空态（design.html §07 空态规则）。
/// 接入真实播放时只替换本 provider 的实现，UI 不改。
final nowPlayingProvider = Provider<NowPlaying?>((ref) => null);
