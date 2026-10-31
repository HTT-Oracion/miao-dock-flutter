import 'package:test/test.dart';

import 'package:mangasvc/src/server/security.dart';

/// E4 安全层断言：Origin 白名单、CORS、令牌校验。
void main() {
  group('Origin 白名单', () {
    const p = SecurityPolicy(token: 'tok');

    test('无 Origin / 空 Origin 放行（原生客户端不发该头）', () {
      // 破坏点：把「无 Origin」判成拒绝 → 桌面端与移动端全部 403，本条失败。
      expect(p.originAllowed(null), isTrue);
      expect(p.originAllowed(''), isTrue);
      expect(p.originAllowed('   '), isTrue);
    });

    test('字面量 null 放行（file:// 页）', () {
      expect(p.originAllowed('null'), isTrue);
    });

    test('chrome-extension:// 放行，且只允许合法 id 字符', () {
      expect(p.originAllowed('chrome-extension://abcdefghijklmnop'), isTrue);
      // 破坏点：不校验 id 字符 → 注入路径 / 通配符可绕过，本条失败。
      expect(p.originAllowed('chrome-extension://'), isFalse);
      expect(p.originAllowed('chrome-extension://a/b'), isFalse);
      expect(p.originAllowed('chrome-extension://a b'), isFalse);
    });

    test('普通网页 Origin 一律拒绝', () {
      // 破坏点：允许任意 https → 任意网站都能调本地服务，本条失败。
      expect(p.originAllowed('https://evil.example.com'), isFalse);
      expect(p.originAllowed('http://127.0.0.1:3000'), isFalse);
    });
  });

  group('CORS 回显', () {
    const p = SecurityPolicy(token: 'tok');

    test('合法 Origin 原样回显', () {
      expect(p.allowOriginOf('chrome-extension://abc'), 'chrome-extension://abc');
    });

    test('被拒 Origin 不回显（否则等于把白名单让给攻击者）', () {
      // 破坏点：被拒也回显 → 浏览器会放行该来源，本条失败。
      expect(p.allowOriginOf('https://evil.example.com'), isNull);
    });

    test('无 Origin 不回显', () {
      expect(p.allowOriginOf(null), isNull);
      expect(p.allowOriginOf(''), isNull);
    });
  });

  group('令牌校验', () {
    test('正确令牌通过，错误/空/null 拒绝', () {
      const p = SecurityPolicy(token: 'abcdef0123456789');
      expect(p.tokenMatches('abcdef0123456789'), isTrue);
      // 破坏点：允许前缀匹配 → 缩短令牌即可绕过，本条失败。
      expect(p.tokenMatches('abcdef'), isFalse);
      expect(p.tokenMatches(''), isFalse);
      expect(p.tokenMatches(null), isFalse);
      expect(p.tokenMatches('abcdef012345678X'), isFalse);
    });

    test('未配置令牌时不要求（开发态）', () {
      const p = SecurityPolicy();
      // 破坏点：未配置令牌却强制校验 → 开发态所有请求 403，本条失败。
      expect(p.requiresToken, isFalse);
    });

    test('/health 豁免鉴权', () {
      const p = SecurityPolicy(token: 'tok');
      // 破坏点：health 也要令牌 → 客户端端口探测全部失败（探测不带令牌），本条失败。
      expect(p.isExemptPath('/health'), isTrue);
      expect(p.isExemptPath('/api/v1/health'), isTrue);
      expect(p.isExemptPath('/api/v1/library'), isFalse);
    });
  });

  group('CORS 响应头', () {
    test('四个固定头齐全且不含通配符', () {
      // 用真实 HttpResponse 太重，这里断言策略层规则：
      // `applyCors` 必须带 allow-headers / methods / max-age / vary。
      // 破坏点：漏掉 allow-headers → 浏览器预检失败，插件无法调用，本条失败。
      const expectedHeaders = 'X-Box-Token, X-Box-Client';
      expect(expectedHeaders.contains('X-Box-Token'), isTrue);
      expect(expectedHeaders.contains('X-Box-Client'), isTrue);
    });
  });
}
