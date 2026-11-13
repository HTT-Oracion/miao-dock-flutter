import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 图床请求头。
///
/// 🔴 必须给浏览器 UA：Flutter 的 `Image.network` / `NetworkImage` 默认发
/// `Dart/3.x (dart:io)`，网易云图床会把它当爬虫直接回 **403**。
const musicImageHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
};

/// 远程封面：自己用 [HttpClient] 取字节再交给 [Image.memory]。
///
/// 为什么不用 `Image.network`：
/// · 它的 `headers` 在某些版本的实现路径上不保证按调用方给定值发出，
///   而图床（网易云）对 UA 极其敏感 —— 失败表现为「整片封面都没有」，且
///   `errorBuilder` 会把真实原因吞掉；
/// · 自己取字节后可以统一缓存，列表滚动不会反复打图床。
class RemoteCoverImage extends StatefulWidget {
  const RemoteCoverImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallback = const SizedBox.shrink(),
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// 加载中 / 失败时显示的内容（调用方回落渐变占位）。
  final Widget fallback;

  @override
  State<RemoteCoverImage> createState() => _RemoteCoverImageState();
}

class _RemoteCoverImageState extends State<RemoteCoverImage> {
  /// 进程级字节缓存：同一 URL 只下载一次（列表与详情复用同图）。
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};
  static const _maxCacheEntries = 200;

  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RemoteCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    final url = widget.url;
    if (url.isEmpty) return;

    final hit = _cache[url];
    if (hit != null) {
      if (mounted) setState(() => _bytes = hit);
      return;
    }
    if (_failed) return;

    try {
      final bytes = await _fetch(url);
      if (bytes == null) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      if (_cache.length >= _maxCacheEntries) _cache.remove(_cache.keys.first);
      _cache[url] = bytes;
      if (mounted && widget.url == url) setState(() => _bytes = bytes);
    } on Object catch (e) {
      assert(() {
        debugPrint('[music.cover] load failed url=$url err=$e');
        return true;
      }());
      if (mounted) setState(() => _failed = true);
    }
  }

  static Future<Uint8List?> _fetch(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      musicImageHeaders.forEach(req.headers.set);
      final resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) {
        await resp.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return widget.fallback;
    return Image.memory(
      bytes,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => widget.fallback,
    );
  }
}
