import 'package:miao_dock_flutter/features/music/controller/music_session.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';

class LoggedInMusicAccount extends MusicAccountNotifier {
  @override
  MusicAccountState build() =>
      const MusicAccountState(cur: MusicPlatform.netease, logged: true, nick: 'tester', extra: {});
}

/// 已登录但**昵称为空**：WebView 登录成功后昵称回读尚未完成 / 回读失败的真实状态。
///
/// 破坏点：头像区对空昵称做 `substring(0, 1)` → 渲染时抛 RangeError（用户实测：
/// 登录后发现页顶部出现红色错误横幅）。
class LoggedInEmptyNickAccount extends MusicAccountNotifier {
  @override
  MusicAccountState build() => const MusicAccountState(cur: MusicPlatform.netease, logged: true, nick: '', extra: {});
}
