import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/shell_prefs.dart';
import '../domain/online_error.dart';
import '../domain/online_models.dart';
import 'source_http.dart';

/// 在线页图加载：带源请求头、内存缓存、磁盘缓存。
///
/// 签名 URL 会过期，所以缓存键包含完整 URL；同一章的签名不变时命中。
class OnlineImageLoader {
  OnlineImageLoader({Dio? dio, this.maxBytes = 20 * 1024 * 1024}) : _dio = dio ?? Dio();

  final Dio _dio;
  final int maxBytes;
  final Map<String, Uint8List> _memory = {};

  Future<Uint8List> load(
    ImageLoadingConfig config, {
    required String sourceId,
    List<String> allowedHosts = const [],
  }) async {
    final url = config.url;
    if (url == null || url.isEmpty) {
      throw const OnlineException(OnlineErrorCode.parse, 'empty image url');
    }
    final host = Uri.tryParse(url)?.host ?? '';
    if (allowedHosts.isNotEmpty && !SourceHttp.hostAllowed(host, allowedHosts)) {
      throw const OnlineException(OnlineErrorCode.hostNotAllowed, 'image host not allowed');
    }
    final cached = _memory[url];
    if (cached != null) return cached;
    final disk = await _readDisk(sourceId, url);
    if (disk != null) {
      _remember(url, disk);
      return disk;
    }
    try {
      final response = await _dio
          .get<List<int>>(
            url,
            options: Options(
              method: config.method,
              responseType: ResponseType.bytes,
              followRedirects: true,
              validateStatus: (_) => true,
              headers: config.headers,
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
            ),
          )
          .timeout(const Duration(seconds: 35));
      final bytes = Uint8List.fromList(response.data ?? const <int>[]);
      final status = response.statusCode ?? 0;
      if (status == 403) throw const OnlineException(OnlineErrorCode.blocked, '403');
      if (status == 404) throw const OnlineException(OnlineErrorCode.notFound, '404');
      if (status < 200 || status >= 300) throw OnlineException(OnlineErrorCode.http, 'status $status', status);
      if (bytes.isEmpty) throw const OnlineException(OnlineErrorCode.network, 'empty image');
      if (bytes.length > maxBytes) throw const OnlineException(OnlineErrorCode.http, 'image too large');
      _remember(url, bytes);
      await _writeDisk(sourceId, url, bytes);
      return bytes;
    } on OnlineException {
      rethrow;
    } on DioException catch (e) {
      final code = switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => OnlineErrorCode.timeout,
        _ => OnlineErrorCode.network,
      };
      throw OnlineException(code, e.message ?? '${e.type}');
    } catch (e) {
      throw OnlineException(OnlineErrorCode.network, '$e');
    }
  }

  void _remember(String url, Uint8List bytes) {
    if (_memory.length >= 12) {
      _memory.remove(_memory.keys.first);
    }
    _memory[url] = bytes;
  }

  Future<Uint8List?> _readDisk(String sourceId, String url) async {
    final file = await _cacheFile(sourceId, url);
    if (file == null || !await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDisk(String sourceId, String url, Uint8List bytes) async {
    try {
      final file = await _cacheFile(sourceId, url);
      if (file == null) return;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  Future<File?> _cacheFile(String sourceId, String url) async {
    final root = onlineStateDirectory();
    if (root == null) return null;
    final hash = sha1.convert(url.codeUnits).toString();
    return File('${root.path}/images/$sourceId/$hash.bin');
  }

  void clearMemory() => _memory.clear();
}

final onlineImageLoaderProvider = Provider<OnlineImageLoader>((ref) => OnlineImageLoader());
