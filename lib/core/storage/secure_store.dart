import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 敏感凭证存储（D-047）。
///
/// ## 为什么不用偏好文件
/// 有道智云的 `appSecret` 是**凭据**，不是配置：偏好文件是明文 JSON，
/// 任何有读权限的进程都能拿到。这里走系统凭据存储：
/// macOS/iOS → Keychain，Windows → Credential Manager，
/// Linux → libsecret，Android → KeyStore，Web → WebCrypto。
///
/// ## 为什么要薄封装
/// AGENTS §3：第三方类型不得泄漏到业务层。上层只认 [SecureStore] 的方法，
/// 换实现（例如以后换成自建加密）不用改调用方。
class SecureStore {
  /// 用默认平台选项。
  ///
  /// 不传 `mOptions` / `aOptions`：v11 起这两组的字段名与旧版不同，
  /// 而我们也不需要改默认行为 —— 少一层自定义就少一处版本耦合。
  SecureStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _prefix = 'miao.';

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: '$_prefix$key');
    } catch (_) {
      // 平台后端不可用（例如 Linux 缺 libsecret）时按「没有凭证」处理，
      // 让调用方能引导用户去填写，而不是整个设置页崩掉。
      return null;
    }
  }

  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: '$_prefix$key', value: value);
    } catch (_) {
      // 写入失败不抛：调用方会在下次读取时发现没存上。
    }
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: '$_prefix$key');
    } catch (_) {
      // 同上。
    }
  }
}
