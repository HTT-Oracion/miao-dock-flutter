import 'dart:io';

import 'package:mangasvc/src/server/handlers.dart';
import 'package:mangasvc/src/server/server.dart';
import 'package:test/test.dart';

void main() {
  test('服务监听所有 IPv4 网卡，允许局域网设备连接', () async {
    final root = Directory.systemTemp.createTempSync('miao_remote_root_');
    final state = Directory.systemTemp.createTempSync('miao_remote_state_');
    final server = MangaSvcServer(
      portStart: 0,
      portEnd: 0,
      rootDir: root.path,
      stateDir: state.path,
      requireToken: false,
    );
    addTearDown(() async {
      await server.stop();
      root.deleteSync(recursive: true);
      state.deleteSync(recursive: true);
    });

    await server.start();
    // 破坏点：改回 loopbackIPv4 → Android 使用 Mac 局域网地址时永远连接失败。
    expect(server.listenAddress, InternetAddress.anyIPv4.address);
  });

  test('远程就绪要求引擎与 LLM 同时 running', () {
    Map<String, dynamic> status(String engine, String llm) => {
      'engine': {'state': engine},
      'llm': {'state': llm},
    };

    expect(engineReadyOf(status('running', 'running')), isTrue);
    expect(engineReadyOf(status('running', 'off')), isFalse);
    expect(engineReadyOf(status('off', 'running')), isFalse);
  });
}
