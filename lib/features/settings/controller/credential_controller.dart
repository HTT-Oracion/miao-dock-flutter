import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_store.dart';

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

  /// 保存凭证：**只写本机钥匙串**（D-054 定案）。
  ///
  /// 服务端不落盘：调用 `/translate/text` 时把凭证放进请求体，用完即弃。
  /// 唯一事实源就是这里，避免出现「两份密钥、换 key 只清一处」。
  Future<void> save(TranslatePlatform platform, PlatformCredential cred) async {
    final store = ref.read(secureStoreProvider);
    await store.write(_keyOf(platform, 'key'), cred.appKey.trim());
    await store.write(_keyOf(platform, 'secret'), cred.appSecret.trim());
    state = AsyncValue.data({...(state.value ?? const {}), platform: cred});
  }
}
