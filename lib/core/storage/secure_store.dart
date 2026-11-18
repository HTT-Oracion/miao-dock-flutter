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

  /// 键命名空间：原始存储键 = `miao.` + 相对键；对外 API 只收/只返相对键。
  static const String _prefix = 'miao.';

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
  ///
  /// 旧存储里的原始键同样带 [_prefix]，所以按前缀扫描、去掉前缀后走 [read] /
  /// [write]（与日常读写口径一致）；新存储已有非空值时不覆盖。
  Future<void> migrateServiceName() async {
    if (kIsWeb || !(Platform.isMacOS || Platform.isIOS)) return;
    final legacy = Platform.isMacOS
        ? FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false, accountName: _legacyServiceName),
          )
        : FlutterSecureStorage(iOptions: IOSOptions(accountName: _legacyServiceName));
    try {
      final entries = await legacy.readAll();
      for (final entry in entries.entries) {
        final rawKey = entry.key;
        if (!rawKey.startsWith(_prefix) || entry.value.isEmpty) continue;
        final key = rawKey.substring(_prefix.length);
        if (key.isEmpty) continue;
        final exists = await read(key);
        if (exists == null || exists.isEmpty) {
          await write(key, entry.value);
          // 新存储可能静默失败（缺 entitlement）：确认写进去再删旧值，避免丢凭据。
          final saved = await read(key);
          if (saved == null || saved.isEmpty) continue;
        }
        await legacy.delete(key: rawKey);
      }
    } on Object catch (e) {
      // 迁移失败不打断启动：旧数据仍在，用户重新登录即可。
      debugPrint('[secure-store] migrate service name failed: $e');
    }
  }

  final FlutterSecureStorage _storage;

  /// 读取本命名空间内的全部键值（启动扫描用：凭据键随导入的平台动态增长）。
  ///
  /// 契约：返回的键是**相对键**（已去掉 [_prefix]），与 [read] / [write] /
  /// [delete] 的入参口径一致；命名空间外的条目（其他应用或插件写入的键）过滤掉。
  ///
  /// 🔴 不能直接透传 `FlutterSecureStorage.readAll()`：它返回**原始键**（带
  /// `miao.` 前缀），调用方用相对键前缀（如 `music.cookie.`）过滤会永远匹配不到，
  /// 表现为「登录成功、重启掉登录」。
  /// 存储不可用时按「没有凭证」返回空表，与 [read] 的口径一致。
  Future<Map<String, String>> readAll() async {
    try {
      final raw = await _storage.readAll();
      final out = <String, String>{};
      for (final entry in raw.entries) {
        if (!entry.key.startsWith(_prefix)) continue;
        final key = entry.key.substring(_prefix.length);
        if (key.isEmpty) continue;
        out[key] = entry.value;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

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
