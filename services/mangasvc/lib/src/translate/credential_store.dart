/// 在线翻译平台凭证的落盘存储（D-052）。
///
/// ## 为什么落盘
/// 用户定案「多一份 `credentials.json`」：服务端自己持有一份，
/// 好处是**调用翻译时不必每次把 secret 塞进请求体**，
/// 也让「服务端能否翻译」成为一个可查询的状态。
///
/// ## 代价（必须明说）
/// 这是**第二份**密钥副本：App 钥匙串一份、服务端 `<state>/credentials.json` 一份。
/// - 换 key 要清两处，否则会残留一份陈旧密钥；
/// - 磁盘上是明文 JSON（本机应用，没有额外加密层）。
///
/// 因此做了三件事来收敛风险：
/// 1. 文件权限 **0600**（仅属主可读写）；
/// 2. **原子写**（临时文件 + rename），避免半截文件被当成有效凭证；
/// 3. 对外接口**永不回传 secret**，只回 `hasKey` / `hasSecret`。
library;

import 'dart:convert';
import 'dart:io';

class StoredCredential {
  const StoredCredential({required this.platform, required this.appKey, required this.appSecret, this.updatedAt});

  final String platform;
  final String appKey;
  final String appSecret;
  final String? updatedAt;

  bool get usable => appKey.isNotEmpty && appSecret.isNotEmpty;

  /// 对外展示用：**不含密钥本体**。
  Map<String, dynamic> toMaskedJson() => {
    'platform': platform,
    'hasKey': appKey.isNotEmpty,
    'hasSecret': appSecret.isNotEmpty,
    if (updatedAt != null) 'updatedAt': updatedAt,
  };

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'appKey': appKey,
    'appSecret': appSecret,
    if (updatedAt != null) 'updatedAt': updatedAt,
  };
}

class CredentialStore {
  CredentialStore({required this.rootDir});

  final String rootDir;

  File get _file => File('$rootDir${Platform.pathSeparator}credentials.json');

  /// 读取；不存在或损坏 → null（不抛：调用方按「未配置」处理）。
  StoredCredential? read() {
    try {
      if (!_file.existsSync()) return null;
      final m = jsonDecode(_file.readAsStringSync());
      if (m is! Map<String, dynamic>) return null;
      return StoredCredential(
        platform: '${m['platform'] ?? ''}',
        appKey: '${m['appKey'] ?? ''}',
        appSecret: '${m['appSecret'] ?? ''}',
        updatedAt: m['updatedAt'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<StoredCredential> save({required String platform, required String appKey, required String appSecret}) async {
    final cred = StoredCredential(
      platform: platform,
      appKey: appKey.trim(),
      appSecret: appSecret.trim(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await _file.parent.create(recursive: true);
    // 原子写：先写临时文件再 rename，避免「写到一半被读到」。
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(cred.toJson()), flush: true);
    await tmp.rename(_file.path);
    _restrictPermissions(_file);
    return cred;
  }

  Future<void> clear() async {
    if (_file.existsSync()) await _file.delete();
  }

  /// 收紧权限（POSIX 才有 0600；Windows 依赖目录 ACL，这里跳过）。
  void _restrictPermissions(File f) {
    if (Platform.isWindows) return;
    try {
      Process.runSync('chmod', ['600', f.path]);
    } catch (_) {
      // chmod 不可用不影响功能，只是少了一层保护。
    }
  }
}
