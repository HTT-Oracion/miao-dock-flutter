import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:mangasvc/src/engine/engine_client.dart';

/// P0-C6d 断言：帧协议解析、图片嗅探、空闲超时、错误归一。
void main() {
  /// 造一帧：`[code][size 4B 大端][data]`
  Uint8List frame(int code, List<int> data) {
    final b = BytesBuilder();
    b.addByte(code);
    b.add([(data.length >> 24) & 0xFF, (data.length >> 16) & 0xFF, (data.length >> 8) & 0xFF, data.length & 0xFF]);
    b.add(data);
    return b.takeBytes();
  }

  /// 最小合法 PNG 头（够嗅探用）。
  final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D]);
  final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1]);
  final webpBytes = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0x24, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);

  group('图片嗅探', () {
    test('识别 PNG / JPEG / WEBP', () {
      // 破坏点：只认扩展名不信内容 → 伪造扩展名的非图片被送进引擎，本条失败。
      expect(sniffImageType(pngBytes), 'png');
      expect(sniffImageType(jpegBytes), 'jpg');
      expect(sniffImageType(webpBytes), 'webp');
    });

    test('非图片与空字节返回 null', () {
      expect(sniffImageType(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])), isNull);
      expect(sniffImageType(Uint8List(0)), isNull);
    });
  });

  group('帧解析', () {
    test('code 0 取出结果字节', () {
      final body = frame(0, pngBytes);
      final p = parseResultStream(body);
      // 破坏点：size 解析用小端 → 结果字节错位，本条失败。
      expect(p.result, pngBytes);
      expect(p.error, isNull);
    });

    test('code 2 取出报错文本', () {
      final p = parseResultStream(frame(2, utf8.encode('模型未加载')));
      expect(p.error, '模型未加载');
      expect(p.result, isNull);
    });

    test('code 1/3/4 变成阶段日志', () {
      final body = BytesBuilder()
        ..add(frame(1, utf8.encode('检测文本')))
        ..add(frame(3, utf8.encode('2')))
        ..add(frame(4, const []));
      final p = parseResultStream(body.takeBytes());
      final lines = p.stageLines;
      // 破坏点：丢掉 3/4 帧 → 诊断里看不到「在排队」，本条失败。
      expect(lines, contains('检测文本'));
      expect(lines, contains('排队位次 2'));
      expect(lines, contains('等待翻译实例'));
    });

    test('截断帧被标记而不是当成正常结果', () {
      final good = frame(1, utf8.encode('ok'));
      // 声明 100 字节但只给 3 字节
      final truncated = Uint8List.fromList([1, 0, 0, 0, 100, 65, 66, 67]);
      final p = parseResultStream(Uint8List.fromList([...good, ...truncated]));
      // 破坏点：越界读或静默忽略 → 截断被当成完整结果，本条失败。
      expect(p.frames.last.truncated, isTrue);
      expect(p.result, isNull);
    });

    test('多帧顺序被保留', () {
      final body = BytesBuilder()
        ..add(frame(1, utf8.encode('a')))
        ..add(frame(1, utf8.encode('b')))
        ..add(frame(0, pngBytes));
      final p = parseResultStream(body.takeBytes());
      expect(p.frames.length, 3);
      expect(p.stageLines, ['a', 'b']);
      expect(p.result, pngBytes);
    });
  });

  group('HTTP 往返（真实 stub 引擎）', () {
    late HttpServer server;

    Future<void> serve(Future<void> Function(HttpRequest) handler) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(handler);
    }

    tearDown(() async => server.close(force: true));

    EngineClient clientFor(Duration? idle) =>
        EngineClient(host: '127.0.0.1', port: server.port, idleTimeout: idle ?? const Duration(seconds: 5));

    test('成功路径：请求体是 data URI，结果按帧取回', () async {
      String? receivedBody;
      await serve((req) async {
        receivedBody = await utf8.decoder.bind(req).join();
        req.response.statusCode = 200;
        req.response.add(frame(1, utf8.encode('阶段一')));
        req.response.add(frame(0, pngBytes));
        await req.response.close();
      });

      final out = await clientFor(null).translateImage(pngBytes);
      expect(out.ok, isTrue, reason: out.error?.message);
      expect(out.image, pngBytes);
      expect(out.ext, 'png');
      // 破坏点：用 multipart 而不是 JSON+data URI → 引擎 422，本条失败。
      final sent = jsonDecode(receivedBody!) as Map;
      expect(sent['image'], startsWith('data:image/png;base64,'));
    });

    test('非图片输入在本地被拦下，不发请求', () async {
      var hit = false;
      await serve((req) async {
        hit = true;
        await req.response.close();
      });

      final out = await clientFor(null).translateImage(Uint8List.fromList(List.filled(20, 7)));
      // 破坏点：本地不拦 → 引擎抛看不懂的异常，本条失败。
      expect(out.ok, isFalse);
      expect(out.error!.code, 'BAD_INPUT');
      expect(hit, isFalse);
    });

    test('流里 code 2 → ENGINE_ERROR，带引擎原文', () async {
      await serve((req) async {
        await req.drain<void>();
        req.response.statusCode = 200;
        req.response.add(frame(2, utf8.encode('CUDA out of memory')));
        await req.response.close();
      });

      final out = await clientFor(null).translateImage(pngBytes);
      expect(out.ok, isFalse);
      expect(out.error!.code, 'ENGINE_ERROR');
      expect(out.error!.message, contains('CUDA'));
    });

    test('HTTP 422 → ENGINE_BAD_INPUT 且保留 detail', () async {
      await serve((req) async {
        await req.drain<void>();
        req.response.statusCode = 422;
        req.response.write(jsonEncode({'detail': 'config 缺 target_lang'}));
        await req.response.close();
      });

      final out = await clientFor(null).translateImage(pngBytes);
      expect(out.ok, isFalse);
      // 破坏点：笼统报「引擎返回 422」→ 用户与排障者都不知道缺什么，本条失败。
      expect(out.error!.code, 'ENGINE_BAD_INPUT');
      expect(out.error!.message, contains('target_lang'));
    });

    test('结果字节不是图片 → ENGINE_BAD_OUTPUT', () async {
      await serve((req) async {
        await req.drain<void>();
        req.response.statusCode = 200;
        req.response.add(frame(0, utf8.encode('not an image at all')));
        await req.response.close();
      });

      final out = await clientFor(null).translateImage(pngBytes);
      // 破坏点：信任引擎自称的输出 → 把垃圾字节写进译文，本条失败。
      expect(out.ok, isFalse);
      expect(out.error!.code, 'ENGINE_BAD_OUTPUT');
    });

    test('长时间无新数据 → ENGINE_TIMEOUT（空闲超时，不是总时长）', () async {
      await serve((req) async {
        await req.drain<void>();
        req.response.statusCode = 200;
        req.response.add(frame(1, utf8.encode('开始')));
        await req.response.flush();
        // 只发一帧然后挂住不发
        await Future<void>.delayed(const Duration(seconds: 30));
        await req.response.close();
      });

      final out = await clientFor(const Duration(milliseconds: 300)).translateImage(pngBytes);
      // 破坏点：用总时长超时 → 慢但正常的请求被判死；用无限等待 → 永远挂着，本条失败。
      expect(out.ok, isFalse);
      expect(out.error!.code, 'ENGINE_TIMEOUT');
    });

    test('连接被拒 → ENGINE_UNAVAILABLE', () async {
      await serve((req) async => req.response.close());
      final port = server.port;
      await server.close(force: true);

      final out = await EngineClient(host: '127.0.0.1', port: port).translateImage(pngBytes);
      // 破坏点：把连不上当普通错误 → 引导页无法区分「引擎没起」与「翻译失败」，本条失败。
      expect(out.error!.code, 'ENGINE_UNAVAILABLE');
      // 让 tearDown 仍能 close
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });
  });
}
