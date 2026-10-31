import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 引擎客户端（P0-C6d）—— 调 manga-image-translator 的流式翻译端点。
///
/// ## 协议（与原项目 `engine/client.rs` 逐字节一致）
/// `POST /translate/image/stream`，JSON 体 `{image: data:<mime>;base64,…, config: {…}}`。
/// 响应是**帧序列**，每帧 `[code:1B][size:4B 大端][data:size B]`：
///
/// | code | 含义 |
/// |---|---|
/// | 0 | 最终图片字节 |
/// | 1 | 阶段文本（诊断日志） |
/// | 2 | 引擎报错文本 |
/// | 3 | 排队位次 |
/// | 4 | 等待翻译实例（无 data） |
///
/// ## 三个容易做错的地方
/// 1. **超时是空闲超时**：每收到一块就重置，不是总时长。引擎翻一张图可能 2 分钟，
///    用总时长会把正常请求判死；而卡住（不再来数据）必须能被发现。
/// 2. **必须先嗅探图片类型**：把非图片（或空字节）送进引擎，Python 侧会抛
///    一个看不出根因的异常。本地先拦下来，错误码 `BAD_INPUT`。
/// 3. **帧可能被截断**：网络中断时最后一帧的 size 可能大于剩余字节。
///    这时要如实标记 truncated，**不能**当成正常结果。
class EngineClient {
  EngineClient({required this.host, required this.port, this.idleTimeout = const Duration(minutes: 3)});

  final String host;
  final int port;

  /// 空闲超时：连续这么久没收到新数据才判超时。
  final Duration idleTimeout;

  String get baseUrl => 'http://$host:$port';

