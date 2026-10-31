import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/app/shell/readiness.dart';
import 'package:miao_dock_flutter/core/process/service_controller.dart';
import 'package:miao_dock_flutter/core/process/service_supervisor.dart';
import 'package:miao_dock_flutter/features/manga/domain/not_ready_state.dart';

/// P0-D3 断言：侧栏状态点必须同时反映**服务进程**与**引擎**两侧。
///
/// 破坏点：只看引擎 → 服务挂了侧栏仍是黄的（「未启动」），
/// 用户会去点「启动引擎」而不是「重启服务」，方向完全错。
/// 用固定状态替换真实 supervisor。
class FakeStatus extends ServiceStatusNotifier {
  FakeStatus(this._value);

  final ServiceStatus _value;

  @override
  ServiceStatus build() => _value;
}

void main() {
  ProviderContainer containerWith(ServiceStatus status) {
    final c = ProviderContainer(overrides: [serviceStatusProvider.overrideWith(() => FakeStatus(status))]);
    addTearDown(c.dispose);
    return c;
  }

  test('服务进程失败 → 红（优先于引擎状态）', () {
    final c = containerWith(const ServiceStatus(state: ServiceProcessState.failed, error: '端口段全被占用'));
    // 破坏点：服务挂了但引擎没起时只报黄 → 用户走错排查方向，本条失败。
    expect(c.read(shellReadinessProvider), ReadinessLevel.broken);
  });

  test('服务正常但引擎未起 → 黄', () {
    final c = containerWith(const ServiceStatus(state: ServiceProcessState.running, port: 5180, pid: 1));
    expect(c.read(shellReadinessProvider), ReadinessLevel.partial);
  });

  test('移动端不托管服务 → 不因「没有服务」判红', () {
    final c = containerWith(ServiceStatus.unsupported);
    // 破坏点：移动端把 unsupported 当失败 → 侧栏永远红，本条失败。
    expect(c.read(shellReadinessProvider), isNot(ReadinessLevel.broken));
  });
}
