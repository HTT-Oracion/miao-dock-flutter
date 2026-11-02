import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import 'queue_controller.dart';

/// 远程翻译入口守卫（**提交 / 重试 / 补页 / 返工全部走这里**）。
///
/// 判定本体在 `QueueNotifier.remoteUsable()`（与设置页【测试连接】同一探测）；
/// 本扩展只负责把「不可用」翻译成本地化文案，让 UI 拿到就能弹。
extension RemoteGuard on WidgetRef {
  /// 返回 null = 放行；非 null = 拦下原因（已本地化）。
  Future<String?> remoteGuard(AppLocalizations l10n) async {
    final usable = await read(queueProvider.notifier).remoteUsable();
    return usable ? null : l10n.remoteConfigInvalid;
  }
}
