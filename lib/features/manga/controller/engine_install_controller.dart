import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/paths.dart';
import '../../../core/storage/shell_prefs.dart';
import '../controller/queue_controller.dart';

/// 引擎装配进度（D-033）—— 引导页「下载」按钮背后的状态机。
///
/// ## 为什么要有独立的 provider
/// 装配是**长任务**（数百 MB 到数 GB），而 UI 需要跨页面存活：
/// 用户切到别的视图再回来，进度不能归零。放在 Notifier 里而不是 FutureBuilder 里，
/// 就是为了这一点。
/// 单个装配条目的进度（用于设计稿那种「一列文件」的下载卡）。
@immutable
class InstallEntry {
  const InstallEntry({required this.id, required this.sizeMb, required this.state, this.percent});

  final String id;
  final double sizeMb;

  /// `done` / `running` / `waiting` / `failed`
  final String state;
  final double? percent;
}

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
    this.entries = const [],
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

  /// 逐条目状态（服务端返回）；空 = 还没开始。
  final List<InstallEntry> entries;

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
    List<InstallEntry>? entries,
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
    entries: entries ?? this.entries,
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
      entries: [
        for (final e in (v['entries'] as List? ?? const []).cast<Map<String, dynamic>>())
          InstallEntry(
            id: '${e['id']}',
            sizeMb: (e['sizeMb'] as num?)?.toDouble() ?? 0,
            state: '${e['state']}',
            percent: (e['percent'] as num?)?.toDouble(),
          ),
      ],
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

/// 生效的引擎目录（D-034）：读盘上的选择，没有则用默认。
///
/// 🔴 **必须持久化**：目录是可搬、可导入的（D-027），记不住路径等于每次启动
/// 都回到默认位置 —— 用户导入的目录「第二天就失效」，这比没有导入更糟。
final engineRootProvider = NotifierProvider<EngineDirNotifier, String>(EngineDirNotifier.new);

class EngineDirNotifier extends Notifier<String> {
  @override
  String build() => readEngineDir() ?? mangaEngineDir();

  void set(String dir) {
    state = dir;
    persistEngineDir(dir);
  }
}

/// 默认装配目录（当前引擎目录）。
String defaultEngineInstallDir() => mangaEngineDir();
