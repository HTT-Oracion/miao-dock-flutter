import 'package:miao_dock_flutter/features/music/domain/js_music_source.dart';
import 'package:miao_dock_flutter/features/music/domain/music_login_info.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';
import 'package:miao_dock_flutter/features/music/domain/music_source_engine.dart';

/// 可编程音乐源引擎替身（不跑 QuickJS）。
///
/// 登录收口用例靠它制造「源 loginInfo 的三态」：有效 / 明确未完成 / 校验异常。
class StubMusicSourceEngine implements MusicSourceEngine {
  StubMusicSourceEngine({this.loginResult, this.loginThrows = false});

  /// `loginInfo` 返回值（null = 引擎拿不到对象，按探测失败处理）。
  MusicLoginInfo? loginResult;

  /// true = `loginInfo` 抛异常（模拟网络 / 引擎异常）。
  bool loginThrows;

  /// `loginInfo` 被调用次数（校验节流断言用）。
  int probes = 0;

  /// 最后一次注入引擎的会话 Cookie。
  String? injectedCookie;

  /// 最后一次被清除会话的源 id（退出登录 / 凭据失效断言用）。
  String? clearedSourceId;

  @override
  Future<void> ensureLoaded(JsMusicSource source) async {}

  @override
  Future<void> setSessionCookie(JsMusicSource source, String cookie) async => injectedCookie = cookie;

  @override
  Future<void> clearSessionCookie(JsMusicSource source) async {
    clearedSourceId = source.id;
    injectedCookie = null;
  }

  @override
  Future<MusicLoginInfo?> loginInfo(JsMusicSource source) async {
    probes += 1;
    if (loginThrows) throw StateError('probe unavailable');
    return loginResult;
  }

  @override
  Future<List<MusicSong>> searchSongs(
    JsMusicSource source, {
    required String keyword,
    int limit = 30,
    int offset = 0,
  }) async => const [];

  @override
  Future<String?> songUrl(JsMusicSource source, {required MusicSong song, required QualityTier quality}) async => null;

  @override
  Future<List<MusicPlaylist>> userPlaylists(JsMusicSource source) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName} not stubbed');
}
