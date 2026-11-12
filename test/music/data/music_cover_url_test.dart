import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/data/api/music_cover_url.dart';

/// 封面地址规范化。
///
/// 破坏点（任意一条都会让对应平台的封面**全部**加载失败，只留渐变占位）：
/// · 不把 `http://` 升为 `https://` → macOS / iOS / Android 默认拒绝明文；
/// · 不替换酷狗 `{size}` 模板占位符；
/// · 把空串当有效 URL 传给 Image.network。
void main() {
  test('http 升 https（三平台都大量返回 http 封面）', () {
    expect(normalizeCoverUrl('http://imge.kugou.com/a.jpg'), 'https://imge.kugou.com/a.jpg');
    expect(normalizeCoverUrl('http://qpic.y.qq.com/b.jpg'), 'https://qpic.y.qq.com/b.jpg');
    expect(normalizeCoverUrl('HTTP://ExAmPle.com/c.jpg'), 'https://ExAmPle.com/c.jpg');
  });

  test('酷狗 {size} 占位符替换', () {
    expect(
      normalizeCoverUrl('http://imge.kugou.com/soft/collection/{size}/x.jpg'),
      'https://imge.kugou.com/soft/collection/300/x.jpg',
    );
    expect(normalizeCoverUrl('https://imge.kugou.com/a/{size}/b.jpg', size: 240), 'https://imge.kugou.com/a/240/b.jpg');
  });

  test('协议相对与空值', () {
    expect(normalizeCoverUrl('//p1.music.126.net/a.jpg'), 'https://p1.music.126.net/a.jpg');
    expect(normalizeCoverUrl(''), isNull);
    expect(normalizeCoverUrl('   '), isNull);
    expect(normalizeCoverUrl(null), isNull);
    // 相对路径无法确定主机，判为不可用而不是拼出错误 URL。
    expect(normalizeCoverUrl('/cover/1.jpg'), isNull);
  });

  test('已是 https 的原样保留', () {
    const u = 'https://p1.music.126.net/x.jpg?param=300y300';
    expect(normalizeCoverUrl(u), u);
  });
}
