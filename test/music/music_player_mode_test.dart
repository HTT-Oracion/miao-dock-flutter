import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/controller/music_player.dart';
import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';

import 'support/demo_music_repository.dart';

import 'package:miao_dock_flutter/features/music/domain/music_models.dart';

void main() {
  test('心动模式首次进入替换队列，退出后恢复原歌单并保持当前曲', () async {
    final repo = DemoMusicRepository();
    final container = ProviderContainer(overrides: [musicRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    final player = container.read(playerProvider.notifier);
    final original = repo.songsByIds(['s1', 's2', 's3', 's4']);

    player.playAll(original, fromLiked: true, title: '我喜欢的音乐');
    for (var i = 0; i < 4; i++) {
      player.cycleMode();
    }
    await Future<void>.delayed(Duration.zero);

    final heartbeat = container.read(playerProvider);
    // 破坏点：心动模式只切图标、不请求相似歌曲重建队列时，本条失败。
    expect(heartbeat.mode, PlayMode.heartbeat);
    expect(heartbeat.queue.map((s) => s.id), isNot(equals(original.map((s) => s.id))));
    expect(heartbeat.queue.first.id, isNot(original.first.id));

    final heartbeatSong = heartbeat.current!;
    player.cycleMode();
    final restored = container.read(playerProvider);
    // 破坏点：离开心动模式不恢复原列表，或恢复时打断当前歌曲时，两条失败。
    expect(restored.mode, PlayMode.list);
    expect(restored.current?.id, heartbeatSong.id);
    expect(restored.queue.map((s) => s.id), containsAll(original.map((s) => s.id)));

    if (restored.playing) player.toggle();
  });

  test('非网易云或非收藏歌单跳过心动档', () {
    final repo = DemoMusicRepository();
    final container = ProviderContainer(overrides: [musicRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    final player = container.read(playerProvider.notifier);

    player.playAll(repo.songsByIds(['s1', 's2']));
    for (var i = 0; i < 4; i++) {
      player.cycleMode();
    }
    expect(container.read(playerProvider).mode, PlayMode.list);
    if (container.read(playerProvider).playing) player.toggle();
  });

  test('顺序播放在队首和队尾都不回卷', () {
    final repo = DemoMusicRepository();
    final container = ProviderContainer(overrides: [musicRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    final player = container.read(playerProvider.notifier);

    player.playAll(repo.songsByIds(['s1', 's2']), start: 0);
    player.cycleMode();
    player.cycleMode();
    player.cycleMode();
    expect(container.read(playerProvider).mode, PlayMode.order);

    player.prevTrack();
    expect(container.read(playerProvider).idx, 0);
    player.nextTrack();
    expect(container.read(playerProvider).idx, 1);
    player.nextTrack();
    expect(container.read(playerProvider).idx, 1);
    expect(container.read(playerProvider).playing, isFalse);
  });

  test('本地歌曲不能加入收藏集合', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const local = MusicSong(
      id: 'local-1',
      title: 'local',
      artist: '',
      album: '',
      duration: Duration.zero,
      platformId: 'local',
    );
    container.read(playerProvider.notifier).toggleLike(local);
    expect(container.read(playerProvider).likedIds, isNot(contains(local.id)));
  });
}
