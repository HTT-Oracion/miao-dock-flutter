import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;

/// 播放引擎抽象：把「有没有真实音频后端」与播放器状态机解耦。
///
/// 为什么需要这一层：
/// · 桌面 / 移动真机要 just_audio 出声；
/// · widget 测试没有音频插件（`AudioPlayer` 的 MethodChannel 未注册，`setUrl` 必失败），
///   若状态机直接绑死 just_audio，任何「播放」用例都会因插件缺失而红；
/// · 少数机器没有可用音频后端时也要能继续用界面（降级为静默的模拟进度）。
abstract interface class MusicAudioEngine {
  /// 是否接上了真实音频（false = 调用方用 500ms 模拟时钟推进）。
  bool get isReal;

  /// 加载并播放；返回 false 表示这次没接上（调用方自行决定停住还是模拟）。
  Future<bool> load({
    required String url,
    required Map<String, String> headers,
    required double volume,
    required bool play,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> stop();
  Future<void> dispose();

  /// 播放位置流（只有真实引擎会发；模拟引擎为空流）。
  Stream<Duration> get positionStream;

  /// 播完一帧的流。
  Stream<void> get completedStream;
}

/// just_audio 实现（桌面 / 移动真机）。
class JustAudioEngine implements MusicAudioEngine {
  JustAudioEngine() : _player = ja.AudioPlayer() {
    _position = _player.positionStream;
    _completed = _player.playerStateStream.where((s) => s.processingState == ja.ProcessingState.completed).map((_) {});
  }

  final ja.AudioPlayer _player;
  late final Stream<Duration> _position;
  late final Stream<void> _completed;

  @override
  bool get isReal => true;

  @override
  Stream<Duration> get positionStream => _position;

  @override
  Stream<void> get completedStream => _completed;

  @override
  Future<bool> load({
    required String url,
    required Map<String, String> headers,
    required double volume,
    required bool play,
  }) async {
    await _player.setAudioSource(ja.AudioSource.uri(Uri.parse(url), headers: headers));
    await _player.setVolume(volume);
    if (play) await _player.play();
    return true;
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// 静默引擎：没有音频后端 / 测试环境使用。
///
/// `load` 返回 false，让播放器退回模拟时钟：进度、切歌、模式等交互照常可验证，
/// 只是没有声音。这不是「假装在播」—— 调用方拿到 false 后会把 UI 的播放态
/// 与真实能力对齐（见 `PlayerNotifier._loadAudio`）。
class SilentAudioEngine implements MusicAudioEngine {
  @override
  bool get isReal => false;

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<void> get completedStream => const Stream.empty();

  @override
  Future<bool> load({
    required String url,
    required Map<String, String> headers,
    required double volume,
    required bool play,
  }) async => false;

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// 引擎装配：默认 just_audio；创建失败（无音频后端）回落静默引擎。
///
/// `flutter test` 进程里没有音频插件：直接给静默引擎，避免用例去连真实 CDN、
/// 也避免 `AudioPlayer` 在无插件环境抛 MethodChannel 断言。判据与
/// `core/storage/shell_prefs.dart` 的测试隔离同一口径（`FLUTTER_TEST`）。
final musicAudioEngineProvider = Provider<MusicAudioEngine>((ref) {
  final engine = _createEngine();
  ref.onDispose(() => unawaited(engine.dispose()));
  return engine;
});

MusicAudioEngine _createEngine() {
  if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') return SilentAudioEngine();
  try {
    return JustAudioEngine();
  } on Object {
    return SilentAudioEngine();
  }
}
