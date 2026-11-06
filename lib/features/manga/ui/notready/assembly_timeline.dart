import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../controller/engine_install_controller.dart';
import '../../domain/not_ready_state.dart';

/// 装配五段时间线（重设计稿 modules/guide.html：环境准备 → 运行环境 →
/// 视觉模型 → 翻译模型 → 就绪）。
///
/// 为什么逐段画而不是给一个「已完成 N 段」的数字：视觉模型与翻译模型是
/// **两条独立资产链**，一个数字分不清「视觉好了、翻译模型还没下」。
///
/// 段状态推导是**纯函数**（[assemblyPhases]），可单测；widget 只负责画。
enum AssemblyPhaseState { done, active, failed, waiting }

@immutable
class AssemblyPhase {
  const AssemblyPhase({required this.label, required this.state, required this.word});

  final String label;
  final AssemblyPhaseState state;

  /// 段状态词（已完成/进行中/失败/等待），由推导函数按 ARB 注入。
  final String word;
}

/// 从门禁视图状态 + 下载条目推导五段状态（判定顺序先硬后软）：
///
/// 1. 有真实下载活动（entries 任一非 waiting）⇒ 按条目 id 关键词归段
///    （visual→视觉 / llm·nllb·sakura→翻译 / 其余→运行环境），段内聚合：
///    全 done → 完成，任一 failed → 失败，任一 running → 进行中；
///    环境准备段在下载活动存在时视为完成（探针能读到即算）。
/// 2. 无活动时按服务状态收尾：uninstalled/downloading ⇒ 全等待（磁盘不会自己变，
///    🔴 缺件且无实际活动只能标等待，不能标进行中）；installed ⇒ 前四段完成；
///    starting ⇒ 前四段完成、就绪进行中；failed/degraded ⇒ 就绪失败。
List<AssemblyPhase> assemblyPhases(AppLocalizations l10n, NotReadyState state, List<InstallEntry> entries) {
  var env = 'waiting', runtime = 'waiting', visual = 'waiting', llm = 'waiting', ready = 'waiting';
  // InstallEntry.state 可空：null 与 'waiting' 同义（还没轮到）。
  String st(InstallEntry e) => e.state;
  final live = entries.any((e) => st(e) != 'waiting');
  if (live) {
    env = 'done';
    String segOf(InstallEntry e) {
      final id = e.id.toLowerCase();
      if (id.contains('visual')) return 'visual';
      if (id.contains('llm') || id.contains('nllb') || id.contains('sakura')) return 'llm';
      return 'runtime';
    }

    String agg(String seg) {
      final list = entries.where((e) => segOf(e) == seg).toList();
      if (list.isEmpty) return 'waiting';
      if (list.every((e) => st(e) == 'done')) return 'done';
      if (list.any((e) => st(e) == 'failed')) return 'failed';
      if (list.any((e) => st(e) == 'running')) return 'active';
      return 'waiting';
    }

    runtime = agg('runtime');
    visual = agg('visual');
    llm = agg('llm');
    // 条目 id 不含任何关键词 ⇒ 全落在 runtime 段，至少点亮一段。
    if (runtime == 'waiting' && visual == 'waiting' && llm == 'waiting') runtime = 'active';
  } else {
    switch (state) {
      case NotReadyState.uninstalled:
      case NotReadyState.downloading:
        break; // 全等待
      case NotReadyState.installed:
        env = runtime = visual = llm = 'done';
      case NotReadyState.starting:
        env = runtime = visual = llm = 'done';
        ready = 'active';
      case NotReadyState.failed:
      case NotReadyState.degraded:
        env = runtime = visual = llm = 'done';
        ready = 'failed';
    }
  }
  AssemblyPhaseState of(String s) => switch (s) {
    'done' => AssemblyPhaseState.done,
    'active' => AssemblyPhaseState.active,
    'failed' => AssemblyPhaseState.failed,
    _ => AssemblyPhaseState.waiting,
  };
  String word(AssemblyPhaseState s) => switch (s) {
    AssemblyPhaseState.done => l10n.engineEntryDone,
    AssemblyPhaseState.active => l10n.nrPhaseActive,
    AssemblyPhaseState.failed => l10n.engineEntryFailed,
    AssemblyPhaseState.waiting => l10n.nrPhaseWaiting,
  };
  return [
    (l10n.nrPhaseEnv, of(env)),
    (l10n.nrPhaseRuntime, of(runtime)),
    (l10n.nrPhaseVisual, of(visual)),
    (l10n.nrPhaseLlm, of(llm)),
    (l10n.nrPhaseReady, of(ready)),
  ].map((r) => AssemblyPhase(label: r.$1, state: r.$2, word: word(r.$2))).toList();
}

/// 五段等分时间线（重设计稿 `.timeline`）：
/// done = 实心绿 + 内点；active = 主色实心 + 外环脉冲 1.8s；failed = 实心红 + 段名转红。
class AssemblyTimeline extends StatelessWidget {
  const AssemblyTimeline({super.key, required this.phases});

  final List<AssemblyPhase> phases;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, p) in phases.indexed) ...[
          if (i > 0) Container(width: 14, height: 1.5, margin: const EdgeInsets.only(top: 9), color: palette.line2),
          Expanded(child: _PhaseStep(phase: p)),
        ],
      ],
    );
  }
}

class _PhaseStep extends StatefulWidget {
  const _PhaseStep({required this.phase});

  final AssemblyPhase phase;

  @override
  State<_PhaseStep> createState() => _PhaseStepState();
}

class _PhaseStepState extends State<_PhaseStep> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // active 段的外环脉冲（motion.html：1.8s ease-in-out infinite）——
    // 「它在动」的唯一信号；等待/完成/失败段不起控制器。
    _pulse = AnimationController(vsync: this, duration: AppMotion.nodePulse);
    if (widget.phase.state == AssemblyPhaseState.active) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _PhaseStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase.state == AssemblyPhaseState.active) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = widget.phase.state;
    final Color nodeColor = switch (state) {
      AssemblyPhaseState.done => palette.good,
      AssemblyPhaseState.active => palette.acc,
      AssemblyPhaseState.failed => palette.bad,
      AssemblyPhaseState.waiting => palette.hi,
    };
    final Color labelColor = switch (state) {
      AssemblyPhaseState.active => palette.acc,
      AssemblyPhaseState.failed => palette.bad,
      AssemblyPhaseState.done => palette.ink,
      AssemblyPhaseState.waiting => palette.ink2,
    };
    return Column(
      children: [
        SizedBox(
          width: 30,
          height: 18,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (state == AssemblyPhaseState.active)
                // 外环脉冲：放大 1→1.8 并淡出（Curves.easeOut），节点本体不动。
                FadeTransition(
                  opacity: Tween<double>(
                    begin: 0.45,
                    end: 0,
                  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeOut)),
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 1,
                      end: 1.8,
                    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeOut)),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.acc, width: 2),
                      ),
                    ),
                  ),
                ),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: state == AssemblyPhaseState.waiting ? palette.hi : nodeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: state == AssemblyPhaseState.waiting ? palette.line2 : nodeColor, width: 2),
                ),
                child: state == AssemblyPhaseState.done
                    ? Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: palette.panel, shape: BoxShape.circle),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.phase.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: AppFont.px10_5, fontWeight: FontWeight.w600, color: labelColor),
        ),
        const SizedBox(height: 1),
        Text(
          widget.phase.word,
          style: TextStyle(fontSize: AppFont.px9, color: palette.mut),
        ),
      ],
    );
  }
}
