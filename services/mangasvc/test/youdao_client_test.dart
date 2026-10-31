import 'dart:convert';

import 'package:mangasvc/src/translate/youdao_client.dart';
import 'package:mangasvc/src/translate/youdao_errors.dart';
import 'package:test/test.dart';

/// D-051：文本接口的成功判定与非 JSON 处理，必须与 miao-dock 一致。
void main() {
  YoudaoClient client(Future<YoudaoHttpResponse> Function(String, Map<String, String>) t) => YoudaoClient(
    transport: t,
    baseUrl: 'https://example.test',
    appKey: 'k',
    appSecret: 's',
    clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    saltGenerator: () => 'fixed-salt',
  );

  test('errorCode=0 → 返回译文，且表单里带齐签名五件套', () async {
    late Map<String, String> sent;
    final c = client((url, fields) async {
      sent = fields;
      expect(url, 'https://example.test/api');
      return YoudaoHttpResponse(status: 200, body: utf8.encode('{"errorCode":"0","translation":["你好"]}'));
    });

    final r = await c.translateText(const YoudaoTranslateRequest(text: 'こんにちは'));
    expect(r.text, '你好');
    // 破坏点：漏 signType/salt → 上游 202（签名校验失败），本条失败。
    expect(sent['signType'], 'v3');
    expect(sent['salt'], 'fixed-salt');
    expect(sent['curtime'], '1700000000');
    expect(sent.containsKey('sign'), isTrue);
    expect(sent['from'], 'ja');
    expect(sent['to'], 'zh-CHS');
  });

  test('errorCode 非 0 → 映射成统一错误并保留原码', () async {
    final c = client((_, _) async => YoudaoHttpResponse(status: 200, body: utf8.encode('{"errorCode":"202"}')));
    // 破坏点：当成成功返回空串 → 用户拿到空译文却以为翻译完成，本条失败。
    await expectLater(
      c.translateText(const YoudaoTranslateRequest(text: 'x')),
      throwsA(isA<TranslateError>().having((e) => e.code, 'code', 'TRANSLATE_AUTH_FAILED')),
    );
  });

  test('响应不是 JSON → 报上游错误并带 HTTP 状态', () async {
    final c = client((_, _) async => YoudaoHttpResponse(status: 502, body: utf8.encode('<html>')));
    await expectLater(
      c.translateText(const YoudaoTranslateRequest(text: 'x')),
      throwsA(isA<TranslateError>().having((e) => e.message, 'msg', contains('502'))),
    );
  });

  test('errorCode 缺失 → 按 "undefined" 走未登记码分支', () async {
    final c = client((_, _) async => YoudaoHttpResponse(status: 200, body: utf8.encode('{}')));
    await expectLater(
      c.translateText(const YoudaoTranslateRequest(text: 'x')),
      throwsA(isA<TranslateError>().having((e) => e.message, 'msg', contains('undefined'))),
    );
  });

  test('未配置密钥 → 直接报 TRANSLATE_NOT_CONFIGURED，不发请求', () async {
    var called = false;
    final c = YoudaoClient(
      transport: (_, _) async {
        called = true;
        return const YoudaoHttpResponse(status: 200, body: []);
      },
      baseUrl: 'https://example.test',
      appKey: '',
      appSecret: '',
    );
    await expectLater(
      c.translateText(const YoudaoTranslateRequest(text: 'x')),
      throwsA(isA<TranslateError>().having((e) => e.code, 'code', 'TRANSLATE_NOT_CONFIGURED')),
    );
    expect(called, isFalse);
  });
}
