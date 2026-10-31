import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/engine_inspect.dart';
import '../../manga/controller/engine_install_controller.dart';

/// 当前引擎目录 —— **代理到 `engineRootProvider`**（D-061）。
///
/// ## 为什么必须只有一个来源
/// 之前这里是个独立、且**不落盘**的 provider：设置页「导入」只改它，
/// 而门禁（`mangaGateProvider`）读的是 `engineRootProvider`。
/// 结果：导入成功后**投放页仍然显示下载页**——用户以为导入没生效。
///
/// 现在本 provider 只做转发：读走 watch，写走对方 notifier，落盘由对方负责。
final engineDirProvider = NotifierProvider<EngineDirNotifier, String>(EngineDirNotifier.new);

class EngineDirNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(engineRootProvider);

  void set(String dir) => ref.read(engineRootProvider.notifier).set(dir);
}

/// 引擎校验结果。
///
/// null = 还没校验过（不是「通过」）。这一点很重要：界面必须能区分
/// 「没检查」与「检查通过」，否则会给出虚假的安心感。
final engineInspectionProvider = AsyncNotifierProvider<EngineInspectionNotifier, EngineInspection?>(
  EngineInspectionNotifier.new,
);

class EngineInspectionNotifier extends AsyncNotifier<EngineInspection?> {
  @override
  Future<EngineInspection?> build() async => null;

  /// 跑一次校验（会起子进程 import，慢，必须手动触发）。
  Future<EngineInspection?> run() async {
    final dir = ref.read(engineDirProvider);
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() => inspectEngine(dir));
    state = result;
    return result.value;
  }

  /// 换目录后作废旧的校验结论。
  void invalidate() => state = const AsyncValue.data(null);

  /// 直接采用一次已有结论（导入流程里已经校验过，不必再让用户点一次）。
  void adopt(EngineInspection inspection) => state = AsyncValue.data(inspection);
}
