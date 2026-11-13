import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
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
  /// 钥匙串服务名（kSecAttrService）：系统弹窗与「钥匙串访问」里显示的名字。
  static const _kcServiceName = '喵坞 MiaoDock';

  /// macOS 必须禁用 data protection keychain。
  ///
  /// 🔴 默认的 data protection keychain 需要 `keychain-access-groups` entitlement
  /// （Keychain Sharing capability）；没有它时**写入静默失败**——调用方拿到成功
  /// 回执但 Keychain 里什么都没有，表现为「登录后重启就掉线」/「回读校验失败」。
  /// 本应用是非沙盒的本地工具，不走 Mac App Store，也没有 App Group，
  /// 按插件 README 的口径关闭 data protection，回落传统 Keychain，无需任何 entitlement。
  SecureStore({FlutterSecureStorage? storage}) : _storage = storage ?? _build();

  static FlutterSecureStorage _build() {
    if (kIsWeb || !Platform.isMacOS) return _forIos();
    return const FlutterSecureStorage(
      mOptions: MacOsOptions(
        // 🔴 非 data protection keychain：默认档需要 keychain-access-groups
        // entitlement，缺失时写入静默失败（D-215）。
        usesDataProtectionKeychain: false,
        // 钥匙串条目归属「喵坞」：系统授权弹窗与「钥匙串访问」里显示应用名而非技术名。
        accountName: _kcServiceName,
      ),
    );
  }

  static FlutterSecureStorage _forIos() {
    if (!Platform.isIOS) return const FlutterSecureStorage();
    return const FlutterSecureStorage(iOptions: IOSOptions(accountName: _kcServiceName));
  }

  /// 旧服务名（插件默认）：迁移用 —— 改名后旧条目按新名查不到，需搬一次。
  static const _legacyServiceName = 'flutter_secure_storage_service';

  /// 把旧服务名下的凭据搬到新服务名（一次迁移；读不到旧值就跳过）。
  ///
  /// 为什么必须搬：钥匙串按 `kSecAttrService` 区分条目，直接改名等于换了个
  /// 空保险箱 —— 用户之前登录的 Cookie 全部「消失」，表现为重启后掉登录。
  Future<void> migrateServiceName() async {
    if (kIsWeb || !(Platform.isMacOS || Platform.isIOS)) return;
    final legacy = Platform.isMacOS
        ? FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false, accountName: _legacyServiceName),
          )
        : FlutterSecureStorage(iOptions: IOSOptions(accountName: _legacyServiceName));
    const keys = ['music.cookie.netease', 'music.cookie.kugou', 'music.cookie.qq', 'music.cookie.migu'];
    try {
      for (final k in keys) {
        final v = await legacy.read(key: k);
        if (v == null || v.isEmpty) continue;
        final exists = await _storage.read(key: k);
        if (exists == null || exists.isEmpty) {
          await _storage.write(key: k, value: v);
        }
        await legacy.delete(key: k);
      }
    } on Object catch (e) {
      // 迁移失败不打断启动：旧数据仍在，用户重新登录即可。
      debugPrint('[secure-store] migrate service name failed: $e');
    }
  }

  final FlutterSecureStorage _storage;

  static const String _prefix = 'miao.';

  /// 读取全部键值（启动扫描用：凭据键随导入的平台动态增长）。
  Future<Map<String, String>> readAll() => _storage.readAll();

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
