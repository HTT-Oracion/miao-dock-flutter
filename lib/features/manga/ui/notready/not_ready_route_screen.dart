import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controller/engine_controller.dart';
import '../../controller/engine_install_controller.dart';
import '../../domain/not_ready_state.dart';
import 'not_ready_screen.dart';
import 'backend_picker.dart';

import 'runtime_picker.dart';

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
      onPrimary: () async {
        final install = ref.read(engineInstallProvider.notifier);
        switch (view.state) {
          case NotReadyState.uninstalled:
          case NotReadyState.failed:
            // 重新下载与直接下载一致：**先选目录**（D-027 定案）。
            final r = await RuntimePickerDialog.show(context, initialDir: ref.read(engineRootProvider));
            if (r == null) return;
            // 后端选择只对 Windows / Linux 有意义（macOS 只有一种构建）。
            String? backend;
            if (backendSelectable) {
              final probe = await probeBackend();
              if (!context.mounted) return;
              final picked = await LlamaBackendPicker.show(context, probe: probe);
              if (picked == null) return;
              backend = picked.id;
            }
            install.reset();
            await install.start(engineDir: r.dir, backend: backend);
          case NotReadyState.installed:
            // 已装好但引擎未起 → 起引擎（共用开关，D-012）。
            engine.start();
          case NotReadyState.starting:
          case NotReadyState.downloading:
          case NotReadyState.degraded:
            // 进行中或服务异常：主按钮此时不承担动作。
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
      // 导入本地运行时（D-015）：选目录 → 浅检查 → 通过则跳过下载。
      onImportLocal: () async {
        final result = await RuntimePickerDialog.show(
          context,
          initialDir: ref.read(engineRootProvider),
          importMode: true,
        );
        if (result == null || !result.imported) return;
        // 校验已通过（对话框里强制要求），记住目录即可让它生效。
        ref.read(engineRootProvider.notifier).set(result.dir);
        // TODO(P0-C): 把选定目录写入运行时配置，并触发引擎装载。
        // 完整性校验见 P0-F6d（已记账，后做）；当前只做了结构浅检查。
      },
    );
  }
}
