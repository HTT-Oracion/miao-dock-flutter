import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/process/service_controller.dart';
import '../../../../core/theme/tokens.dart';
import '../controller/engine_controller.dart';
import '../controller/engine_install_controller.dart';
import '../controller/engine_ready_controller.dart';
import '../domain/not_ready_state.dart';
import 'notready/not_ready_screen.dart';
import 'notready/runtime_picker.dart';

/// 漫画模块的**门禁**（D-037）。
///
/// 进入漫画模块时先快检「装配 + 引擎」，未就绪则用 `.nr-card` 顶替主体区内容，
/// 侧栏照常显示（高亮「投放」）。
///
/// ## 为什么放在分支层而不是每个屏里
/// 投放 / 队列 / 漫画库三处各写一遍，迟早漂移；而且新增视图时会忘记加。
class MangaGate extends ConsumerWidget {
  const MangaGate({super.key, required this.enabled, required this.child});

  /// 只有漫画模块（moduleIndex == 0）才启用。
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) return child;

    final gate = ref.watch(mangaGateProvider);
    if (gate == MangaGateState.ready) return child;
    // 检查中：骨架。**不能**先画「未装配」——那会闪一下像故障。
    if (gate == MangaGateState.checking) return const _GateSkeleton();

    return _GateCard(gate: gate);
  }
}

/// 检查中的骨架（沿用共享 Skeleton）。
class _GateSkeleton extends StatelessWidget {
  const _GateSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Bar(width: 220, height: 20, color: palette.hi),
              const SizedBox(height: 12),
              _Bar(width: 420, height: 12, color: palette.hi),
              const SizedBox(height: 24),
              Container(
                height: 132,
                decoration: BoxDecoration(
                  color: palette.card,
                  border: Border.all(color: palette.line),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 占位条（加载态用）。
class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
  );
}

/// 未就绪时的卡片：复用 [NotReadyScreen]（同一个 `.nr-card` 视觉）。
class _GateCard extends ConsumerWidget {
  const _GateCard({required this.gate});

  final MangaGateState gate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final install = ref.watch(engineInstallProvider);
    final source = ref.watch(translateSourceProvider);

    final view = switch (gate) {
      MangaGateState.downloading => NotReadyView(
        state: NotReadyState.downloading,
        engine: EngineRuntimeState.off,
        source: source,
        downloadProgress: install.percent,
        logs: install.logs,
      ),
      MangaGateState.degraded => NotReadyView(
        state: NotReadyState.degraded,
        engine: EngineRuntimeState.off,
        source: source,
      ),
      MangaGateState.installed => NotReadyView(
        state: NotReadyState.installed,
        engine: EngineRuntimeState.off,
        source: source,
      ),
      MangaGateState.starting => NotReadyView(
        state: NotReadyState.starting,
        engine: EngineRuntimeState.starting,
        source: source,
      ),
      MangaGateState.failed => NotReadyView(
        state: NotReadyState.failed,
        engine: EngineRuntimeState.failed,
        source: source,
        logs: const [],
      ),
      _ => NotReadyView(state: NotReadyState.uninstalled, engine: EngineRuntimeState.off, source: source),
    };

    return NotReadyScreen(
      view: view,
      onPrimary: () => _primary(context, ref, gate),
      onSecondary: () => context.go('/settings'),
      onRetryService: () => ref.read(serviceStatusProvider.notifier).start(),
      onImportLocal: () => _import(context, ref),
      // 方案 C：整模块拦截，但留一条**不需要引擎**的只读出口。
      onBrowseLibrary: () => context.go('/manga/library'),
    );
  }

  Future<void> _primary(BuildContext context, WidgetRef ref, MangaGateState gate) async {
    final install = ref.read(engineInstallProvider.notifier);
    switch (gate) {
      case MangaGateState.notAssembled:
      case MangaGateState.failed:
        final r = await RuntimePickerDialog.show(context, initialDir: ref.read(engineRootProvider));
        if (r == null) return;
        install.reset();
        await install.start(engineDir: r.dir);
        // 装完重新快检，卡片才会消失。
        await ref.read(enginePresenceProvider.notifier).refresh();
      case MangaGateState.installed:
        await ref.read(engineStateProvider.notifier).start();
      default:
        break;
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final r = await RuntimePickerDialog.show(context, initialDir: ref.read(engineRootProvider), importMode: true);
    if (r == null) return;
    ref.read(engineRootProvider.notifier).set(r.dir);
    await ref.read(enginePresenceProvider.notifier).refresh();
  }
}
