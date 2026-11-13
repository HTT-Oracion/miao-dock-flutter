import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 真实 Keychain 写读无法在 `flutter test` 里验证（无 MethodChannel 后端，
/// 写读必失败）；显式声明为本机手动验证项，避免假绿。
///
/// 真机验证路径：运行应用 → WebView 登录 → 观察日志。
/// · 成功：无 `[music.auth] keychain read-back empty`
/// · 失败：出现该行，并带 expectedLen（区分「完全没写入」与「被截断」）
///
/// 破坏点记录：macOS 默认 data protection keychain 在缺
/// `keychain-access-groups` entitlement 时**写入静默失败**；
/// 修复为 `MacOsOptions(usesDataProtectionKeychain: false)`
/// （见 `SecureStore._build`，非沙盒本地工具无需该 entitlement）。
void main() {
  test('macOS Keychain 写读为真机手动验证项（CI 环境无法运行）', () {
    // 在 macOS 开发机上提示真实验证方式；其余平台直接跳过。
    if (Platform.isMacOS) {
      // 不 fail：这是手动验证项，避免 CI 常红。
      // ignore: avoid_print
      print(
        '[manual-verify] Keychain 写读需在运行的应用里验证：'
        '登录一次，确认日志无 [music.auth] keychain read-back empty',
      );
    }
    expect(true, isTrue);
  });
}
