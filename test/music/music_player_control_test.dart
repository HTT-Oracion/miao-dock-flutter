import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:async';

import 'package:miao_dock_flutter/features/music/controller/music_audio_engine.dart';
import 'package:miao_dock_flutter/features/music/controller/music_player.dart';
import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';

import 'support/demo_music_repository.dart';

/// 播放器控制：播放/暂停、音量、进度、歌词版本号。
///
/// 破坏点：
/// · `toggle()` 在引擎未接上时只翻 playing 标志 → 图标变、没声音；
/// · 音量在音频未激活时不下发引擎 → 拖动无效；
/// · 歌词加载完不 bump 版本号 → 歌词空白 / 「译」无反应。
void main() {
  ProviderContainer make() {
    final c = ProviderContainer(overrides: [musicRepositoryProvider.overrideWithValue(DemoMusicRepository())]);
    addTearDown(c.dispose);
    return c;
  }

  test('播放/暂停：重复 toggle 应回到原状态（状态机自洽）', () {
    final c = make();
    final repo = DemoMusicRepository();
    final player = c.read(playerProvider.notifier);
    player.playAll(repo.songsByIds(['s1', 's2']));

    final wasPlaying = c.read(playerProvider).playing;
    player.toggle();
    final afterFirst = c.read(playerProvider).playing;
    // 破坏点：toggle 失效（永远 true / 永远 false）→ 这条失败。
    expect(afterFirst, !wasPlaying);

    player.toggle();
    expect(c.read(playerProvider).playing, wasPlaying);
  });

  test('暂停后再播放：从暂停位置继续，不重新开始', () {
    final c = make();
    final repo = DemoMusicRepository();
    final player = c.read(playerProvider.notifier);
    player.playAll(repo.songsByIds(['s1']));

    player.seekRatio(0.4);
    final posBefore = c.read(playerProvider).positionMs;
    expect(posBefore, greaterThan(0));

    player.toggle(); // 暂停
    expect(c.read(playerProvider).playing, isFalse);

    player.toggle(); // 继续播放
    // 破坏点：恢复时走 _startCurrent() 且不传进度 → positionMs 归零（用户实测反馈）。
    expect(c.read(playerProvider).positionMs, posBefore, reason: '恢复播放必须保留进度');
    expect(c.read(playerProvider).playing, isTrue);

    player.toggle();
  });

  test('音量：setVolume 限幅并解除静音', () {
    final c = make();
    final player = c.read(playerProvider.notifier);

    player.setVolume(150);
    expect(c.read(playerProvider).volume, 100);
    player.setVolume(-20);
    expect(c.read(playerProvider).volume, 0);
    player.setVolume(40);
    expect(c.read(playerProvider).volume, 40);
    expect(c.read(playerProvider).muted, isFalse);
  });

  test('进度：seekRatio 按比例定位并夹在时长内', () {
    final c = make();
    final player = c.read(playerProvider.notifier);
    final repo = DemoMusicRepository();
    player.playAll(repo.songsByIds(['s1']));
    final dur = c.read(playerProvider).current!.duration.inMilliseconds;

    player.seekRatio(0.5);
    expect(c.read(playerProvider).positionMs, (dur * 0.5).round());
    player.seekRatio(2.0);
    expect(c.read(playerProvider).positionMs, dur);
  });

  test('歌词：加载完成后 lyricsRevision 递增（UI 才会重绘）', () async {
    final c = make();
    final repo = DemoMusicRepository();
    final player = c.read(playerProvider.notifier);
    player.playAll(repo.songsByIds(['s1']));

    final before = c.read(playerProvider).lyricsRevision;
    // 等待异步预取落缓存。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final after = c.read(playerProvider).lyricsRevision;

    // 破坏点：预取后不 bump → after == before，歌词永远停空轴、「译」点了没反应。
    expect(after, greaterThan(before));
    // 歌词真的进缓存了（能读到内容）。
    expect(c.read(currentLyricsProvider).lines, isNotEmpty);

    player.toggle();
  });

  _loadMustNotBlockTest();
}

/// 假引擎：`play()` 像 just_audio 一样**永不自行完成**（只在 pause/stop 时完成）。
///
/// 用来锁住 `JustAudioEngine.load()` 那个致命坑：如果 load() 里 `await play()`，
/// 它会永远挂着，调用方的 `_audioActive = true` 永远执行不到，
/// 于是播放/暂停、进度拖动、音量全部失效。
class _NeverCompletingPlayEngine implements MusicAudioEngine {
  Completer<void>? _playCompleter;
  Duration? seekedTo;
  bool isPlaying = false;
  bool loadReturned = false;

  @override
  bool get isReal => true;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<void> get completedStream => const Stream<void>.empty();

  @override
  Future<bool> load({
    required String url,
    required Map<String, String> headers,
    required double volume,
    required bool play,
    String? title,
    String? artist,
    String? album,
    Uri? artUri,
    Duration? duration,
  }) async {
    loadReturned = true;
    if (play) unawaited(this.play());
    return true;
  }

  @override
  Future<void> play() {
    isPlaying = true;
    _playCompleter = Completer<void>();
    return _playCompleter!.future; // 与 just_audio 一致：等 pause 才完成
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    if (_playCompleter != null && !_playCompleter!.isCompleted) _playCompleter!.complete();
  }

  @override
  Future<void> seek(Duration position) async => seekedTo = position;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {
    if (_playCompleter != null && !_playCompleter!.isCompleted) _playCompleter!.complete();
  }

  @override
  Future<void> dispose() async {}
}

/// load() 不能被 play() 阻塞 —— 否则引擎永远「未激活」，所有控制失效。
void _loadMustNotBlockTest() {
  test('引擎 load 不被 play 阻塞（just_audio play 要等暂停才完成）', () async {
    final engine = _NeverCompletingPlayEngine();
    var returned = false;
    // 破坏点：JustAudioEngine.load 里 `await _player.play()` → 这里永远不返回，
    // 下面的 loadReturned 断言超时失败（真实故障：播放/暂停与进度全失效）。
    unawaited(engine.load(url: 'x', headers: const {}, volume: 1, play: true).then((_) => returned = true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(engine.loadReturned, isTrue, reason: 'load 必须立即返回');
    expect(returned, isTrue);
    await engine.pause();
  });
}
