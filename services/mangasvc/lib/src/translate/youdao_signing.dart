/// 有道智云签名 v3（D-049）。
///
/// ## 来源
/// 逐行对照 `miao-dock/src-tauri/src/mangasvc/translate/youdao.rs`（`sign_fields` /
/// `truncate_input` / `sha256_hex`），要求**行为完全一致**。
///
/// ## 只做纯计算
/// 本文件不碰网络、不读环境：签名是最容易算错、也最容易被测试钉死的部分，
/// 单独放一层，HTTP 与重试逻辑在别处。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// `input` 截断（有道方案 §5.1）。
///
/// - `len(q) <= 20` → q 原样；
/// - 否则 → `q前10 + len(q) + q后10`。
///
/// 🔴 **len 按 UTF-16 码元计数**（不是 Unicode 字符数，也不是字节数）。
/// 这是照抄官方 JS demo 的语义：`String.length` 在 JS 里就是码元数。
/// 用 `q.length`（Dart 同样是码元数）与之等价；**不要**改成 `runes.length`。
String truncateInput(String q) {
  if (q.length <= 20) return q;
  final head = q.substring(0, 10);
  final tail = q.substring(q.length - 10);
  return '$head${q.length}$tail';
}

String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

/// 一次签名所需的五件套。
class YoudaoSignature {
  const YoudaoSignature({
    required this.appKey,
    required this.salt,
    required this.curtime,
    required this.sign,
    this.signType = 'v3',
  });

  final String appKey;
  final String salt;
  final String curtime;
  final String sign;
  final String signType;

  /// 查询参数（文本接口按 `application/x-www-form-urlencoded` 提交）。
  Map<String, String> toParams() => {
    'appKey': appKey,
    'salt': salt,
    'curtime': curtime,
    'signType': signType,
    'sign': sign,
  };
}

/// 生成签名。
///
/// `sign = sha256(appKey + truncate(q) + salt + curtime + appSecret)`
///
/// 🔴 **每次请求（含重试）都必须重新调用**：有道用 `salt + curtime` 防重放，
/// 同一签名第二次发出去**必然** 207。
YoudaoSignature signYoudao({
  required String appKey,
  required String appSecret,
  required String q,
  required String salt,
  required int curtimeSeconds,
}) {
  final input = truncateInput(q);
  final curtime = '$curtimeSeconds';
  final sign = sha256Hex('$appKey$input$salt$curtime$appSecret');
  return YoudaoSignature(appKey: appKey, salt: salt, curtime: curtime, sign: sign);
}
