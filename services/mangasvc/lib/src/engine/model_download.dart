import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// 模型文件下载（P0-C6b）—— 真实 HTTP、`Range` 续传、sha256 校验。
///
/// ## 三个必须做对的点
/// 1. **续传要看响应码**：带 `Range` 请求后，服务器**可能仍返回 200**（不支持续传）。
///    此时若继续追加写，文件会前段旧数据 + 后段全量数据 ⇒ 静默损坏。
///    正确做法是 200 时清空重下，206 时才追加。
/// 2. **先下 `.part` 再改名**：直接写目标文件的话，中断后目标文件存在但内容不全，
///    上层若用「文件存在」判就绪就会误判。
/// 3. **校验不过要删**：sha256 不符说明文件坏了，留着只会让下次「续传」把坏数据接着往下接。
///
/// ## 暂停语义
/// 取消 = 关闭 HTTP 连接并保留 `.part`。下次同一 URL 会从断点继续。
class ModelDownloader {
  ModelDownloader({required this.modelsDir, HttpClient Function()? httpClientFactory})
    : _clientFactory = httpClientFactory ?? HttpClient.new;

  /// 模型落盘目录（D-016：`<数据根>/manga/state/models-state`）。
  final String modelsDir;

  final HttpClient Function() _clientFactory;

  HttpClient? _active;

  /// 取消当前下载（保留 `.part` 供续传）。
  void cancel() {
    _active?.close(force: true);
    _active = null;
  }

  /// 下载一个文件。
  ///
  /// [sha256] 为期望值（hex）；给定时必校验，不符返回失败。
  /// [onProgress] 参数为（已接收字节, 总字节或 null）。
  Future<DownloadResult> download({
    required String url,
    required String fileName,
    String? sha256,
    void Function(int received, int? total)? onProgress,
  }) async {
    final dir = Directory(modelsDir)..createSync(recursive: true);
    final partPath = '${dir.path}${Platform.pathSeparator}$fileName.part';
    final finalPath = '${dir.path}${Platform.pathSeparator}$fileName';
    final part = File(partPath);

    // 已存在最终文件且校验通过 ⇒ 直接复用（幂等，重跑不重下数 GB）。
    final existing = File(finalPath);
    if (existing.existsSync()) {
      if (sha256 == null) {
        return DownloadResult.success(finalPath, bytes: existing.lengthSync(), skipped: true);
      }
      if (await _sha256Of(finalPath) == sha256.toLowerCase()) {
        return DownloadResult.success(finalPath, bytes: existing.lengthSync(), skipped: true);
      }
      // 校验不过：删掉，走完整下载。
      existing.deleteSync();
    }

    var already = part.existsSync() ? part.lengthSync() : 0;
    final client = _clientFactory();
    // 🔴 Dart 默认 idleTimeout 只有 15s：4 GB 的 gguf 在慢镜像上必然被判定超时
    // （实测断在 `Operation timed out`，而当时只下到几 MB）。
    // 大文件下载必须放宽，否则「能下小文件、下不了大文件」这种问题极难自证。
    client.idleTimeout = const Duration(minutes: 5);
    client.connectionTimeout = const Duration(seconds: 30);
    _active = client;

    try {
      final req = await client.getUrl(Uri.parse(url));
      // 只有确有 .part 时才带 Range；0 字节的 Range 请求会被部分服务器拒绝。
      if (already > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$already-');
      final resp = await req.close();

      // 🔴 服务器不支持续传时会返回 200 而不是 206：必须从头写，不能追加。
      final resuming = already > 0 && resp.statusCode == HttpStatus.partialContent;
      if (resp.statusCode != HttpStatus.ok && resp.statusCode != HttpStatus.partialContent) {
        return DownloadResult.failure('HTTP ${resp.statusCode}（$url）');
      }
      if (already > 0 && !resuming) {
        // 清空重下：否则「旧前段 + 新全量」= 静默损坏。
        already = 0;
        if (part.existsSync()) part.deleteSync();
      }

      final total = resuming
          ? _contentLength(resp) != null
                ? already + _contentLength(resp)!
                : null
          : _contentLength(resp);

      final sink = part.openSync(mode: resuming ? FileMode.append : FileMode.write);
      var received = already;
      try {
        await for (final chunk in resp) {
          sink.writeFromSync(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        sink.closeSync();
      }

      // 长度对不上 ⇒ 连接中途断了。保留 .part 供续传，且**不**改名。
      if (total != null && received < total) {
        return DownloadResult.failure('下载不完整：$received / $total 字节（.part 已保留，可续传）', retryable: true);
      }

      // 校验：不过就删，避免下次把坏数据当断点续。
      if (sha256 != null) {
        final actual = await _sha256Of(partPath);
        if (actual != sha256.toLowerCase()) {
          part.deleteSync();
          return DownloadResult.failure('sha256 校验失败（期望 $sha256，实际 $actual）');
        }
      }

      part.renameSync(finalPath);
      return DownloadResult.success(finalPath, bytes: received);
    } on SocketException catch (e) {
      return DownloadResult.failure('网络错误：${e.message}（.part 已保留，可续传）', retryable: true);
    } on HttpException catch (e) {
      // cancel() 会以 HttpException 的形式结束响应流，这是预期路径而非故障。
      return DownloadResult.failure('下载中断：${e.message}（.part 已保留，可续传）', retryable: true);
    } finally {
      client.close(force: true);
      if (identical(_active, client)) _active = null;
    }
  }

  /// 校验一个已存在文件的 sha256（供「导入本地」与完整性校验复用）。
  Future<String?> hashOf(String path) async {
    if (!File(path).existsSync()) return null;
    return _sha256Of(path);
  }

  static int? _contentLength(HttpClientResponse resp) {
    final v = resp.headers.value(HttpHeaders.contentLengthHeader);
    if (v == null) return null;
    return int.tryParse(v);
  }

  /// 流式计算 sha256（模型动辄数 GB，**不能**一次读进内存）。
  static Future<String> _sha256Of(String path) async {
    final sink = _DigestSink();
    final hasher = sha256.startChunkedConversion(sink);
    await for (final chunk in File(path).openRead()) {
      hasher.add(chunk);
    }
    hasher.close();
    return sink.value.toString();
  }
}

/// 收集 chunked sha256 的结果。
class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// 模型清单里的一个文件（`<modelsDir>/manifest.json` 的 `files[]` 元素）。
class ManifestFile {
  const ManifestFile({required this.url, required this.dest, this.sha256});

  final String url;

  /// 落盘文件名（相对 modelsDir）。
  final String dest;

  /// 期望 sha256（hex）；null = 不校验。
  final String? sha256;
}

/// 下载结果。
class DownloadResult {
  const DownloadResult._({
    required this.ok,
    this.path,
    this.bytes = 0,
    this.error,
    this.retryable = false,
    this.skipped = false,
  });

  const DownloadResult.success(String path, {required int bytes, bool skipped = false})
    : this._(ok: true, path: path, bytes: bytes, skipped: skipped);

  const DownloadResult.failure(String error, {bool retryable = false})
    : this._(ok: false, error: error, retryable: retryable);

  final bool ok;
  final String? path;
  final int bytes;
  final String? error;

  /// 是否值得重试（网络类错误）。
  final bool retryable;

  /// 是否因文件已就绪而跳过下载。
  final bool skipped;

  String get json =>
      jsonEncode({'ok': ok, 'path': path, 'bytes': bytes, 'error': error, 'retryable': retryable, 'skipped': skipped});
}
