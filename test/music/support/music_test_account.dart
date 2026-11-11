import 'package:miao_dock_flutter/features/music/controller/music_session.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';

class LoggedInMusicAccount extends MusicAccountNotifier {
  @override
  MusicAccountState build() =>
      const MusicAccountState(cur: MusicPlatform.netease, logged: true, nick: 'tester', extra: {});
}
