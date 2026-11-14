import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/controller/music_player.dart';
import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';

import 'package:miao_dock_flutter/features/music/controller/music_session.dart';

import 'support/demo_music_repository.dart';

/// 心动模式可用性（对齐 miao-dock `canUseHeartbeat`）：
/// **平台能力位（源是否声明 similarSongs）× 队列来自我喜欢的音乐**。
///
/// 破坏点：判据硬编码平台名（`cur == 'netease'`）→ 导入其它支持 similarSongs
/// 的平台时「接口有了、门禁仍拦着」；或反之（按钮显示心动、实际按随机播）。
class _Repo extends DemoMusicRepository {
  _Repo({required this.similar});

  final bool similar;

  @override
  bool get supportsSimilarSongs => similar;
}

void main() {
  /// 播放一段来自「我喜欢的音乐」的队列。
  ///
  /// `likedHeartbeatOn` 是「用户长期开启心动」的偏好（默认关）——自动进档需要它，
  /// 所以先手动开启一次（等于用户点过心动档）。
  PlayMode modeAfterPlay({required bool similar, required bool fromLiked}) {
    final repo = _Repo(similar: similar);
    final c = ProviderContainer(
      overrides: [
        musicRepositoryProvider.overrideWithValue(repo),
        // 🔴 用**非** netease 的平台：硬编码 `cur == 'netease'` 的旧判据在这里必失败。
        musicAccountProvider.overrideWith(_KugouAccount.new),
      ],
    );
    addTearDown(c.dispose);
    final notifier = c.read(playerProvider.notifier);
    final songs = repo.songsByIds(['s1', 's2', 's3']);
    if (similar) {
      // 先播一次并点心动档，把偏好置 true（_canUseHeartbeat 满足时才会生效）。
      notifier.playAll(songs, fromLiked: true, title: '我喜欢的音乐');
      notifier.cycleMode(); // list → one
      notifier.cycleMode(); // one → shuffle
      notifier.cycleMode(); // shuffle → order
      notifier.cycleMode(); // order → heartbeat
    }
    notifier.playAll(songs, fromLiked: fromLiked, title: '队列');
    return c.read(playerProvider).mode;
  }

  test('能力位 true + 队列来自喜欢：自动进心动档', () {
    // 破坏点：硬编码平台名 → 这里拿不到心动档。
    expect(modeAfterPlay(similar: true, fromLiked: true), PlayMode.heartbeat);
  });

  test('能力位 false：即使队列来自喜欢也不进心动档', () {
    expect(modeAfterPlay(similar: false, fromLiked: true), isNot(PlayMode.heartbeat));
  });

  test('队列不来自喜欢：不进心动档', () {
    expect(modeAfterPlay(similar: true, fromLiked: false), isNot(PlayMode.heartbeat));
  });
}

/// 当前平台 = 酷狗（验证判据不依赖平台名）。
class _KugouAccount extends MusicAccountNotifier {
  @override
  MusicAccountState build() => const MusicAccountState(cur: 'kugou', logged: true, nick: 'k', extra: {});
}
