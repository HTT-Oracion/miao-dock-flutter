import 'package:mangasvc/src/translate/youdao_errors.dart';
import 'package:test/test.dart';

/// D-050：错误码映射必须与 miao-dock 的 `errors.rs` 一致。
void main() {
  test('签名失败 → 鉴权族，且文案与上游一致', () {
    final e = mapYoudaoCode('202', api: 'text');
    // 破坏点：映射成通用错误 → 用户无法判断是 key 还是签名的锅，本条失败。
    expect(e.code, 'TRANSLATE_AUTH_FAILED');
    expect(e.message, contains('签名校验失败'));
    expect(e.upstreamCode, '202');
  });

  test('两张表按接口分开（205 只在文本表、902000 只在大模型表）', () {
    // 破坏点：统一用一张表 → 「没开通大模型翻译」会被误报，本条失败。
    expect(mapYoudaoCode('205', api: 'text').code, 'TRANSLATE_AUTH_FAILED');
    expect(mapYoudaoCode('902000', api: 'llm').message, contains('大模型翻译'));
    expect(mapYoudaoCode('205', api: 'llm').code, 'TRANSLATE_UPSTREAM_ERROR');
  });

  test('207 的文案直接指向我们自己的签名复用问题', () {
    final e = mapYoudaoCode('207', api: 'text');
    expect(e.message, contains('salt/curtime'));
  });

  test('未登记码不吞：文案带平台、接口与原始码', () {
    final e = mapYoudaoCode('99999', api: 'llm');
    // 破坏点：只回「翻译失败」→ 排障时拿不到上游原码，本条失败。
    expect(e.code, 'TRANSLATE_UPSTREAM_ERROR');
    expect(e.message, contains('99999'));
    expect(e.message, contains('youdaoZhiYun'));
    expect(e.message, contains('llm'));
  });

  test('toJson 带上原码便于日志', () {
    expect(mapYoudaoCode('401', api: 'text').toJson(), containsPair('code', 'TRANSLATE_QUOTA_EXCEEDED'));
  });
}
