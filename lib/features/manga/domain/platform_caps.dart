import 'package:flutter/foundation.dart';

import '../../../core/window/window_controller.dart';
import 'not_ready_state.dart';

/// 平台能力（D-044）：**本地引擎只可能跑在桌面端**。
///
/// ## 为什么要在领域层定义
/// 「哪些来源可选」是**业务约束**，不是 UI 细节：桌面端三选一，Web / 移动端只有远程。
/// 只在界面上藏选项不可靠（换个入口就能绕过），所以判定要能同时被 UI 与请求侧复用。
///
/// ## 为什么 Web 也算「远程」
/// 浏览器里没有进程、没有文件系统，跑不了 Python 引擎；
/// 它和手机一样，只能连别人已经起好的服务。
bool get isWebHost => kIsWeb;

/// 是否可能在本机跑引擎（只有桌面端）。
bool get supportsLocalEngine => isDesktopPlatform && !kIsWeb;

/// 当前平台可选的翻译来源。
List<TranslateSource> get availableTranslateSources =>
    supportsLocalEngine ? TranslateSource.values : const [TranslateSource.remote];
