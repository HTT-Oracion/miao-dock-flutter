import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miao_dock_flutter/features/manga/controller/engine_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/remote_controller.dart';
import 'package:miao_dock_flutter/features/manga/domain/not_ready_state.dart';
import 'package:protocol/protocol.dart';

/// D-129：选了远程翻译但配置无效时，提交要**建任务直接失败**，不进流水线。
void main() {
  /// 可控的探测结果：模拟设置页【测试连接】。
  RemoteProbe probeOk = const RemoteProbe(ok: true, message: 'ok', engineReady: true);
  Future<RemoteProbe> pingProbe(RemoteConfig cfg) async => probeOk;

  setUp(() {
    probeOk = const RemoteProbe(ok: true, message: 'ok', engineReady: true);
  });

  ProviderContainer containerWith({required String baseUrl, required String token}) {
    final c = ProviderContainer(
      overrides: [
        translateSourceProvider.overrideWith(_RemoteSource.new),
        remoteConfigProvider.overrideWith(() => _Cfg(RemoteConfig(baseUrl: baseUrl, token: token))),
        mangaSvcClientProvider.overrideWithValue(_Client()),
        remotePingProvider.overrideWithValue(pingProbe),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('token 为空 → 拦下并带上原因', () async {
    final c = containerWith(baseUrl: 'http://127.0.0.1:5180', token: '');
    expect(await c.read(queueProvider.notifier).remoteUsable(), isFalse);
    final out = await c
        .read(queueProvider.notifier)
        .submit(comicName: '某书', imagePaths: const ['/a.png'], blockedReason: '远程翻译配置不生效，请到设置页进行配置');
    expect(out.blocked, isTrue);
    final client = c.read(mangaSvcClientProvider) as _Client;
    // 破坏点：没把原因传给服务端 → 任务照常跑流水线。
    expect(client.lastFailReason, '远程翻译配置不生效，请到设置页进行配置');
  });

  test('地址非法（无 scheme）→ 拦下', () async {
    final c = containerWith(baseUrl: '随便什么', token: 'tk');
    expect(await c.read(queueProvider.notifier).remoteUsable(), isFalse);
  });

  test('探测失败时 remoteUsable 为 false（guard 的判定本体）', () async {
    final c = ProviderContainer(
      overrides: [
        translateSourceProvider.overrideWith(_RemoteSource.new),
        remoteConfigProvider.overrideWith(
          () => _Cfg(const RemoteConfig(baseUrl: 'http://127.0.0.1:5180', token: 'tk')),
        ),
        remotePingProvider.overrideWithValue((cfg) async => const RemoteProbe(ok: false, message: '拒绝')),
      ],
    );
    addTearDown(c.dispose);
    // 破坏点：ping 失败仍放行 → 任务会跑进流水线。
    await c.read(remoteVerificationProvider.notifier).verify();
    expect(await c.read(queueProvider.notifier).remoteUsable(), isFalse);
  });

  test('配置有效但未显式校验 → 仍拦截', () async {
    final c = containerWith(baseUrl: 'http://127.0.0.1:5180', token: 'tk');
    expect(await c.read(queueProvider.notifier).remoteUsable(), isFalse);
  });

  test('配置、连接与对面引擎均校验通过 → 不拦', () async {
    final c = containerWith(baseUrl: 'http://127.0.0.1:5180', token: 'tk');
    await c.read(remoteVerificationProvider.notifier).verify();
    expect(await c.read(queueProvider.notifier).remoteUsable(), isTrue);
    final out = await c
        .read(queueProvider.notifier)
        .submit(comicName: '某书', imagePaths: const ['/a.png'], blockedReason: '不该用到');
    expect(out.blocked, isFalse);
    expect((c.read(mangaSvcClientProvider) as _Client).lastFailReason, isNull);
  });

  test('连接成功但对面引擎未就绪 → 校验失败', () async {
    probeOk = const RemoteProbe(ok: true, message: 'ok', engineReady: false);
    final c = containerWith(baseUrl: 'http://127.0.0.1:5180', token: 'tk');
    await c.read(remoteVerificationProvider.notifier).verify();
    expect(c.read(remoteVerificationProvider), RemoteVerificationState.failed);
    expect(await c.read(queueProvider.notifier).remoteUsable(), isFalse);
  });

  test('已通过后修改远程配置 → 立即撤销校验', () async {
    final c = containerWith(baseUrl: 'http://127.0.0.1:5180', token: 'tk');
    await c.read(remoteVerificationProvider.notifier).verify();
    expect(c.read(remoteVerificationProvider), RemoteVerificationState.ready);

    c.read(remoteConfigProvider.notifier).save(token: 'next-token');
    // 破坏点：沿用旧配置的成功结果 → 新令牌未经确认也会保持放行。
    expect(c.read(remoteVerificationProvider), RemoteVerificationState.unverified);
    expect(await c.read(queueProvider.notifier).remoteUsable(), isFalse);
  });
}

class _RemoteSource extends TranslateSourceNotifier {
  @override
  TranslateSource build() => TranslateSource.remote;
}

class _Cfg extends RemoteConfigNotifier {
  _Cfg(this._v);
  final RemoteConfig _v;
  @override
  RemoteConfig build() => _v;
}

class _Client extends FakeMangaSvcClient {
  String? lastFailReason;

  @override
  Future<CreateTaskResponse> createTask({
    required String comicName,
    required List<String> imagePaths,
    String client = 'app',
    String? failReason,
  }) async {
    lastFailReason = failReason;
    return CreateTaskResponse(
      taskId: 't-1',
      comicName: comicName,
      normalizedComicName: comicName,
      outputDir: comicName,
      status: TaskStatus.queued,
      queuePosition: 1,
      createdAt: DateTime(2026, 1, 1),
    );
  }
}
