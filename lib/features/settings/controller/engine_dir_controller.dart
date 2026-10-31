import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/engine_inspect.dart';
import '../../../core/storage/paths.dart';

/// 当前引擎目录（D-027）。
///
/// 不持久化是有意的：目录是「安装位置」，每次下载都要重新确认（D-015 定案），
/// 应用启动时回落到默认值即可；用户改选后仅在本会话内生效。
final engineDirProvider = NotifierProvider<EngineDirNotifier, String>(EngineDirNotifier.new);

class EngineDirNotifier extends Notifier<String> {
  @override
  String build() => mangaEngineDir();

  void set(String dir) => state = dir;
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
