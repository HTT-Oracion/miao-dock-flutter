import 'dart:convert';
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

  test('移动端可上传图片字节建单，不依赖手机路径', () async {
    final root = Directory.systemTemp.createTempSync('miao_upload_root_');
    final state = Directory.systemTemp.createTempSync('miao_upload_state_');
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
    final port = await server.start();
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.postUrl(Uri.parse('http://127.0.0.1:$port/api/v1/tasks'));
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'comicName': 'mobile-upload',
        'imagePaths': <String>[],
        'client': 'mobile',
        'images': [
          {'filename': '001.png', 'base64': base64Encode(_png)},
        ],
      }),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();

    // 破坏点：仍把 Android content/cache 路径交给桌面端 → 服务端找不到文件并直接失败。
    expect(response.statusCode, 200, reason: body);
    expect(Directory('${state.path}/remote-uploads').existsSync(), isTrue);
  });

  test('刷新配对令牌后旧令牌立即失效并持久化', () async {
    final root = Directory.systemTemp.createTempSync('miao_token_root_');
    final state = Directory.systemTemp.createTempSync('miao_token_state_');
    final server = MangaSvcServer(portStart: 0, portEnd: 0, rootDir: root.path, stateDir: state.path);
    addTearDown(() async {
      await server.stop();
      root.deleteSync(recursive: true);
      state.deleteSync(recursive: true);
    });
    final port = await server.start();
    final oldToken = server.token!;
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final refresh = await client.postUrl(Uri.parse('http://127.0.0.1:$port/api/v1/pairing/token/refresh'));
    refresh.headers.set('X-Box-Token', oldToken);
    final refreshResponse = await refresh.close();
    final refreshBody = jsonDecode(await utf8.decoder.bind(refreshResponse).join()) as Map<String, dynamic>;
    final newToken = '${refreshBody['token']}';
    expect(newToken, isNot(oldToken));

    Future<int> ping(String token) async {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/api/v1/ping'));
      request.headers.set('X-Box-Token', token);
      return (await request.close()).statusCode;
    }

    expect(await ping(oldToken), 403);
    expect(await ping(newToken), 200);
    expect(File('${state.path}/token').readAsStringSync(), newToken);
  });
}

const _png = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
];
