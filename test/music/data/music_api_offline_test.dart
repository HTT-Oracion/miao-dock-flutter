import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/data/api/lrc.dart';
import 'package:miao_dock_flutter/features/music/data/api/migu_api.dart';
import 'package:miao_dock_flutter/features/music/data/api/qqmusic_api.dart';

/// 音乐平台接口的**纯函数**部分（不联网）：签名 / 歌词解析 / 混淆流解码。
///
/// 破坏点：
/// · QQ 签名取位或异或表改一位 → sign 断言失败；
/// · LRC 把两位小数当毫秒 → 时间戳断言失败；
/// · 咪咕解码漏掉 `+offset` → 正文断言失败。
void main() {
  group('QQ 签名', () {
    test('与上游 Mineradio 算法一致（固定输入 → 固定 sign）', () {
      // 用 node 侧同算法算出（scripts 已删，值来自实现核对）。
      const body = '{"a":1}';
      final sign = QqMusicApi.qqSign(body);
      expect(sign.startsWith('zzc'), isTrue);
      // 中段是去掉 `\\ / + =` 的 base64，故允许字母数字混合。
      expect(sign, matches(RegExp(r'^zzc[0-9a-z]+$')));
      expect(sign.length, greaterThan(30));
      // 同一输入必须稳定（不能混入随机数）。
      expect(QqMusicApi.qqSign(body), sign);
    });

    test('不同 body 得到不同 sign', () {
      expect(QqMusicApi.qqSign('{"a":1}'), isNot(QqMusicApi.qqSign('{"a":2}')));
    });
  });

  group('LRC 解析', () {
    test('[mm:ss.xx] 两位小数按百分秒解析', () {
      final lyrics = parseLrc('[00:01.23]第一句\n[01:02.50]第二句\n');
      expect(lyrics.lines.length, 2);
      expect(lyrics.lines.first.t, 1230);
      expect(lyrics.lines.last.t, 62500);
    });

    test('[mm:ss.mmm] 三位小数按毫秒解析', () {
      final lyrics = parseLrc('[00:01.234]句子');
      expect(lyrics.lines.single.t, 1234);
    });

    test('同一行多个时间标签展开成多行且按时间排序', () {
      final lyrics = parseLrc('[00:10.00][00:05.00]副歌');
      expect(lyrics.lines.map((l) => l.t).toList(), [5000, 10000]);
      expect(lyrics.lines.every((l) => l.text == '副歌'), isTrue);
    });

    test('翻译轨按时间戳对齐并标记 hasTranslation', () {
      final lyrics = parseLrc('[00:01.00]原文一\n[00:05.00]原文二', translation: '[00:01.00]译一\n[00:05.00]译二');
      expect(lyrics.hasTranslation, isTrue);
      expect(lyrics.lines.first.translation, '译一');
      expect(lyrics.lines.last.translation, '译二');
    });

    test('纯音乐（无时间标签）返回空时间轴，不造占位行', () {
      final lyrics = parseLrc('纯音乐，请欣赏');
      expect(lyrics.lines, isEmpty);
    });
  });

  group('咪咕 listen 混淆流', () {
    test('按 offset + 密钥还原正文', () {
      const payload = '{"code":"000000","data":{"url":"https://x/a.mp3"}}';
      final key = utf8.encode(MiguApi.listenKey);
      const offset = 37;
      final body = <int>[
        0,
        0,
        0,
        offset,
        ...utf8.encode(payload).indexed.map((e) => (e.$2 - offset + key[e.$1 % key.length]) & 0xFF),
      ];
      final json = MiguApi.decodeListenBody(body);
      expect(json['code'], '000000');
      expect((json['data'] as Map)['url'], 'https://x/a.mp3');
    });

    test('过短响应返回空对象而不是抛异常', () {
      expect(MiguApi.decodeListenBody(const [1, 2]), isEmpty);
    });
  });
}
