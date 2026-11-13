/// 源回读的账户信息（`loginInfo` 能力）。
class MusicLoginInfo {
  const MusicLoginInfo({required this.loggedIn, required this.nick});

  /// Cookie 是否仍有效（false = 失效，调用方撤登录态）。
  final bool loggedIn;

  /// 昵称（空串 = 源没提供，展示兜底「?」）。
  final String nick;
}
