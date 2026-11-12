import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/data/api/netease_api.dart';

/// EAPI 加密参数必须与 miao-dock / NeteaseCloudMusicApi 一致。
///
/// 破坏点（都会让服务端回空 body 或「参数错误」，表现为扫码永远不成功）：
/// · 用 base64 而非大写十六进制 → 解密失败；
/// · 摘要串拼错（少 `nobody` / `use` / `md5forencrypt`）→ 签名不匹配；
/// · AES 模式/填充用错（CBC / 无 PKCS7）→ 服务端拒绝。
void main() {
  const eapiKey = 'e82ckenh8dichen8';

  /// 参考实现的独立还原（不调用被测方法），用于交叉验证。
  String reference(String path, Map<String, dynamic> payload) {
    final text = jsonEncode(payload);
    final digest = md5.convert(utf8.encode('nobody${path}use${text}md5forencrypt')).toString();
    final raw = '$path-36cd479b6b5-$text-36cd479b6b5-$digest';
    final e = enc.Encrypter(enc.AES(enc.Key.fromUtf8(eapiKey), mode: enc.AESMode.ecb, padding: 'PKCS7'));
    return e
        .encrypt(raw, iv: enc.IV.fromLength(0))
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  test('EAPI 加密输出与参考实现一致（大写 hex）', () {
    const path = '/api/login/qrcode/unikey';
    final payload = {'type': 1};
    final actual = NeteaseApi.eapiParams(path, payload);

    // 破坏点：换成 base64 / 改摘要串 / 改 AES 模式 → 与参考值不等。
    expect(actual, reference(path, payload));
    expect(RegExp(r'^[0-9A-F]+$').hasMatch(actual), isTrue);
  });

  test('EAPI 请求头必须带稳定非空 deviceId', () {
    final h1 = NeteaseApi.eapiHeader();
    final h2 = NeteaseApi.eapiHeader();

    // 破坏点：deviceId 传空串（修复前就是这样）→ 扫码确认后服务端回 8821 风控。
    expect('${h1['deviceId']}'.trim(), isNotEmpty);
    expect(h1['deviceId'], h2['deviceId'], reason: '同一进程内必须稳定');
    // MUSIC_U 必须留空，否则顶掉 Cookie 头里的真实登录态。
    expect(h1['MUSIC_U'], '');
    expect(h1['os'], 'iPhone OS');
  });

  test('EAPI 加密确定性，且随 payload 变化', () {
    const path = '/api/login/qrcode/client/login';
    final a = NeteaseApi.eapiParams(path, {'key': 'k1', 'type': 1});
    final b = NeteaseApi.eapiParams(path, {'key': 'k1', 'type': 1});
    final c = NeteaseApi.eapiParams(path, {'key': 'k2', 'type': 1});

    // 破坏点：引入随机 IV → a != b。
    expect(a, b);
    expect(a, isNot(c));
    // AES 分组对齐：密文长度是 16 字节（32 个 hex 字符）的整数倍。
    expect(a.length % 32, 0);
  });
}
