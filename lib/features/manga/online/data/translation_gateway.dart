import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/online_download.dart';
import '../domain/online_error.dart';

/// 翻译网关：把 UI 状态机与真实 `mangasvc` 队列隔开。
///
/// 演示实现按页推进（准实时），真实实现只需把 `createTask` / 轮询
/// `translatedSeqs` 的结果映射到同一组 [TranslationStatus]。
abstract interface class OnlineTranslationGateway {
  Stream<TranslationStatus> translate({
    required String sourceId,
    required String comicId,
    required String chapterId,
    required int total,
    bool fromCurrentPage = false,
  });
}

/// 演示翻译：排队 600ms → 每 260ms 产出一页 → 完成。
class DemoTranslationGateway implements OnlineTranslationGateway {
  const DemoTranslationGateway();

  @override
  Stream<TranslationStatus> translate({
    required String sourceId,
    required String comicId,
    required String chapterId,
    required int total,
    bool fromCurrentPage = false,
  }) async* {
    if (sourceId == 'mangabz') {
      throw const OnlineException(OnlineErrorCode.crashed, 'source unavailable');
    }
    yield TranslationStatus(state: TranslationState.queued, done: 0, total: total);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    var done = 0;
    while (done < total) {
      yield TranslationStatus(state: TranslationState.running, done: done, total: total);
      await Future<void>.delayed(const Duration(milliseconds: 260));
      done += 1;
    }
    yield TranslationStatus(state: TranslationState.done, done: total, total: total);
  }
}

/// 可覆盖点：测试用故障网关验证 failed / partial / unavailable 的视觉与动作。
final onlineTranslationGatewayProvider = Provider<OnlineTranslationGateway>((ref) {
  return const DemoTranslationGateway();
});

/// 翻译服务是否可用（Web 端整模块灰置；移动端需远程桌面端）。
///
/// 演示模式下移动端也允许发起，以覆盖设计稿的翻译状态机；真实接入时
/// 把这里换成 `remoteVerificationProvider` 的就绪判断即可。
final onlineTranslationAvailableProvider = Provider<bool>((ref) => true);
