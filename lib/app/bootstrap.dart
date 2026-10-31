import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/port_probe.dart';
import '../../core/net/service_locator.dart';
import '../../core/window/window_controller.dart';
import '../../features/manga/controller/queue_controller.dart';
import '../../features/manga/data/http_manga_svc_client.dart';

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

  final ServiceLocator locator;
  if (forcedBaseUrl.isNotEmpty) {
    locator = RemoteServiceLocator(baseUrl: forcedBaseUrl, token: token.isEmpty ? null : token);
  } else if (isDesktopPlatform) {
    locator = LocalServiceLocator(probe: const PortProbe(), token: token.isEmpty ? null : token);
  } else {
    // 移动端 / Web：地址来自设置域（待 P5 落地后接入），此处先用同一个 define 兜住。
    locator = RemoteServiceLocator(baseUrl: forcedBaseUrl, token: token.isEmpty ? null : token);
  }

  runApp(ProviderScope(overrides: [mangaSvcClientProvider.overrideWithValue(HttpMangaSvcClient(locator))], child: app));
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
