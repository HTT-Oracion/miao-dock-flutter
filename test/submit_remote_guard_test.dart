import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miao_dock_flutter/features/manga/controller/engine_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/remote_controller.dart';
import 'package:miao_dock_flutter/features/manga/domain/not_ready_state.dart';
import 'package:protocol/protocol.dart';

/// D-129：选了远程翻译但配置无效时，提交要**建任务直接失败**，不进流水线。
void main() {
  ProviderContainer containerWith({required String baseUrl, required String token}) {
    final c = ProviderContainer(
      overrides: [
        translateSourceProvider.overrideWith(_RemoteSource.new),
        remoteConfigProvider.overrideWith(() => _Cfg(RemoteConfig(baseUrl: baseUrl, token: token))),
        mangaSvcClientProvider.overrideWithValue(_Client()),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('token 为空 → 拦下并带上原因', () async {
    final c = containerWith(baseUrl: 'http://127.0.0.1:5180', token: '');
    expect(c.read(queueProvider.notifier).remoteBlocked, isTrue);
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
    expect(c.read(queueProvider.notifier).remoteBlocked, isTrue);
  });

  test('配置有效 → 不拦', () async {
    final c = containerWith(baseUrl: 'http://127.0.0.1:5180', token: 'tk');
    expect(c.read(queueProvider.notifier).remoteBlocked, isFalse);
    final out = await c
        .read(queueProvider.notifier)
        .submit(comicName: '某书', imagePaths: const ['/a.png'], blockedReason: '不该用到');
    expect(out.blocked, isFalse);
    expect((c.read(mangaSvcClientProvider) as _Client).lastFailReason, isNull);
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
