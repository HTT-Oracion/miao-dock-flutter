import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'service_launch.dart';

/// `mangasvc` 子进程监督（P0-D1 / P0-D2）。
///
/// ## 就绪判定只认「那一行」
/// 服务的就绪协议是固定格式的一行：
/// `mangasvc listening on 127.0.0.1:<port>`（`server.dart` 的 `readyLine`）。
/// **不用**「端口能连上」当就绪 —— 端口可能被同网段的其它进程占着，
/// 一旦连错进程，后续所有请求都会莫名其妙地失败。
///
/// ## 退出清理
/// App 退出时必须把子进程带走，否则下次启动端口仍被占、用户只能重启机器。
/// 这里 `stop()` 先 SIGTERM 给宽限期，超时再 SIGKILL；并在 [dispose] 复用同一路径。
class ServiceSupervisor {
  ServiceSupervisor({
    required this.plan,
    this.readyTimeout = const Duration(seconds: 40),
    this.stopGrace = const Duration(seconds: 3),
    this.maxRestarts = 2,
    this.restartBackoff = const Duration(seconds: 1),
  });

  final ServiceLaunchPlan plan;

  /// 等就绪行的上限。开发期 `dart run` 首次可能要编译，给宽一点。
  final Duration readyTimeout;
  final Duration stopGrace;

  /// 非预期退出后的自动重启次数上限。
  final int maxRestarts;
  final Duration restartBackoff;

  Process? _proc;
  ServiceProcessState _state = ServiceProcessState.stopped;
  int? _port;
  bool _intentionalStop = false;
  int _restarts = 0;
  Timer? _restartTimer;

  final List<String> _log = [];
  final _stateController = StreamController<ServiceProcessState>.broadcast();
  Completer<int>? _readyCompleter;

  ServiceProcessState get state => _state;

  /// 就绪行里的端口；未就绪为 null。
  int? get port => _port;

  int? get pid => _proc?.pid;

  /// 最近输出（stdout + stderr，最多 200 行）。
  List<String> get log => List<String>.unmodifiable(_log);

  /// 状态变化流（UI 订阅用）。
  Stream<ServiceProcessState> get states => _stateController.stream;

  void _setState(ServiceProcessState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  void _append(String line) {
    _log.add(line);
    if (_log.length > 200) _log.removeAt(0);
  }

  /// 启动并等待就绪行。
  ///
  /// 返回就绪端口；失败返回 null（原因见 [log] 与 [lastError]）。
  Future<int?> start() async {
    if (_state == ServiceProcessState.running) return _port;
    if (_state == ServiceProcessState.starting) return _readyCompleter?.future;

    _intentionalStop = false;
    _restarts = 0;
    return _spawn();
  }

  /// 最近一次失败原因。
  String? lastError;

  Future<int?> _spawn() async {
    _setState(ServiceProcessState.starting);
    _readyCompleter = Completer<int>();
    lastError = null;

    try {
      final proc = await Process.start(
        plan.executable,
        plan.args,
        workingDirectory: plan.workingDirectory,
        runInShell: false,
      );
      _proc = proc;
      _append('[service] spawned pid=${proc.pid} (${plan.origin})');

      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onStdout);
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
        if (l.trim().isNotEmpty) _append('[stderr] $l');
      });

      unawaited(proc.exitCode.then(_onExit));

      final int port;
      try {
        port = await _readyCompleter!.future.timeout(readyTimeout);
      } on TimeoutException {
        lastError = '等待就绪行超时（${readyTimeout.inSeconds}s）。可能原因：服务启动失败、端口段全被占用。';
        _append('[service] ready-line timeout');
        _setState(ServiceProcessState.failed);
        // 超时也要杀掉，否则留一个永远不起作用的进程占资源。
        // 这里**必须 await**：不等它结束，调用方拿到的 pid 还是非空（进程还活着）。
        await _killQuiet();
        return null;
      }
      if (port <= 0) return null;

      _port = port;
      _setState(ServiceProcessState.running);
      _append('[service] ready on port $port');
      return port;
    } on ProcessException catch (e) {
      lastError = '起不了 mangasvc（${plan.executable}）：${e.message}';
      _append('[service] spawn failed: ${e.message}');
      _setState(ServiceProcessState.failed);
      return null;
    }
  }

  /// 解析就绪行。格式见 `server.dart` 的 `readyLine`。
  static final RegExp _readyRe = RegExp(r'mangasvc listening on\s+(\S+):(\d+)');

  void _onStdout(String line) {
    if (line.trim().isEmpty) return;
    _append(line);
    final m = _readyRe.firstMatch(line);
    if (m != null) {
      final port = int.tryParse(m.group(2)!);
      if (port != null && _readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.complete(port);
      }
    }
  }

  void _onExit(int code) {
    _proc = null;
    final wasIntentional = _intentionalStop;
    _append('[service] exited code=$code');

    // 就绪前就退出：让等待方立刻失败，不要干等到超时。
    // 🔴 主动杀掉时（超时兜底）**不能**改写 lastError —— 否则「等超时」这个根因
    //    会被「被我们杀掉了」这个后果覆盖，用户看到的原因就错了。
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      if (!wasIntentional) lastError = 'mangasvc 在就绪前退出（code=$code）';
      _readyCompleter!.complete(-1);
    }

    if (wasIntentional) {
      _port = null;
      // 🔴 失败就是最终结论：超时后我们主动杀掉进程，不能因此把 failed 改写成 stopped ——
      // 那会让用户以为「只是停了」，而真实原因（没能就绪）被抹掉。
      if (_state != ServiceProcessState.failed) _setState(ServiceProcessState.stopped);
      return;
    }
    if (_restarts >= maxRestarts) {
      _append('[service] 达到重启上限（$maxRestarts），不再重试');
      _port = null;
      _setState(ServiceProcessState.failed);
      return;
    }
    _restarts++;
    _append('[service] 非预期退出，${restartBackoff.inMilliseconds}ms 后重启（第 $_restarts 次）');
    _setState(ServiceProcessState.starting);
    _restartTimer?.cancel();
    _restartTimer = Timer(restartBackoff, () {
      if (_intentionalStop) return;
      unawaited(_spawn());
    });
  }

  /// 主动停止（不触发重启）。
  Future<void> stop() async {
    _intentionalStop = true;
    _restartTimer?.cancel();
    _restartTimer = null;

    final proc = _proc;
    if (proc == null) {
      _port = null;
      _setState(ServiceProcessState.stopped);
      return;
    }
    // 已 failed 时不降级成 stopping（见 _onExit 处的说明）。
    if (_state != ServiceProcessState.failed) _setState(ServiceProcessState.stopping);
    proc.kill(ProcessSignal.sigterm);
    await proc.exitCode.timeout(
      stopGrace,
      onTimeout: () {
        // 宽限期到了还没退：强杀，避免留僵尸占端口。
        proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    _proc = null;
    _port = null;
    _setState(ServiceProcessState.stopped);
  }

  /// 结束子进程但**不改写状态**（失败已经是最终结论，不再降级成 stopped）。
  Future<void> _killQuiet() async {
    final proc = _proc;
    if (proc == null) return;
    _intentionalStop = true;
    _restartTimer?.cancel();
    _restartTimer = null;
    proc.kill(ProcessSignal.sigterm);
    await proc.exitCode.timeout(
      stopGrace,
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    _proc = null;
    _port = null;
  }

  Future<void> dispose() async {
    await stop();
    await _stateController.close();
  }
}

/// 服务进程状态（与设计稿「服务」层一一对应）。
enum ServiceProcessState { stopped, starting, running, stopping, failed }
