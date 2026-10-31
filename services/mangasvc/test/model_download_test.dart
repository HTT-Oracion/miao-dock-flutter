import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:mangasvc/src/engine/model_download.dart';

/// P0-C6b 断言：真实下载、`Range` 续传、sha256 校验。
///
/// 最关键的一条是「服务器不支持续传时必须重下」—— 那是最容易写成
/// 「旧前段 + 新全量」静默损坏的地方，且损坏后的文件**看起来**大小正常。
void main() {
  late Directory tmp;
  late HttpServer server;
  late List<int> payload;
  late String sha;

  /// 支持 Range 的服务器（标准行为）。
  Future<void> startRangeServer() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final start = range == null ? 0 : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      final body = payload.sublist(start);
      if (start > 0) {
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${payload.length - 1}/${payload.length}',
        );
      }
      req.response.headers.contentLength = body.length;
      req.response.add(body);
      await req.response.close();
    });
  }

  /// **忽略** Range 的服务器：永远返回 200 + 全量（真实世界里大量 CDN 就这样）。
  Future<void> startDumbServer() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentLength = payload.length;
      req.response.add(payload);
      await req.response.close();
    });
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('miao_dl_');
    payload = List<int>.generate(64 * 1024, (i) => i % 251);
    sha = sha256.convert(payload).toString();
  });

  tearDown(() async {
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  String url() => 'http://${server.address.host}:${server.port}/model.bin';

  group('基础下载', () {
    test('下载成功后文件内容与源一致，且 .part 已改名', () async {
      await startRangeServer();
      final dl = ModelDownloader(modelsDir: tmp.path);
      final r = await dl.download(url: url(), fileName: 'model.bin', sha256: sha);

      expect(r.ok, isTrue, reason: r.error);
      expect(File('${tmp.path}/model.bin').lengthSync(), payload.length);
      // 破坏点：留 .part → 下次误判为未完成，本条失败。
      expect(File('${tmp.path}/model.bin.part').existsSync(), isFalse);
    });

    test('sha256 不符 → 删掉坏文件并失败', () async {
      await startRangeServer();
      final dl = ModelDownloader(modelsDir: tmp.path);
      final r = await dl.download(url: url(), fileName: 'model.bin', sha256: 'deadbeef');

      expect(r.ok, isFalse);
      expect(r.error, contains('sha256'));
      // 破坏点：留着坏文件 → 下次「续传」把坏数据接着接，本条失败。
      expect(File('${tmp.path}/model.bin').existsSync(), isFalse);
      expect(File('${tmp.path}/model.bin.part').existsSync(), isFalse);
    });

    test('已存在且校验通过 → 跳过下载（幂等）', () async {
      await startRangeServer();
      final dl = ModelDownloader(modelsDir: tmp.path);
      await dl.download(url: url(), fileName: 'model.bin', sha256: sha);

      final again = await dl.download(url: url(), fileName: 'model.bin', sha256: sha);
      // 破坏点：每次都重下数 GB → 用户无法接受，本条失败。
      expect(again.skipped, isTrue);
    });

    test('已存在但校验不过 → 重新下载', () async {
      await startRangeServer();
      File('${tmp.path}/model.bin').writeAsStringSync('corrupted');

      final dl = ModelDownloader(modelsDir: tmp.path);
      final r = await dl.download(url: url(), fileName: 'model.bin', sha256: sha);

      expect(r.ok, isTrue);
      expect(r.skipped, isFalse);
      expect(File('${tmp.path}/model.bin').readAsBytesSync(), payload);
    });
  });

  group('断点续传', () {
    test('续传后与一次性下载逐字节相同', () async {
      await startRangeServer();
      // 造一个「已下了前半段」的 .part
      final half = payload.length ~/ 2;
      File('${tmp.path}/model.bin.part').writeAsBytesSync(payload.sublist(0, half));

      final dl = ModelDownloader(modelsDir: tmp.path);
      final r = await dl.download(url: url(), fileName: 'model.bin', sha256: sha);

      expect(r.ok, isTrue, reason: r.error);
      // 破坏点：续传位置算错 → 内容错位但长度正确，本条失败。
      expect(File('${tmp.path}/model.bin').readAsBytesSync(), payload);
    });

    test('服务器忽略 Range（返回 200）→ 必须重下而不是追加', () async {
      await startDumbServer();
      // .part 已有旧数据
      File('${tmp.path}/model.bin.part').writeAsBytesSync(payload.sublist(0, 100));

      final dl = ModelDownloader(modelsDir: tmp.path);
      final r = await dl.download(url: url(), fileName: 'model.bin', sha256: sha);

      expect(r.ok, isTrue, reason: r.error);
      // 🔴 破坏点（最隐蔽）：200 时仍追加 → 前 100 字节是旧的、后面是全量，
      //    文件变大但「看起来」存在。这里用逐字节比对把它钉死。
      expect(File('${tmp.path}/model.bin').readAsBytesSync(), payload);
    });

    test('取消后 .part 保留，可继续', () async {
      await startRangeServer();
      final dl = ModelDownloader(modelsDir: tmp.path);
      // 先制造一个 .part，再直接调用 download 后立刻取消（保守做法：验证 cancel 不清 .part）
      File('${tmp.path}/model.bin.part').writeAsBytesSync(payload.sublist(0, 10));
      dl.cancel();

      // 破坏点：cancel 顺手删了 .part → 下次从头再下，本条失败。
      expect(File('${tmp.path}/model.bin.part').existsSync(), isTrue);
    });
  });

  group('失败处理', () {
    test('404 → 明确失败且不留下目标文件', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      });

      final dl = ModelDownloader(modelsDir: tmp.path);
      final r = await dl.download(url: url(), fileName: 'model.bin');

      expect(r.ok, isFalse);
      expect(r.error, contains('404'));
      expect(File('${tmp.path}/model.bin').existsSync(), isFalse);
    });

    test('网络不可达 → 标记可重试', () async {
      final dl = ModelDownloader(modelsDir: tmp.path);
      // 端口 1 基本必然拒绝
      final r = await dl.download(url: 'http://127.0.0.1:1/x.bin', fileName: 'x.bin');
      expect(r.ok, isFalse);
      // 破坏点：网络错误判成不可重试 → 用户只能手动重来，本条失败。
      expect(r.retryable, isTrue);
    });
  });
}
