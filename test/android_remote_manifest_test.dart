import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 正式清单允许局域网 HTTP 远程翻译', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    // 破坏点：权限只写在 debug 清单 → release/profile 无法联网。
    expect(manifest, contains('android.permission.INTERNET'));
    // 破坏点：Android 9+ 默认拦截明文 HTTP → 局域网地址连不上桌面端。
    expect(manifest, contains('android:usesCleartextTraffic="true"'));
  });
}
