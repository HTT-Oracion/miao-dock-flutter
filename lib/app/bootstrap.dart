import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/port_probe.dart';
import '../../core/net/service_locator.dart';
import '../../core/process/service_controller.dart';
import '../../core/storage/shell_prefs.dart';
import '../../core/process/service_launch.dart';
import '../../core/process/service_supervisor.dart';
import '../../core/window/window_controller.dart';
import '../../features/manga/controller/queue_controller.dart';
import '../../features/manga/domain/platform_caps.dart';
import '../../features/manga/data/http_manga_svc_client.dart';
import 'engine_autostart.dart';

/// 启动装配收口（AGENTS §3）：桌面 / 移动平台分支与 Fake / 真客户端注入只在这里发生，
/// 业务层不感知平台差异。
///
/// 客户端注入（P0-A2/A3/A4）：
///   · 桌面端 → [LocalServiceLocator]：端口段探测 5180–5190 + 令牌；
///   · 移动端 / Web → [RemoteServiceLocator]：连设置域手动配置的桌面端地址。
///
/// `--dart-define=MIAO_SVC_BASE_URL=...` 可强制指定地址（联调 / 排障用）；
/// `--dart-define=MIAO_SVC_TOKEN=...` 注入配对令牌。
Future<void> bootstrap(Widget app) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDesktopWindow();
  await initMobileSystemUi();

  const forcedBaseUrl = String.fromEnvironment('MIAO_SVC_BASE_URL');
  const token = String.fromEnvironment('MIAO_SVC_TOKEN');
  const serviceBin = String.fromEnvironment('MIAO_SERVICE_BIN');

  // P0-D1：桌面端由应用自己拉起 mangasvc（服务常驻，D-012）。
  // 指定了外部地址（联调）或非桌面端时不启动本地服务。
  ServiceSupervisor? supervisor;
  if (isDesktopPlatform && forcedBaseUrl.isEmpty) {
    final plan = ServiceLaunchPlan.resolve(
      forcedBin: serviceBin.isEmpty ? null : serviceBin,
      overrideBin: Platform.environment['MIAO_SERVICE_BIN'],
    );
    if (plan != null) {
      supervisor = ServiceSupervisor(plan: plan);
      // 启动失败不阻塞进 UI：引导页会把「服务未就绪」如实画出来。
      final port = await supervisor.start();
      // 诊断输出：启动失败时日志里要能直接看到原因，而不是只留一个连不上的服务。
      debugPrint('[bootstrap] mangasvc ${plan.origin} → ${port == null ? '失败：${supervisor.lastError}' : '端口 $port'}');
    } else {
      debugPrint('[bootstrap] 未启动 mangasvc：${ServiceLaunchPlan.lastError}');
    }
  }

  // 服务自报的令牌优先（编译期常量通常为空）。
  final serviceToken = supervisor?.token ?? (token.isEmpty ? null : token);

  final ServiceLocator locator;
  if (forcedBaseUrl.isNotEmpty) {
    locator = RemoteServiceLocator(baseUrl: forcedBaseUrl, token: token.isEmpty ? null : token);
  } else if (isDesktopPlatform) {
    locator = LocalServiceLocator(probe: const PortProbe(), token: serviceToken);
  } else {
    // 移动端 / Web：地址来自设置域（待 P5 落地后接入），此处先用同一个 define 兜住。
    locator = RemoteServiceLocator(baseUrl: forcedBaseUrl, token: token.isEmpty ? null : token);
  }

  // P0-D2：应用退出时带走子进程，避免留孤儿占端口。
  if (supervisor != null) {
    AppLifecycleCleanup(supervisor).attach();
  }

  runApp(
    ProviderScope(
      overrides: [
        mangaSvcClientProvider.overrideWithValue(
          HttpMangaSvcClient(
            // Web / 移动端：本机没有服务，也没有端口探测（`ServerSocket` 在 Web 上不可用）。
            // 一律走用户配置的远程地址（D-045）。
            supportsLocalEngine
                ? locator
                : RemoteServiceLocator(baseUrl: readRemoteBaseUrl() ?? '', token: readRemoteToken()),
          ),
        ),
        if (supervisor != null) serviceSupervisorProvider.overrideWithValue(supervisor),
      ],
      child: EngineAutoStart(child: app),
    ),
  );
}

/// 移动端系统 UI（Android）：edge-to-edge 沉浸式。
///
/// 设计稿是 Web 稿、未画系统栏；跨端差异按以下口径落地并已在方案中报备：
///   · 状态栏 / 导航栏透明，内容延伸到系统栏下方；
///   · 图标用浅色（深色主题下才可见），由 `SafeArea` 负责内容避让。
///
/// iOS 与 Web 不做系统栏操作（iOS 由 Info.plist 控制，Web 无系统栏）。
Future<void> initMobileSystemUi() async {
  if (isDesktopPlatform || kIsWeb) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0x00000000),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
}
