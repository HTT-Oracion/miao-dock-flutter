import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_store.dart';
import '../../manga/controller/queue_controller.dart';

/// 在线翻译平台（D-047）。
///
/// 当前只有有道智云 —— 原项目 `miao-dock` 的在线 API 也只接了这一个。
/// 加平台时在这里扩，`id` 就是引擎侧的 translator 名。
enum TranslatePlatform {
  /// id 用 `youdaoZhiYun` 而**不是** `youdao`：
  /// 引擎自带一个同名翻译器（读环境变量、只有文本接口），两者必须能区分。
  youdaoZhiYun('youdaoZhiYun');

  const TranslatePlatform(this.id);

  /// 引擎侧的 translator 名。
  final String id;
}

/// 一组平台凭证。
class PlatformCredential {
  const PlatformCredential({this.appKey = '', this.appSecret = ''});

  final String appKey;
  final String appSecret;

  bool get usable => appKey.trim().isNotEmpty && appSecret.trim().isNotEmpty;

  PlatformCredential copyWith({String? appKey, String? appSecret}) =>
      PlatformCredential(appKey: appKey ?? this.appKey, appSecret: appSecret ?? this.appSecret);
}

/// 凭证仓库：**钥匙串**，不是偏好文件。
final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final credentialProvider = AsyncNotifierProvider<CredentialNotifier, Map<TranslatePlatform, PlatformCredential>>(
  CredentialNotifier.new,
);

class CredentialNotifier extends AsyncNotifier<Map<TranslatePlatform, PlatformCredential>> {
  String _keyOf(TranslatePlatform p, String field) => 'cred.${p.id}.$field';

  @override
  Future<Map<TranslatePlatform, PlatformCredential>> build() async {
    final store = ref.watch(secureStoreProvider);
    final out = <TranslatePlatform, PlatformCredential>{};
    for (final p in TranslatePlatform.values) {
      out[p] = PlatformCredential(
        appKey: await store.read(_keyOf(p, 'key')) ?? '',
        appSecret: await store.read(_keyOf(p, 'secret')) ?? '',
      );
    }
    return out;
  }

  /// 保存凭证：**同时写两处**（D-052）。
  ///
  /// 1. 本机钥匙串（App 自用，重启后仍可回填界面）；
  /// 2. 服务端 `<state>/credentials.json`（翻译时服务端直接取用，不必每次随请求传）。
  ///
  /// 两处不一致的后果是「界面显示已配置，但翻译报未配置」——
  /// 所以服务端写入失败时**要让它可见**，不要吞掉。
  Future<String?> save(TranslatePlatform platform, PlatformCredential cred) async {
    final store = ref.read(secureStoreProvider);
    await store.write(_keyOf(platform, 'key'), cred.appKey.trim());
    await store.write(_keyOf(platform, 'secret'), cred.appSecret.trim());
    state = AsyncValue.data({...(state.value ?? const {}), platform: cred});

    try {
      await ref
          .read(mangaSvcClientProvider)
          .putTranslateCredentials(platform: platform.id, appKey: cred.appKey.trim(), appSecret: cred.appSecret.trim());
      return null;
    } catch (e) {
      return '$e';
    }
  }
}
