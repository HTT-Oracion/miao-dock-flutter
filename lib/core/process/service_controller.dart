import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../window/window_controller.dart';
import 'service_launch.dart';
import 'service_supervisor.dart';

/// 服务进程状态（P0-D3）—— 供 UI 观测。
///
/// ## 为什么单独一个 provider，而不复用端口探测结果
/// 端口探测回答「能不能连上」，它**分不清**「服务没起」与「服务起了但端口被别人占」。
/// 进程状态能分清，而这两种情况对用户的提示完全不同：
/// 前者要去启动，后者要去改端口。
@immutable
class ServiceStatus {
  const ServiceStatus({required this.state, this.port, this.pid, this.error, this.supported = true});

  final ServiceProcessState state;
  final int? port;
  final int? pid;

  /// 失败原因（state = failed 时）。
  final String? error;

  /// 当前平台是否托管本地服务。
  ///
  /// 移动端 / Web 不跑服务（AGENTS §2），此时**不能**把「没有服务」显示成故障。
  final bool supported;

  bool get isRunning => state == ServiceProcessState.running;

  static const ServiceStatus unsupported = ServiceStatus(state: ServiceProcessState.stopped, supported: false);
}

/// 服务监督器（桌面端）。非桌面端为 null。
///
/// 由 [bootstrapService] 注入；测试不注入则为 null（UI 退化为「未托管」）。
final serviceSupervisorProvider = Provider<ServiceSupervisor?>((ref) => null);

/// 服务进程状态。
final serviceStatusProvider = NotifierProvider<ServiceStatusNotifier, ServiceStatus>(ServiceStatusNotifier.new);

class ServiceStatusNotifier extends Notifier<ServiceStatus> {
  StreamSubscription<ServiceProcessState>? _sub;

  @override
  ServiceStatus build() {
    final supervisor = ref.watch(serviceSupervisorProvider);
    if (supervisor == null) {
      return isDesktopPlatform ? const ServiceStatus(state: ServiceProcessState.stopped) : ServiceStatus.unsupported;
    }
    _sub?.cancel();
    _sub = supervisor.states.listen((s) {
      state = _snapshot(supervisor, s);
    });
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    return _snapshot(supervisor, supervisor.state);
  }

  static ServiceStatus _snapshot(ServiceSupervisor s, ServiceProcessState st) =>
      ServiceStatus(state: st, port: s.port, pid: s.pid, error: st == ServiceProcessState.failed ? s.lastError : null);

  /// 手动启动（设置页 / 引导页的「启动服务」）。
  Future<bool> start() async {
    final supervisor = ref.read(serviceSupervisorProvider);
    if (supervisor == null) return false;
    final port = await supervisor.start();
    state = _snapshot(supervisor, supervisor.state);
    return port != null;
  }

  /// 手动停止。
  Future<void> stop() async {
    final supervisor = ref.read(serviceSupervisorProvider);
    if (supervisor == null) return;
    await supervisor.stop();
    state = _snapshot(supervisor, supervisor.state);
  }
}

/// 应用退出时的进程清理（P0-D2）。
///
/// 不清理的后果：子进程成为孤儿，端口一直占着，下次启动必须换端口或重启机器。
class AppLifecycleCleanup with WidgetsBindingObserver {
  AppLifecycleCleanup(this._supervisor);

  final ServiceSupervisor? _supervisor;
  bool _done = false;

  void attach() => WidgetsBinding.instance.addObserver(this);

  void detach() => WidgetsBinding.instance.removeObserver(this);

  /// 用户点关闭 / Cmd+Q：先把子进程带走再退，避免留孤儿占端口。
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await shutdown();
    return AppExitResponse.exit;
  }

  Future<void> shutdown() async {
    if (_done) return;
    _done = true;
    debugPrint('[lifecycle] 应用退出：清理 mangasvc');
    await _supervisor?.dispose();
    debugPrint('[lifecycle] mangasvc 已结束');
  }
}

/// 解析 + 启动（供 bootstrap 使用，避免把 Process 逻辑写进 bootstrap）。
Future<ServiceStatus> startLocalService({
  String? forcedBin,
  Duration readyTimeout = const Duration(seconds: 40),
}) async {
  final plan = ServiceLaunchPlan.resolve(forcedBin: forcedBin);
  if (plan == null) {
    return ServiceStatus(state: ServiceProcessState.failed, error: ServiceLaunchPlan.lastError);
  }
  final sup = ServiceSupervisor(plan: plan, readyTimeout: readyTimeout);
  final port = await sup.start();
  return ServiceStatus(state: sup.state, port: sup.port, pid: sup.pid, error: port == null ? sup.lastError : null);
}
