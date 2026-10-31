import 'package:mangasvc/src/translate/youdao_signing.dart';
import 'package:test/test.dart';

/// D-049：有道签名 v3 必须与 `miao-dock` 的 `youdao.rs` 行为一致。
///
/// 签名算错的症状是上游回 202/207，**不会**告诉你哪里错了 —— 所以这里逐条钉死。
void main() {
  group('truncateInput（按 UTF-16 码元计数）', () {
    test('恰好 20 个码元 → 原样', () {
      const q = '12345678901234567890';
      expect(truncateInput(q), q);
    });

    test('21 个码元 → 前10 + 21 + 后10', () {
      const q = '123456789012345678901';
      // 破坏点：整串返回 → 长文本签名必错（上游 202），本条失败。
      expect(
        truncateInput(q),
        '1234567890'
        '21'
        '2345678901',
      );
    });

    test('中文按码元：BMP 汉字每个 1 码元，20 个以内不截断', () {
      const q = '一二三四五六七八九十';
      expect(q.length, 10);
      expect(truncateInput(q), q);
      // 21 个汉字 → 超过 20 码元，必须截断（不是按「字数」也不是按字节）。
      final long = '一二三四五六七八九十' * 2 + '一';
      expect(long.length, 21);
      expect(truncateInput(long), '${long.substring(0, 10)}21${long.substring(11)}');
    });

    test('emoji 占 2 个码元（这是「按码元不按字符」的关键证据）', () {
      // 15 个 emoji = 30 码元 > 20 → 必须截断；若按字符数算则 15 <= 20 不截断。
      final q = '😀' * 15;
      expect(q.length, 30);
      // 破坏点：改成 runes.length → 返回原串，签名长度与上游不一致，本条失败。
      expect(truncateInput(q), isNot(q));
      // 结构是「前10码元 + 30 + 后10码元」，长度嵌在中间而不是结尾。
      expect(truncateInput(q), contains('30'));
      expect(truncateInput(q).length, 10 + 2 + 10);
    });
  });

  group('signYoudao', () {
    test('签名 = sha256(appKey + 截断文本 + salt + curtime + appSecret)', () {
      final sig = signYoudao(appKey: 'k', appSecret: 's', q: 'hello', salt: 'salt1', curtimeSeconds: 1700000000);
      final expected = sha256Hex(
        'k'
        'hello'
        'salt1'
        '1700000000'
        's',
      );
      // 破坏点：拼接顺序错（如把 secret 放前面）→ 上游 202，本条失败。
      expect(sig.sign, expected);
      expect(sig.curtime, '1700000000');
      expect(sig.signType, 'v3');
      expect(sig.toParams()['salt'], 'salt1');
      expect(sig.toParams().containsKey('signType'), isTrue);
    });

    test('长文本用截断后的 input 参与签名', () {
      const q = 'abcdefghijKLMNOPQRSTuvwxyz'; // 26 码元
      final sig = signYoudao(appKey: 'k', appSecret: 's', q: q, salt: 'x', curtimeSeconds: 1);
      final expected = sha256Hex(
        'k'
        '${truncateInput(q)}'
        'x'
        '1'
        's',
      );
      expect(sig.sign, expected);
    });
  });
}
