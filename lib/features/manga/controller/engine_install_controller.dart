import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/paths.dart';
import '../controller/queue_controller.dart';

/// 引擎装配进度（D-033）—— 引导页「下载」按钮背后的状态机。
///
/// ## 为什么要有独立的 provider
/// 装配是**长任务**（数百 MB 到数 GB），而 UI 需要跨页面存活：
/// 用户切到别的视图再回来，进度不能归零。放在 Notifier 里而不是 FutureBuilder 里，
/// 就是为了这一点。
@immutable
class EngineInstallState {
  const EngineInstallState({
    this.running = false,
    this.done = false,
    this.entryId,
    this.phase,
    this.index = 0,
    this.total = 0,
    this.percent,
    this.error,
    this.logs = const [],
  });

  final bool running;
  final bool done;
  final String? entryId;
  final String? phase;
  final int index;
  final int total;

  /// 单个条目的下载进度；null = 没有真实来源（不编造）。
  final double? percent;

  final String? error;
  final List<String> logs;

  static const EngineInstallState idle = EngineInstallState();

  EngineInstallState copyWith({
    bool? running,
    bool? done,
    String? entryId,
    String? phase,
    int? index,
    int? total,
    double? percent,
    String? error,
    List<String>? logs,
    bool clearError = false,
  }) => EngineInstallState(
    running: running ?? this.running,
    done: done ?? this.done,
    entryId: entryId ?? this.entryId,
    phase: phase ?? this.phase,
    index: index ?? this.index,
    total: total ?? this.total,
    percent: percent ?? this.percent,
    error: clearError ? null : (error ?? this.error),
    logs: logs ?? this.logs,
  );
}

final engineInstallProvider = NotifierProvider<EngineInstallNotifier, EngineInstallState>(EngineInstallNotifier.new);

class EngineInstallNotifier extends Notifier<EngineInstallState> {
  Timer? _timer;

  @override
  EngineInstallState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return EngineInstallState.idle;
  }

  /// 开始装配。`engineDir` 由目录选择对话框给出（D-015：每次都问）。
  Future<void> start({required String engineDir, String? backend, bool includeNllb = false}) async {
    if (state.running) return;
    _timer?.cancel();
    state = const EngineInstallState(running: true);
    try {
      final first = await ref
          .read(mangaSvcClientProvider)
          .installEngine(engineDir: engineDir, backend: backend, includeNllb: includeNllb);
      _apply(first);
      _poll();
    } catch (e) {
      state = state.copyWith(running: false, error: '$e', logs: ['$e']);
    }
  }

  void _poll() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      try {
        _apply(await ref.read(mangaSvcClientProvider).getEngineInstall());
      } catch (e) {
        _timer?.cancel();
        _timer = null;
        state = state.copyWith(running: false, error: '$e');
      }
    });
  }

  void _apply(Map<String, dynamic> v) {
    final running = v['running'] == true;
    final st = v['state'] as String?;
    final logs = (v['tail'] as List?)?.cast<String>() ?? const <String>[];
    state = EngineInstallState(
      running: running,
      done: st == 'done',
      entryId: v['entryId'] as String?,
      phase: v['phase'] as String?,
      index: (v['index'] as num?)?.toInt() ?? 0,
      total: (v['total'] as num?)?.toInt() ?? 0,
      percent: (v['percent'] as num?)?.toDouble(),
      error: v['error'] as String?,
      logs: logs,
    );
    if (!running) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// 清空（换目录后重来）。
  void reset() {
    _timer?.cancel();
    _timer = null;
    state = EngineInstallState.idle;
  }
}

/// 会话内导入的引擎目录。
///
/// 不持久化是临时取舍：落盘需要一个「引擎目录」设置项（设置页尚未有），
/// 先把导入效果接上，避免按钮点了没反应。
final importedEngineDirProvider = NotifierProvider<ImportedEngineDirNotifier, String?>(ImportedEngineDirNotifier.new);

class ImportedEngineDirNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? dir) => state = dir;
}

/// 生效的引擎目录：导入过就用导入的，否则用默认。
final activeEngineDirProvider = Provider<String>((ref) => ref.watch(importedEngineDirProvider) ?? mangaEngineDir());

/// 默认装配目录（当前引擎目录）。
String defaultEngineInstallDir() => mangaEngineDir();
