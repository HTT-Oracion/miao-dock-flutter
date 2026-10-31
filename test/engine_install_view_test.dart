import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/manga/controller/engine_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/engine_install_controller.dart';
import 'package:miao_dock_flutter/features/manga/domain/not_ready_state.dart';

/// D-033：引导页六态必须由**真实装配状态**驱动。
class FakeInstall extends EngineInstallNotifier {
  FakeInstall(this._value);

  final EngineInstallState _value;

  @override
  EngineInstallState build() => _value;
}

void main() {
  ProviderContainer containerWith(EngineInstallState st) {
    final c = ProviderContainer(overrides: [engineInstallProvider.overrideWith(() => FakeInstall(st))]);
    addTearDown(c.dispose);
    return c;
  }

  test('装配中 → downloading，且进度按真实值透传', () {
    final c = containerWith(
      const EngineInstallState(running: true, index: 1, total: 3, entryId: 'engine_source', percent: 0.42),
    );
    final v = c.read(notReadyViewProvider);
    // 破坏点：装配中仍显示「未装配」→ 用户点两次下载，本条失败。
    expect(v.state, NotReadyState.downloading);
    expect(v.downloadProgress, 0.42);
  });

  test('无真实进度时 downloadProgress 为 null（不编造百分比）', () {
    final c = containerWith(const EngineInstallState(running: true, index: 0, total: 3));
    // 破坏点：没有来源也画 0% → 与设计稿 §07 冲突，本条失败。
    expect(c.read(notReadyViewProvider).downloadProgress, isNull);
  });

  test('装配失败 → failed，并把服务端日志交给 UI', () {
    final c = containerWith(
      const EngineInstallState(error: 'HTTP 404', logs: ['[install] ↓ python', '[install] ✗ 下载失败：HTTP 404']),
    );
    final v = c.read(notReadyViewProvider);
    // 破坏点：失败后仍停在 downloading → 用户永远等下去，本条失败。
    expect(v.state, NotReadyState.failed);
    expect(v.logs.join('\n'), contains('下载失败'));
  });

  test('装配完成 → 已装未启动', () {
    final c = containerWith(const EngineInstallState(done: true));
    // 破坏点：完成仍显示未装配 → 用户重复下载 4 GB，本条失败。
    expect(c.read(notReadyViewProvider).state, NotReadyState.installed);
  });
}
