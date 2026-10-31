import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 引擎进程监督（P0-C6c）—— spawn + 健康探针 + 崩溃退避重启。
///
/// ## 三条必须做对的语义
/// 1. **「健康」不等于「进程活着」**：进程起来后要能应答 `/health` 才算就绪。
///    只看 pid 会让宿主编译中的引擎被当成可用（用户点翻译就超时）。
/// 2. **主动停止不得触发重启**：`stop()` 会结束子进程，若不区分，
///    监督器会把「用户要停」当「崩溃了」立刻拉起来 —— 停止按钮变成重启按钮。
/// 3. **重启要退避**：模型加载失败这类问题是**确定性**的，立刻无限重试会
///    把 CPU 打满、日志刷爆。退避 + 次数上限，超限后进入 failed 交给人判断。
class EngineSupervisor {
  EngineSupervisor({
    required this.processPath,
    required this.processArgs,
    required this.healthUrl,
    this.workingDirectory,
    this.healthTimeout = const Duration(seconds: 60),
    this.healthInterval = const Duration(milliseconds: 150),
    this.maxRestarts = 3,
    this.backoffBase = const Duration(milliseconds: 300),
    this.backoffCap = const Duration(seconds: 30),
  });

  final String processPath;
  final List<String> processArgs;
  final String healthUrl;
  final String? workingDirectory;

  /// 等待健康应答的总时长（首次加载模型可能很慢）。
  final Duration healthTimeout;
  final Duration healthInterval;

  /// 非预期退出后的最大重启次数；超过则进入 [SupervisorState.failed]。
  final int maxRestarts;
  final Duration backoffBase;
  final Duration backoffCap;

  Process? _proc;
  SupervisorState _state = SupervisorState.stopped;
  bool _intentionalStop = false;
  int _restartCount = 0;
  Timer? _restartTimer;
  final List<String> _log = [];

  SupervisorState get state => _state;

  /// 已发生的自动重启次数。
  int get restartCount => _restartCount;

  /// 子进程 pid（未运行返回 null）。
  int? get pid => _proc?.pid;

  /// 最近日志（stdout + stderr，最多 200 行）。
  List<String> get log => List<String>.unmodifiable(_log);

  void _append(String line) {
    _log.add(line);
    if (_log.length > 200) _log.removeAt(0);
  }

  /// 启动并等待健康。
  ///
  /// 返回是否在 [healthTimeout] 内就绪。
  Future<bool> start() async {
    if (_state == SupervisorState.running || _state == SupervisorState.starting) return true;
    _intentionalStop = false;
    _restartCount = 0;
    return _spawnAndWait();
  }

  Future<bool> _spawnAndWait() async {
    _state = SupervisorState.starting;
    try {
      final proc = await Process.start(processPath, processArgs, workingDirectory: workingDirectory, runInShell: false);
      _proc = proc;
      _append('[supervisor] spawned pid=${proc.pid}');

      // 持续排空两个流：不排空会让子进程在写满管道后阻塞（整机看起来"卡住"）。
      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
        if (l.isNotEmpty) _append(l);
      });
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
        if (l.isNotEmpty) _append(l);
      });

      unawaited(
        proc.exitCode.then((code) {
          _append('[supervisor] exited code=$code');
          _onExit(code);
        }),
      );

      final healthy = await _waitHealthy();
      if (!healthy) {
        _append('[supervisor] health check timed out after ${healthTimeout.inSeconds}s');
        _state = SupervisorState.failed;
        return false;
      }
      _state = SupervisorState.running;
      _append('[supervisor] healthy');
      return true;
    } on ProcessException catch (e) {
      _append('[supervisor] spawn failed: ${e.message}');
      _state = SupervisorState.failed;
      return false;
    }
  }

  Future<bool> _waitHealthy() async {
    final deadline = DateTime.now().add(healthTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_proc == null) return false;
      if (await probeHealth(healthUrl)) return true;
      await Future<void>.delayed(healthInterval);
    }
    return false;
  }

  /// 单次健康探测。超时短（1s），避免探针本身拖住判定。
  static Future<bool> probeHealth(String url, {Duration timeout = const Duration(seconds: 1)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final resp = await req.close().timeout(timeout);
      await resp.drain<void>();
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void _onExit(int code) {
    _proc = null;
    // 主动停止：不重启。这就是「停止」与「崩溃」的分界。
    if (_intentionalStop) {
      _state = SupervisorState.stopped;
      return;
    }
    if (_state == SupervisorState.stopping) {
      _state = SupervisorState.stopped;
      return;
    }

    if (_restartCount >= maxRestarts) {
      _append('[supervisor] 达到重启上限（$maxRestarts 次），停止重试');
      _state = SupervisorState.failed;
      return;
    }

    _restartCount++;
    final delay = _backoff(_restartCount);
    _append('[supervisor] 非预期退出（code=$code），${delay.inMilliseconds}ms 后第 $_restartCount 次重启');
    _state = SupervisorState.starting;
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () {
      if (_intentionalStop) return;
      unawaited(_spawnAndWait());
    });
  }

  /// 指数退避：base * 2^(n-1)，上限 [backoffCap]。
  Duration _backoff(int attempt) {
    final ms = backoffBase.inMilliseconds * (1 << (attempt - 1).clamp(0, 20));
    return Duration(milliseconds: ms > backoffCap.inMilliseconds ? backoffCap.inMilliseconds : ms);
  }

  /// 主动停止（不触发重启）。
  Future<void> stop({Duration grace = const Duration(seconds: 3)}) async {
    _intentionalStop = true;
    _restartTimer?.cancel();
    _restartTimer = null;

    final proc = _proc;
    if (proc == null) {
      _state = SupervisorState.stopped;
      return;
    }
    _state = SupervisorState.stopping;
    proc.kill(ProcessSignal.sigterm);
    // 宽限期后强杀：模型进程有时不响应 SIGTERM，留僵尸会占住端口。
    final exited = await proc.exitCode.timeout(
      grace,
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    _append('[supervisor] stopped (exit=$exited)');
    _proc = null;
    _state = SupervisorState.stopped;
  }

  Future<void> dispose() async {
    await stop();
  }
}

/// 监督器状态（与引擎五态对齐，外加 failed）。
enum SupervisorState { stopped, starting, running, stopping, failed }
