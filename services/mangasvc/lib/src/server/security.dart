/// 安全层 —— Origin 白名单、CORS 预检、令牌校验。
///
/// 与原项目 `src-tauri/src/mangasvc.rs` 的 `dispatch_request` 同语义：
/// 1. **Origin 白名单**（只有带 Origin 才校验）：`chrome-extension://*` 或字面量 `null`
///    （Box 桌面端 / 移动端原生请求都不带 Origin）。
/// 2. **CORS 预检**：`OPTIONS` 直接 204。
/// 3. **令牌校验**（`/health` 豁免）：请求头 `X-Box-Token`，定长比较防时序侧信道。
///
/// 🔴 为什么鉴权只在**一处**做：多一处就会漂移出「某个端点忘了校验」。
/// 所以本层在最外层，handler 不再重复判。
library;

import 'dart:io';

import 'http.dart';

/// 服务安全策略。
class SecurityPolicy {
  const SecurityPolicy({this.token, this.allowExtensionOrigins = true, this.allowNullOrigin = true});

  /// 服务令牌；null = 未启用鉴权（**仅开发期**，生产必须给）。
  ///
  /// 取 `MIAO_TOKEN` 环境变量；未设置时由 `server.dart` 生成并落到 `state/token`。
  final String? token;

  /// 是否放行 `chrome-extension://*`（浏览器插件）。
  final bool allowExtensionOrigins;

  /// 是否放行字面量 `null`（桌面端 WebView 的 `file://` 页）。
  final bool allowNullOrigin;

  /// 是否需要校验令牌。
  bool get requiresToken => token != null && token!.isNotEmpty;

  /// Origin 是否被允许。
  ///
  /// - 空 / 无 Origin → 允许（原生客户端不发该头）
  /// - `null` → 看 [allowNullOrigin]
  /// - `chrome-extension://<id>` → 看 [allowExtensionOrigins]，且 id 只允许 `[A-Za-z0-9._-]`
  /// - 其他 → 拒绝
  bool originAllowed(String? origin) {
    if (origin == null) return true;
    final o = origin.trim();
    if (o.isEmpty) return true;
    if (o == 'null') return allowNullOrigin;
    const prefix = 'chrome-extension://';
    if (o.startsWith(prefix)) {
      if (!allowExtensionOrigins) return false;
      final rest = o.substring(prefix.length);
      if (rest.isEmpty) return false;
      return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(rest);
    }
    return false;
  }

  /// 请求该回显的 `Access-Control-Allow-Origin`。
  ///
  /// 无 Origin / 空 / 被拒 → null（**不带**该头）。
  /// 🔴 「被拒也回显」是真实口子：浏览器只认自己发出的 Origin，回显它等于把白名单让给攻击者。
  String? allowOriginOf(String? origin) {
    if (origin == null) return null;
    final o = origin.trim();
    if (o.isEmpty || !originAllowed(o)) return null;
    return o;
  }

  /// 令牌是否匹配。
  ///
  /// **定长比较**（逐字节异或累积）—— 与 Node `timingSafeEqual` 同语义，
  /// 避免按字符提前返回泄露前缀。
  bool tokenMatches(String? provided) {
    final expected = token;
    if (expected == null || provided == null) return false;
    if (provided.isEmpty || expected.length != provided.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ provided.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// 该路径是否免鉴权（只有健康检查）。
  bool isExemptPath(String path) => path == '/health' || path == '/api/v1/health';
}

/// 给响应附加 CORS 头。
///
/// 四个固定头 + 条件性的 allow-origin；**绝不返回 `*`**。
void applyCors(HttpHeaders h, String? allowOrigin) {
  h.set('vary', 'Origin');
  h.set('access-control-allow-headers', 'X-Box-Token, X-Box-Client');
  h.set('access-control-allow-methods', 'GET, POST, OPTIONS');
  h.set('access-control-max-age', '600');
  if (allowOrigin != null) {
    h.set('access-control-allow-origin', allowOrigin);
  }
}

/// 安全层的判定结果。
enum SecurityVerdict {
  /// 放行，进入路由。
  allow,

  /// CORS 预检，已回 204。
  preflight,

  /// Origin 被拒或令牌无效，已回 403。
  denied,
}

/// 对一个请求执行安全判定；已写响应时返回 [SecurityVerdict.preflight] / [SecurityVerdict.denied]。
Future<SecurityVerdict> guardRequest(HttpRequest req, SecurityPolicy policy) async {
  final origin = req.headers.value('origin');
  final allowOrigin = policy.allowOriginOf(origin);

  // 1) Origin 白名单（带 Origin 才校验）
  if (!policy.originAllowed(origin)) {
    stderr.writeln('[mangasvc][security] Origin 拒绝：$origin；${req.method} ${req.uri.path}');
    // 被拒时**不回** allow-origin 头
    await writeErrorCode(req.response, 403, 'PERMISSION_DENIED', '鉴权失败或来源不被允许');
    return SecurityVerdict.denied;
  }

  // 2) CORS 预检
  if (req.method == 'OPTIONS') {
    applyCors(req.response.headers, allowOrigin);
    req.response.statusCode = 204;
    await req.response.close();
    return SecurityVerdict.preflight;
  }

  // 3) 令牌（/health 豁免）
  if (policy.requiresToken && !policy.isExemptPath(req.uri.path)) {
    final provided = req.headers.value('x-box-token');
    if (!policy.tokenMatches(provided)) {
      stderr.writeln('[mangasvc][security] 令牌校验失败：${req.method} ${req.uri.path}');
      await writeErrorCode(req.response, 403, 'PERMISSION_DENIED', '鉴权失败或来源不被允许');
      return SecurityVerdict.denied;
    }
  }

  // 放行：把 allow-origin 挂到响应上（后续 handler 写响应时已带上）
  applyCors(req.response.headers, allowOrigin);
  return SecurityVerdict.allow;
}

/// 读取或生成服务令牌。
///
/// 优先级：`MIAO_TOKEN` 环境变量 > `<root>/state/token` 文件 > 新生成。
/// 生成时写 64 位 hex（与原项目同长度）。
String? resolveToken({required String rootDir, bool enabled = true}) {
  if (!enabled) return null;
  final fromEnv = Platform.environment['MIAO_TOKEN'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

  final file = File('$rootDir/state/token');
  try {
    if (file.existsSync()) {
      final t = file.readAsStringSync().trim();
      if (t.isNotEmpty) return t;
    }
    final token = _randomHex(32);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(token);
    return token;
  } catch (_) {
    // 落盘失败仍可用（只是每次启动换新），不该让服务起不来。
    return _randomHex(32);
  }
}

/// 生成 n 字节随机数的 hex（64 字符 = 32 字节）。
String _randomHex(int bytes) {
  final rnd = List<int>.generate(bytes, (_) => DateTime.now().microsecondsSinceEpoch & 0xFF ^ _seed++);
  return rnd.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

int _seed = 0;
