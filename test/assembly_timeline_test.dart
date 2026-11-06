import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/engine_install_controller.dart';
import 'package:miao_dock_flutter/features/manga/domain/not_ready_state.dart';
import 'package:miao_dock_flutter/features/manga/ui/notready/assembly_timeline.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 装配五段时间线断言（重设计稿 guide.html）——
/// 推导是纯函数：破坏「段状态判定顺序」的任何改动都会让对应条目失败。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  List<AssemblyPhase> phasesOf(NotReadyState state, List<InstallEntry> entries) => assemblyPhases(l10n, state, entries);

  test('未装配且无活动 ⇒ 全等待（磁盘不会自己变，禁止假「进行中」）', () {
    final phases = phasesOf(NotReadyState.uninstalled, const []);
    expect(phases.every((p) => p.state == AssemblyPhaseState.waiting), isTrue);
  });

  test('已装配未启动 ⇒ 前四段完成、就绪等待', () {
    final phases = phasesOf(NotReadyState.installed, const []);
    expect(phases.take(4).every((p) => p.state == AssemblyPhaseState.done), isTrue);
    expect(phases.last.state, AssemblyPhaseState.waiting);
  });

  test('启动中 ⇒ 就绪段进行中（「它在动」的唯一信号）', () {
    final phases = phasesOf(NotReadyState.starting, const []);
    expect(phases.last.state, AssemblyPhaseState.active);
  });

  test('失败 ⇒ 就绪段失败（重启无意义，由动作区换主按钮）', () {
    final phases = phasesOf(NotReadyState.failed, const []);
    expect(phases.last.state, AssemblyPhaseState.failed);
  });

  test('有下载活动 ⇒ 按条目 id 关键词归段（visual → 视觉段进行中）', () {
    const entries = [
      InstallEntry(id: 'runtime-deps', state: 'done', sizeMb: 600),
      InstallEntry(id: 'visual-qwen2-vl', state: 'running', sizeMb: 1900, percent: 0.4),
      InstallEntry(id: 'llm-nllb', state: 'waiting', sizeMb: 2100),
    ];
    final phases = phasesOf(NotReadyState.downloading, entries);
    expect(phases[0].state, AssemblyPhaseState.done); // 环境准备
    expect(phases[1].state, AssemblyPhaseState.done); // 运行环境
    expect(phases[2].state, AssemblyPhaseState.active); // 视觉模型
    expect(phases[3].state, AssemblyPhaseState.waiting); // 翻译模型
  });

  testWidgets('时间线渲染五段并标注状态词（active 段外环脉冲）', (tester) async {
    const phases = [
      AssemblyPhase(label: '环境准备', state: AssemblyPhaseState.done, word: '完成'),
      AssemblyPhase(label: '运行环境', state: AssemblyPhaseState.done, word: '完成'),
      AssemblyPhase(label: '视觉模型', state: AssemblyPhaseState.active, word: '进行中'),
      AssemblyPhase(label: '翻译模型', state: AssemblyPhaseState.waiting, word: '等待'),
      AssemblyPhase(label: '就绪', state: AssemblyPhaseState.waiting, word: '等待'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
        home: const Scaffold(body: AssemblyTimeline(phases: phases)),
      ),
    );
    // active 段的脉冲控制器在循环播放，pumpAndSettle 永不停止 ⇒ 定点 pump。
    for (final label in ['环境准备', '运行环境', '视觉模型', '翻译模型', '就绪']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('等待'), findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 100));
  });
}
