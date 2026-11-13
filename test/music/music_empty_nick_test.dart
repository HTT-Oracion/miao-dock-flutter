import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/controller/music_session.dart';

/// 登录后空昵称不崩溃。
///
/// 破坏点：头像区对昵称做 `substring(0, 1)`，空串抛
/// `RangeError (end): Invalid value: Only valid value is 0: 0`——
/// 用户实测：WebView 登录成功（昵称回读前/回读失败）后发现页顶部整条红色错误横幅。
/// 防护收敛在 `MusicAccountState.avatarInitial`，所有取首字的地方统一走它。
void main() {
  MusicAccountState stateOf(String? nick) =>
      MusicAccountState(cur: 'netease', logged: true, nick: nick, extra: const {});

  test('空昵称：头像占位为「?」，不抛 RangeError', () {
    final s = stateOf('');
    // 破坏点：直接 substring(0,1) → RangeError。
    expect(s.avatarInitial, '?');
  });

  test('null 昵称：同样兜底「?」', () {
    expect(stateOf(null).avatarInitial, '?');
  });

  test('正常昵称：取首字符', () {
    expect(stateOf('狼与羊皮纸').avatarInitial, '狼');
    expect(stateOf('tester').avatarInitial, 't');
  });

  test('displayName：已登录返回昵称（可为空），未登录返回空串', () {
    expect(stateOf('abc').displayName, 'abc');
    expect(stateOf('').displayName, '');
    expect(MusicAccountState(cur: 'netease', logged: false, nick: null, extra: const {}).displayName, '');
  });
}
