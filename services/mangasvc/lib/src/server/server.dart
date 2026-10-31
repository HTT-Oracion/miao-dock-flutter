import 'dart:async';
import 'dart:io';

import 'handlers.dart';
import 'http.dart';
import 'routes.dart';
import 'security.dart';

/// mangasvc 的 HTTP 服务本体。
///
/// ## 端口段（与客户端探测约定一致）
/// 在 **127.0.0.1:5180–5190** 内「先探测再绑定」：先起的占 5180，被占则顺延。
/// 客户端 `PortProbe` 按同一段逐端口试，靠 `/health` 的 `service` 字段认领。
///
/// ## 单实例语义
/// 不设单实例锁：两个实例会自然落到不同端口，客户端都能认出来。
/// 这与原项目一致（`animesvc` 与 `mangasvc` 同段共存）。
class MangaSvcServer {
  MangaSvcServer({
    this.portStart = 5180,
    this.portEnd = 5190,
    this.rootDir,
    this.engineMode = 'mock',
    this.requireToken = true,
    this.stateDir,
  });

  final int portStart;
  final int portEnd;

  /// 落盘根目录；null = 由 store 决定默认值。
  final String? rootDir;

  /// 引擎模式：`mock`（B 级替身）/ `real`。
  final String engineMode;

  /// 是否要求 `X-Box-Token`（E4：跨设备访问的鉴权面）。测试可关。
  final bool requireToken;

  /// 服务状态目录（令牌 / 隐藏清单）。
  ///
  /// 🔴 与**库根**分开：库根是用户成果（`~/Pictures/...`），状态是产品数据
  /// （`<appData>/MiaoDock/manga/state`）。混在一起会污染用户相册目录。
  /// null = 用 `<库根>/.miao-state`（仅测试便捷路径；生产由 main 显式传）。
  final String? stateDir;

  /// 安全策略（启动时由 [start] 填充 token）。
  late SecurityPolicy _policy = const SecurityPolicy();

  HttpServer? _server;
  String? _token;

  /// 当前服务令牌（父进程要把它传给客户端；`--print-token` 会输出）。
  String? get token => _token;
  late final Handlers _handlers = Handlers(rootDir: rootDir, engineMode: engineMode);

  /// 实际绑定的端口（未启动为 null）。
  int? get port => _server?.port;

  /// 启动服务：在端口段内找到第一个可用端口并开始监听。
  Future<int> start() async {
    Object? lastError;
    for (var p = portStart; p <= portEnd; p++) {
      try {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, p, shared: false);
        _server = server;
        final token = resolveToken(
          stateDir: stateDir ?? '${_handlers.store.rootDir}${Platform.pathSeparator}.miao-state',
          enabled: requireToken,
        );
        _policy = SecurityPolicy(token: token);
        _token = token;
        server.listen(_dispatch);
        await _handlers.init();
        return p;
      } on SocketException catch (e) {
        lastError = e; // 端口被占，试下一个
      }
    }
    throw StateError('mangasvc: $portStart–$portEnd 全段被占用（$lastError）');
  }

  /// 停止服务。
  Future<void> stop() async {
    await _handlers.dispose();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _dispatch(HttpRequest req) async {
    try {
      // 安全层在最外层：Origin 白名单 → CORS 预检 → 令牌。
      final verdict = await guardRequest(req, _policy);
      if (verdict != SecurityVerdict.allow) return;

      final match = matchRouteSegments(req.method, req.uri.pathSegments);
      if (match == null) {
        await writeErrorCode(req.response, 404, 'NOT_FOUND', '端点不存在：${req.method} ${req.uri.path}');
        return;
      }
      await _handlers.handle(req, match);
    } on ServiceError catch (e) {
      // 响应可能已被写（如 SSE 流已开）——此时再写头会抛，吞掉即可。
      try {
        await writeError(req.response, e);
      } catch (_) {}
    } catch (e, st) {
      // 未预期异常也要回信封，不能给客户端一个裸 500。
      try {
        await writeError(
          req.response,
          ServiceError('INTERNAL', '服务内部错误：$e', details: {'stack': st.toString()}, status: 500),
        );
      } catch (_) {}
    }
  }
}

/// 就绪行协议：stdout 打印一行，父进程据此判定「可以开始请求了」。
///
/// 格式固定为 `mangasvc listening on 127.0.0.1:<port>`，与客户端探测解耦：
/// 客户端不解析它，只用它给 `flutter run` / 打包启动脚本一个可等待的信号。
String readyLine(int port) => 'mangasvc listening on 127.0.0.1:$port';
