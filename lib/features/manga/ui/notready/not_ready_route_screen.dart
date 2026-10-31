import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/engine_controller.dart';
import '../../domain/not_ready_state.dart';
import 'not_ready_screen.dart';

/// 路由壳：把 [NotReadyScreen] 接到 provider 与导航上。
///
/// 拆成两层是因为 [NotReadyScreen] 是**纯展示件**（可单测、可预览），
/// 而本文件只做「状态 → 动作」的接线。
class NotReadyRouteScreen extends ConsumerWidget {
  const NotReadyRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(notReadyViewProvider);
    final engine = ref.read(engineStateProvider.notifier);

    return NotReadyScreen(
      view: view,
      onPrimary: () {
        switch (view.state) {
          case NotReadyState.uninstalled:
            // P0-C：触发模型下载。当前未接入 → 不假装开始。
            break;
          case NotReadyState.installed:
            engine.start();
          case NotReadyState.failed:
            engine.start();
          case NotReadyState.starting:
            break;
          case NotReadyState.downloading:
            break;
          case NotReadyState.degraded:
            break;
        }
      },
      onSecondary: () {
        switch (view.state) {
          case NotReadyState.uninstalled:
          case NotReadyState.installed:
            context.go('/settings');
          default:
            break;
        }
      },
      onRetryService: () {},
      onExportLogs: null,
    );
  }
}
