/// 有道智云文本翻译客户端（D-051）。
///
/// 语义逐条对照 `miao-dock/src-tauri/src/mangasvc/translate/youdao.rs`：
/// - 表单提交 `POST {base}/api`；
/// - 响应不是合法 JSON → `TRANSLATE_UPSTREAM_ERROR` 且**带上 HTTP 状态**；
/// - 判成功只看 `errorCode === "0"`（**单判**，大模型接口才双判）；
/// - `errorCode` 缺失按 `"undefined"` 处理（复刻 JS `String(v)`，不是空串）。
///
/// ## 出网可注入
/// [YoudaoTransport] 让测试不发真网络；生产实现留在 `youdao_http.dart`。
library;

import 'dart:convert';

import 'youdao_errors.dart';
import 'youdao_signing.dart';

/// 一次翻译请求（对应 Rust 的 `TranslateReq`，只保留文本接口用得到的字段）。
class YoudaoTranslateRequest {
  const YoudaoTranslateRequest({required this.text, this.from = 'ja', this.to = 'zh-CHS', this.domain, this.vocabId});

  final String text;
  final String from;
  final String to;
  final String? domain;
  final String? vocabId;
}

/// 翻译结果（对应 `TranslateResult`）。
class YoudaoTranslateResult {
  const YoudaoTranslateResult({required this.text, this.langType});

  final String text;
  final String? langType;
}

/// 表单响应。
class YoudaoHttpResponse {
  const YoudaoHttpResponse({required this.status, required this.body});

  final int status;
  final List<int> body;
}

/// 出网抽象：`POST` 表单，返回状态与字节。
typedef YoudaoTransport = Future<YoudaoHttpResponse> Function(String url, Map<String, String> fields);

/// 复刻 JS `String(v)`（业务码比较用）。
///
/// 缺字段 → `"undefined"`，而不是空串 —— 这决定了「未知码」的提示文案。
String jsString(Object? v) {
  if (v == null) return 'undefined';
  if (v is String) return v;
  if (v is num) return v.toString();
  if (v is bool) return v.toString();
  return v.toString();
}

class YoudaoClient {
  YoudaoClient({
    required this.transport,
    required this.baseUrl,
    required this.appKey,
    required this.appSecret,
    DateTime Function()? clock,
    String Function()? saltGenerator,
  }) : _clock = clock ?? (() => DateTime.now()),
       _salt = saltGenerator ?? _uuid4Like;

  final YoudaoTransport transport;
  final String baseUrl;
  final String appKey;
  final String appSecret;
  final DateTime Function() _clock;
  final String Function() _salt;

  /// 文本翻译。
  ///
  /// 🔴 每次调用都重新生成 salt/curtime/sign：重试复用会被上游判 207。
  Future<YoudaoTranslateResult> translateText(YoudaoTranslateRequest req) async {
    if (appKey.isEmpty || appSecret.isEmpty) {
      throw const TranslateError('TRANSLATE_NOT_CONFIGURED', '尚未配置有道翻译密钥（appKey / appSecret），请到「设置 → 翻译来源」填写');
    }

    final sig = signYoudao(
      appKey: appKey,
      appSecret: appSecret,
      q: req.text,
      salt: _salt(),
      curtimeSeconds: _clock().millisecondsSinceEpoch ~/ 1000,
    );

    final fields = <String, String>{
      'q': req.text,
      'from': req.from,
      'to': req.to,
      ...sig.toParams(),
      if (req.domain != null) 'domain': req.domain!,
      if (req.vocabId != null) 'vocabId': req.vocabId!,
    };

    final res = await transport('$baseUrl/api', fields);
    Object? json;
    try {
      json = jsonDecode(utf8.decode(res.body));
    } catch (_) {
      // 破坏点：不区分「不是 JSON」→ 用户只看到「翻译失败」，不知道是网络代理/网关问题。
      throw TranslateError('TRANSLATE_UPSTREAM_ERROR', '有道文本翻译响应不是合法 JSON（HTTP ${res.status}）');
    }
    final map = json is Map<String, dynamic> ? json : <String, dynamic>{};

    // 单判：只有 errorCode。缺失按 "undefined"（复刻 JS String(v)）。
    final code = jsString(map['errorCode']);
    if (code != '0') throw mapYoudaoCode(code, api: 'text');

    final translation = map['translation'];
    final text = translation is List ? translation.whereType<String>().join('\n') : '';
    return YoudaoTranslateResult(text: text, langType: map['l'] is String ? map['l'] as String : null);
  }

  /// 简易 uuid4（只用于 salt，不要求密码学强度）。
  static String _uuid4Like() {
    final rnd = DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(16, '0');
    return '${rnd.substring(0, 8)}-${rnd.substring(8, 12)}-4${rnd.substring(12, 15)}-'
        'a${rnd.substring(15)}';
  }
}
