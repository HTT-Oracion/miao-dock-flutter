import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/app/remote_autostart.dart';
import 'package:miao_dock_flutter/features/manga/controller/engine_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/remote_controller.dart';
import 'package:miao_dock_flutter/features/manga/domain/not_ready_state.dart';

/// D-165：启动即校验远程配置（不再要求用户先点一次「校验远程配置」）。
///
/// 破坏点：去掉 `RemoteAutoVerify` 的自动探测 → 首条用例里 `calls` 为 0、
/// 状态停在 `unverified`；把「配置不完整不探测」的守卫删掉 → 第三条用例
/// 会真的发探测并落 `failed`。
class _RemoteSource extends TranslateSourceNotifier {
  @override
  TranslateSource build() => TranslateSource.remote;
}

class _LocalSource extends TranslateSourceNotifier {
  @override
  TranslateSource build() => TranslateSource.local;
}

class _FixedConfig extends RemoteConfigNotifier {
  _FixedConfig(this.cfg);

  final RemoteConfig cfg;

  @override
  RemoteConfig build() => cfg;
}

const _valid = RemoteConfig(baseUrl: 'http://192.168.1.2:5180', token: 'token');

void main() {
  Widget host(ProviderContainer container) => UncontrolledProviderScope(
    container: container,
    child: const RemoteAutoVerify(child: SizedBox()),
  );

  testWidgets('远程来源 + 配置完整：启动首帧后自动进入校验并落地结果', (tester) async {
    var calls = 0;
    final probe = Completer<RemoteProbe>();
    final container = ProviderContainer(
      overrides: [
        translateSourceProvider.overrideWith(_RemoteSource.new),
        remoteConfigProvider.overrideWith(() => _FixedConfig(_valid)),
        remotePingProvider.overrideWithValue((_) {
          calls += 1;
          return probe.future;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(host(container));
    await tester.pump();

    // 启动后无需任何点击，就已经在探测了（卡片「正在校验远程配置」不是摆设）。
    expect(calls, 1);
    expect(container.read(remoteVerificationProvider), RemoteVerificationState.checking);

    probe.complete(const RemoteProbe(ok: true, message: 'ok', engineReady: true));
    await tester.pump();

    expect(container.read(remoteVerificationProvider), RemoteVerificationState.ready);
  });

  testWidgets('本地来源：不探测远程', (tester) async {
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        translateSourceProvider.overrideWith(_LocalSource.new),
        remotePingProvider.overrideWithValue((_) async {
          calls += 1;
          return const RemoteProbe(ok: true, message: 'ok', engineReady: true);
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(host(container));
    await tester.pump();
    await tester.pump();

    // 破坏点：不分来源一律探测 → 桌面本机翻译也会打一次远程 ping。
    expect(calls, 0);
    expect(container.read(remoteVerificationProvider), RemoteVerificationState.unverified);
  });

  testWidgets('配置不完整：不探测，也不落「失败」', (tester) async {
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        translateSourceProvider.overrideWith(_RemoteSource.new),
        remoteConfigProvider.overrideWith(() => _FixedConfig(const RemoteConfig(baseUrl: '', token: ''))),
        remotePingProvider.overrideWithValue((_) async {
          calls += 1;
          return const RemoteProbe(ok: true, message: 'ok', engineReady: true);
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(host(container));
    await tester.pump();
    await tester.pump();

    // 破坏点：无守卫直接 verify() → 首次打开就红屏「远程连接失败」。
    expect(calls, 0);
    expect(container.read(remoteVerificationProvider), RemoteVerificationState.unverified);
  });
}
