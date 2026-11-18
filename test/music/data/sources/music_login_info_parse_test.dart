import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/data/sources/js/music_source_dto.dart';

/// `loginInfo` 返回值解析（纯函数，不跑 QuickJS）。
///
/// 破坏点：引擎层手工拼 MusicLoginInfo 时漏掉 avatarUrl → 登录态恢复后头像永远「?」
/// （D-234 的「源回读头像」链路断在引擎解析这一层，JS 源明明回了 avatarUrl）。
void main() {
  test('解析 loggedIn / nick / avatarUrl', () {
    final info = parseMusicLoginInfo(const {
      'loggedIn': true,
      'nick': '狼与羊皮纸',
      'avatarUrl': 'https://p1.music.126.net/avatar.jpg',
    });
    expect(info, isNotNull);
    expect(info!.loggedIn, isTrue);
    expect(info.nick, '狼与羊皮纸');
    expect(info.avatarUrl, 'https://p1.music.126.net/avatar.jpg');
  });

  test('缺省 / 空串字段归一：头像为空给 null，昵称空串保留', () {
    final info = parseMusicLoginInfo(const {'loggedIn': true});
    expect(info!.nick, '');
    expect(info.avatarUrl, isNull);
    final blank = parseMusicLoginInfo(const {'loggedIn': false, 'nick': '  ', 'avatarUrl': '  '});
    expect(blank!.loggedIn, isFalse);
    expect(blank.nick, '');
    expect(blank.avatarUrl, isNull);
  });

  test('非对象返回值 → null（源违反契约，调用方按探测失败处理）', () {
    expect(parseMusicLoginInfo(null), isNull);
    expect(parseMusicLoginInfo('oops'), isNull);
    expect(parseMusicLoginInfo(const [1, 2]), isNull);
  });
}
