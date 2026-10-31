import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/manga/controller/engine_ready_controller.dart';

/// D-037：漫画模块门禁的判定顺序。
void main() {
  MangaGateState gate({
    bool loading = false,
    EnginePresence presence = EnginePresence.complete,
    bool installing = false,
    bool installError = false,
    bool serviceBroken = false,
    bool running = false,
    bool starting = false,
    bool failed = false,
    bool needsLocal = true,
  }) => deriveMangaGate(
    presenceLoading: loading,
    presence: presence,
    installing: installing,
    installError: installError,
    serviceBroken: serviceBroken,
    engineRunning: running,
    engineStarting: starting,
    engineFailed: failed,
    needsLocalEngine: needsLocal,
  );

  test('快检中 → checking（不能先画未装配）', () {
    // 破坏点：检查中直接画「未装配」→ 每次进模块闪一下像故障，本条失败。
    expect(gate(loading: true), MangaGateState.checking);
  });

  test('没装 → notAssembled（即使引擎也没起）', () {
    // 破坏点：先判引擎 → 「没装」被报成「引擎没启动」，用户点启动永远失败，本条失败。
    expect(gate(presence: EnginePresence.absent), MangaGateState.notAssembled);
    expect(gate(presence: EnginePresence.partial), MangaGateState.notAssembled);
  });

  test('同时「没装」与「服务异常」→ 报未装配（装配优先级更高）', () {
    // 破坏点：先判服务 → 用户看到「服务异常」去重启服务，而真正问题是没装，本条失败。
    expect(gate(presence: EnginePresence.absent, serviceBroken: true), MangaGateState.notAssembled);
  });

  test('装配中 → downloading', () {
    expect(gate(presence: EnginePresence.absent, installing: true), MangaGateState.downloading);
  });

  test('装好了但服务异常 → degraded（不是未装配）', () {
    // 破坏点：服务挂了报「未装配」→ 用户会去重下 4 GB，本条失败。
    expect(gate(serviceBroken: true), MangaGateState.degraded);
  });

  test('装好了、引擎未启动 / 启动中 / 失败 / 就绪', () {
    expect(gate(), MangaGateState.installed);
    expect(gate(starting: true), MangaGateState.starting);
    expect(gate(failed: true), MangaGateState.failed);
    expect(gate(running: true), MangaGateState.ready);
  });

  test('远程翻译不拦（本机不需要引擎）', () {
    // 破坏点：远程来源也被装配缺失拦住 → 移动端永远进不去，本条失败。
    expect(gate(presence: EnginePresence.absent, needsLocal: false), MangaGateState.ready);
  });
}
