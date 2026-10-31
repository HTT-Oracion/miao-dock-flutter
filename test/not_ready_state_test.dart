import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import 'package:miao_dock_flutter/features/manga/domain/not_ready_state.dart';

/// 启动引导状态派生断言（D-012）。
///
/// 这些判据错一个，用户就会看到「已就绪但翻译不了」这种自相矛盾的界面，
/// 所以每条都写明破坏点。
void main() {
  EngineStatus statusOf({String engine = 'stopped', String llm = 'stopped', String? stage}) => EngineStatus(
    engine: EngineProcess(state: engine, version: ''),
    llm: LlmProcess(state: llm),
    accel: '',
    warmed: false,
    config: const EngineConfig(translator: '', targetLang: '', detector: '', ocr: '', inpainter: ''),
    models: const ModelStatus(ready: true, sets: {}),
    runtime: const RuntimeProbe(ready: true, checks: []),
    rawStage: stage,
  );

  group('未安装模型', () {
    test('无下载进度 → uninstalled', () {
      final v = deriveNotReadyView(source: TranslateSource.local, status: null, modelsInstalled: false);
      // 破坏点：没模型却显示 installed → 用户点「启动」必然失败，本条失败。
      expect(v.state, NotReadyState.uninstalled);
    });

    test('有下载进度 → downloading（且进度原样透传）', () {
      final v = deriveNotReadyView(
        source: TranslateSource.local,
        status: null,
        modelsInstalled: false,
        downloadProgress: 0.42,
      );
      expect(v.state, NotReadyState.downloading);
      expect(v.downloadProgress, 0.42);
    });
  });

  group('引擎组就绪判定', () {
    test('引擎与 LLM 都 running 才算就绪', () {
      final v = deriveNotReadyView(
        source: TranslateSource.local,
        status: statusOf(engine: 'running', llm: 'running'),
        modelsInstalled: true,
      );
      expect(v.engine, EngineRuntimeState.running);
      expect(v.canTranslate, isTrue);
    });

    test('只有引擎 running、LLM 未起 → 不算就绪', () {
      final v = deriveNotReadyView(
        source: TranslateSource.local,
        status: statusOf(engine: 'running', llm: 'stopped'),
        modelsInstalled: true,
      );
      // 破坏点：只判 engine.state → LLM 没起来也被当成能翻译，本条失败。
      expect(v.engine, isNot(EngineRuntimeState.running));
      expect(v.canTranslate, isFalse);
    });

    test('任一进程 starting → starting', () {
      final v = deriveNotReadyView(
        source: TranslateSource.local,
        status: statusOf(engine: 'running', llm: 'starting'),
        modelsInstalled: true,
      );
      expect(v.state, NotReadyState.starting);
    });

    test('任一进程失败 → failed，并带出阶段', () {
      final v = deriveNotReadyView(
        source: TranslateSource.local,
        status: statusOf(engine: 'failed', llm: 'stopped', stage: 'L2'),
        modelsInstalled: true,
      );
      expect(v.state, NotReadyState.failed);
      expect(v.failedPhase, 'L2');
    });
  });

  group('翻译来源', () {
    test('远程翻译不需要本机引擎，直接可用', () {
      final v = deriveNotReadyView(source: TranslateSource.remote, status: null, modelsInstalled: false);
      // 破坏点：远程来源仍要求本机模型 → 移动端永远不可用，本条失败。
      expect(v.needsLocalEngine, isFalse);
      expect(v.canTranslate, isTrue);
      expect(v.readiness, ReadinessLevel.ready);
    });

    test('本地翻译需要引擎；未启动时 readiness = partial', () {
      final v = deriveNotReadyView(
        source: TranslateSource.local,
        status: statusOf(engine: 'stopped', llm: 'stopped'),
        modelsInstalled: true,
      );
      // 破坏点：readiness 恒为 ready → 侧栏永远绿灯，本条失败。
      expect(v.readiness, ReadinessLevel.partial);
      // 但浏览仍可用（分层带来的收益）
      expect(v.canBrowse, isTrue);
    });

    test('大模型翻译同样需要本机引擎（只是 LLM 换云端）', () {
      expect(TranslateSource.llm.needsEngine, isTrue);
      expect(TranslateSource.llm.requiresLocalRuntime, isTrue);
      // 破坏点：把 llm 当成「不需要本机」→ 不下载引擎就用，必然失败，本条失败。
    });

    test('未知来源抛错，不静默降级', () {
      // 破坏点：parse 返回 local → 配错时看起来像正常用本机，本条失败。
      expect(() => TranslateSource.parse('nonsense'), throwsArgumentError);
    });
  });

  group('服务异常', () {
    test('degraded → 不能浏览也不能翻译，readiness = broken', () {
      final v = NotReadyView(
        state: NotReadyState.degraded,
        engine: EngineRuntimeState.off,
        source: TranslateSource.local,
      );
      // 破坏点：服务挂了还允许浏览 → 界面会一直报错，本条失败。
      expect(v.canBrowse, isFalse);
      expect(v.canTranslate, isFalse);
      expect(v.readiness, ReadinessLevel.broken);
    });
  });
}
