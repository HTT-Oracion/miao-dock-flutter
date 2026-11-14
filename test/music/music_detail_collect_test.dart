import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/domain/music_models.dart';

/// 收藏按钮显隐（用户口径，唯一判据 `shouldShowCollectButton`）：
/// 【我喜欢的音乐】与【我创建的歌单】都不显示收藏 —— 收藏「喜欢」本身 /
/// 收藏自己创建的歌单没有语义；只有「收藏来的歌单」与「榜单」可收藏。
///
/// 破坏点：判据改成「歌单一律可收藏」→ 系统歌单 / 自建歌单也出现收藏按钮。
MusicPlaylist _playlist({required bool special, required bool subscribed}) =>
    MusicPlaylist(id: 'p1', name: '测试歌单', trackCount: 3, seed: '测试歌单', special: special, subscribed: subscribed);

void main() {
  test('【我喜欢的音乐】（special）：不显示收藏', () {
    // 破坏点：不判 special → 出现「收藏」。
    expect(shouldShowCollectButton(MusicSourceKind.playlist, _playlist(special: true, subscribed: false)), isFalse);
  });

  test('【我创建的歌单】（!subscribed）：不显示收藏', () {
    // 破坏点：不判 subscribed → 自建歌单出现「收藏」。
    expect(shouldShowCollectButton(MusicSourceKind.playlist, _playlist(special: false, subscribed: false)), isFalse);
  });

  test('收藏来的歌单（subscribed）：显示收藏', () {
    expect(shouldShowCollectButton(MusicSourceKind.playlist, _playlist(special: false, subscribed: true)), isTrue);
  });

  test('榜单：显示收藏', () {
    expect(shouldShowCollectButton(MusicSourceKind.chart, _playlist(special: false, subscribed: false)), isTrue);
  });

  test('每日推荐：不显示收藏（不是歌单）', () {
    expect(shouldShowCollectButton(MusicSourceKind.daily, _playlist(special: false, subscribed: false)), isFalse);
  });
}
