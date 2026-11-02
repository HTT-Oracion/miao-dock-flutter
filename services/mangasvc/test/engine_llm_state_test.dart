import 'package:mangasvc/src/engine/engine_runtime.dart';
import 'package:test/test.dart';

/// D-134 遗留修复：`toStatusView().llm.state` 必须反映 **LLM 真实状态**。
///
/// 修复前直接照抄引擎整体状态 —— L3 缺权重时引擎 running ⇒ UI 以为 LLM 也
/// running ⇒ 侧栏绿点、点翻译才炸。
void main() {
  test('L3 未起（无 pid）→ llm.state = off，即使引擎整体 running', () {
    final rt = EngineRuntime(runtimeRoot: 'definitely-missing', modelsDir: 'also-missing');
    // 模拟「引擎已在跑但 LLM 没起来」：直接打状态字段（测试专用视角）。
    rt.markRunningForTest();
    final view = rt.toStatusView();
    final llm = view['llm'] as Map;
    // 破坏点：照抄引擎状态 → 这里会是 running。
    expect(llm['state'], 'off');
    expect(llm['pid'], isNull);
  });
}