  /// 翻译一张图。
  Future<TranslateOutcome> translateImage(Uint8List bytes, {Map<String, dynamic>? config}) async {
    final ext = sniffImageType(bytes);
    if (ext == null) {
      // 本地拦截：空字节或非图片。
      return TranslateOutcome.failure(
        EngineError('BAD_INPUT', bytes.isEmpty ? '原图字节为空，拒绝送翻译' : '原图字节不是可识别图片（PNG/JPEG/WEBP）'),
      );
    }

    final payload = jsonEncode({
      'image': 'data:${mimeOfExt(ext)};base64,${base64Encode(bytes)}',
      'config': config ?? const <String, dynamic>{},
    });

    final client = HttpClient();
    // 🔴 引擎是本机 127.0.0.1：绝不能被系统代理劫走。
    //    Dart 的 HttpClient 默认 findProxy 是 direct，这里显式写出来是为了让这条约束可被检索。
    client.findProxy = (_) => 'DIRECT';
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl/translate/image/stream'));
      req.headers.contentType = ContentType.json;
      final body = utf8.encode(payload);
      req.headers.contentLength = body.length;
      req.add(body);

      final resp = await req.close();

      // handler 之前的错误（422 等）走 HTTP 状态码；之后的走流里的 code 2。
      if (resp.statusCode != HttpStatus.ok) {
        final rawBytes = await _readAllWithIdleTimeout(resp);
        return TranslateOutcome.failure(
          normalizeHttpError(resp.statusCode, utf8.decode(rawBytes, allowMalformed: true)),
        );
      }

      final raw = await _readAllWithIdleTimeout(resp);
      final parsed = parseResultStream(raw);

      if (parsed.result != null) {
        final outExt = sniffImageType(parsed.result!);
        if (outExt == null) {
          return TranslateOutcome.failure(
            EngineError('ENGINE_BAD_OUTPUT', '引擎返回的字节不是可识别的图片', details: {'bytes': parsed.result!.length}),
          );
        }
        return TranslateOutcome.success(parsed.result!, outExt, parsed.stageLines);
      }
      if (parsed.error != null) {
        return TranslateOutcome.failure(
          EngineError('ENGINE_ERROR', parsed.error!, details: {'frames': parsed.frameSummary}),
        );
      }
      return TranslateOutcome.failure(
        EngineError('ENGINE_BAD_OUTPUT', '引擎没有返回结果帧', details: {'frames': parsed.frameSummary}),
      );
    } on TimeoutException {
      return TranslateOutcome.failure(EngineError('ENGINE_TIMEOUT', '引擎响应空闲超时（${idleTimeout.inSeconds}s 无新数据）'));
    } on SocketException catch (e) {
      return TranslateOutcome.failure(EngineError('ENGINE_UNAVAILABLE', '连不上引擎：${e.message}'));
    } finally {
      client.close(force: true);
    }
  }

  /// 健康探测（引擎就绪判定用）。
  Future<bool> probeHealth({String path = '/health', Duration timeout = const Duration(seconds: 2)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    client.findProxy = (_) => 'DIRECT';
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl$path')).timeout(timeout);
      final resp = await req.close().timeout(timeout);
      await resp.drain<void>();
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// 读完整个响应，**每收到一块就重置空闲计时**。
  Future<Uint8List> _readAllWithIdleTimeout(HttpClientResponse resp) {
    final builder = BytesBuilder(copy: false);
    final done = Completer<Uint8List>();
    Timer? timer;

    void arm() {
      timer?.cancel();
      timer = Timer(idleTimeout, () {
        if (!done.isCompleted) {
          done.completeError(TimeoutException('idle', idleTimeout));
        }
      });
    }

    arm();
    resp.listen(
      (chunk) {
        builder.add(chunk);
        arm();
      },
      onDone: () {
        timer?.cancel();
        if (!done.isCompleted) done.complete(builder.takeBytes());
      },
      onError: (Object e, StackTrace st) {
        timer?.cancel();
        if (!done.isCompleted) done.completeError(e, st);
      },
      cancelOnError: true,
    );
    return done.future;
  }
}

/// 帧解析结果。
class ParsedStream {
  const ParsedStream({required this.result, required this.error, required this.frames});

  /// code 0 的最终图片字节。
  final Uint8List? result;

  /// code 2 的报错文本。
  final String? error;

  final List<EngineFrame> frames;

  /// 阶段日志行（code 1/3/4 的可读形式），供诊断视图。
  List<String> get stageLines => [
    for (final f in frames)
      if (stageTextOf(f) != null) stageTextOf(f)!,
  ];

  /// 帧摘要（进错误详情）。
  List<Map<String, dynamic>> get frameSummary => [
    for (final f in frames) {'code': f.code, 'size': f.size, 'truncated': f.truncated},
  ];
}

/// 单帧。
class EngineFrame {
  const EngineFrame({required this.code, required this.size, this.text, this.truncated = false});

  final int code;
  final int size;
  final String? text;

  /// 帧被截断（size 大于剩余字节）。
  final bool truncated;
}

/// 解析帧序列（纯函数，易测）。
///
/// 帧头 5 字节：`[code:1][size:4 大端]`。size 超出剩余长度时记 truncated 并停止 ——
/// 这是网络中断的正常形态，不是解析器缺陷。
ParsedStream parseResultStream(Uint8List body) {
  final frames = <EngineFrame>[];
  Uint8List? result;
  String? error;
  var off = 0;

  while (off + 5 <= body.length) {
    final code = body[off];
    final size = (body[off + 1] << 24) | (body[off + 2] << 16) | (body[off + 3] << 8) | body[off + 4];
    final end = off + 5 + size;
    if (end > body.length) {
      frames.add(EngineFrame(code: code, size: size, truncated: true));
      break;
    }
    final data = Uint8List.sublistView(body, off + 5, end);
    var text = <String?>[null];
    if (code == 0) {
      result = Uint8List.fromList(data);
    } else if (code == 1 || code == 2 || code == 3) {
      final t = utf8.decode(data, allowMalformed: true);
      if (code == 2) error = t;
      text[0] = t;
    }
    frames.add(EngineFrame(code: code, size: size, text: text[0]));
    off = end;
  }
  return ParsedStream(result: result, error: error, frames: frames);
}

/// 帧 → 可读日志行；返回 null 表示该帧不产生日志。
String? stageTextOf(EngineFrame f) {
  if (f.code == 4) return '等待翻译实例';
  final t = f.text;
  if (t == null) return null;
  return switch (f.code) {
    1 => t,
    3 => '排队位次 $t',
    2 => '引擎报错：$t',
    _ => null,
  };
}

/// 按魔数嗅探图片类型；不认识返回 null。
///
/// 用**嗅探结果**而不是调用方声称的 mime —— 扩展名与真实内容不符时，
/// 引擎会以一个看不出根因的异常失败。
String? sniffImageType(Uint8List b) {
  if (b.length < 12) return null;
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
  // JPEG: FF D8 FF
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpg';
  // WEBP: "RIFF"…"WEBP"
  if (b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'webp';
  }
  return null;
}

String mimeOfExt(String ext) => switch (ext) {
  'png' => 'image/png',
  'jpg' => 'image/jpeg',
  'webp' => 'image/webp',
  _ => 'application/octet-stream',
};

/// HTTP 状态码 → 引擎错误（保留 FastAPI 的 detail，便于定位）。
EngineError normalizeHttpError(int status, String body) {
  final detail = _readFastApiDetail(body);
  final msg = detail ?? (body.isEmpty ? '引擎返回 HTTP $status' : '引擎返回 HTTP $status：${_truncate(body, 200)}');
  return switch (status) {
    422 => EngineError('ENGINE_BAD_INPUT', msg),
    404 => EngineError('ENGINE_NOT_FOUND', msg),
    >= 500 => EngineError('ENGINE_ERROR', msg),
    _ => EngineError('ENGINE_ERROR', msg),
  };
}

String? _readFastApiDetail(String body) {
  if (body.isEmpty) return null;
  try {
    final m = jsonDecode(body);
    if (m is Map && m['detail'] != null) {
      final d = m['detail'];
      return d is String ? d : jsonEncode(d);
    }
  } catch (_) {
    // 不是 JSON：交给调用方用原文
  }
  return null;
}

String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}…';

/// 引擎错误。
class EngineError {
  const EngineError(this.code, this.message, {this.details = const {}});

  final String code;
  final String message;
  final Map<String, dynamic> details;

  @override
  String toString() => 'EngineError($code): $message';
}

/// 翻译结果。
class TranslateOutcome {
  const TranslateOutcome._({this.image, this.ext, this.stageLines = const [], this.error});

  TranslateOutcome.success(Uint8List image, String ext, List<String> stageLines)
    : this._(image: image, ext: ext, stageLines: stageLines);

  TranslateOutcome.failure(EngineError error) : this._(error: error);

  final Uint8List? image;
  final String? ext;
  final List<String> stageLines;
  final EngineError? error;

  bool get ok => error == null;
}
