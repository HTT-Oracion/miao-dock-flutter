/// 路由表 —— **服务端与客户端契约的单一对照点**。
///
/// 每条 = `METHOD /api/v1/...`，与 `packages/protocol/lib/src/manga_svc_client.dart`
/// 的方法一一对应。路由匹配与「有哪些端点」都从这里读，不散在 handler 里。
///
/// 路径模式支持 `{name}` 段通配；匹配时按段比较，字面段必须相等。
library;

/// 一条路由定义。
class RouteDef {
  const RouteDef({required this.method, required this.pattern, required this.group});

  /// HTTP 方法（大写）。
  final String method;

  /// 路径模式，如 `/api/v1/library/{name}/meta`。
  final String pattern;

  /// 端点分组（tasks / queue / library / translate / engine / health）。
  final String group;

  /// `METHOD pattern` 形式，用于日志与断言。
  String get id => '$method $pattern';

  /// 路径段。
  List<String> get segments => pattern.split('/').where((s) => s.isNotEmpty).toList();
}

/// 全量路由表（48 条 —— 客户端契约 45 个方法 + `/health` 双路径 + start/stop）。
const List<RouteDef> routes = [
  // ── health ──────────────────────────────────────────────────────────────
  RouteDef(method: 'GET', pattern: '/health', group: 'health'),
  RouteDef(method: 'GET', pattern: '/api/v1/health', group: 'health'),

  /// 远程连通性探测（D-045）：**不豁免令牌**。
  ///
  /// 与 `/health` 的区别是刻意的：`/health` 不需要令牌，所以它只能证明「服务在」，
  /// 证明不了「令牌对」。远程端（手机 / 插件）要一次问清三件事：
  /// 能不能连上、令牌对不对、对面引擎起没起 —— 这个端点就是为它准备的。
  RouteDef(method: 'GET', pattern: '/api/v1/ping', group: 'health'),

  // ── tasks ───────────────────────────────────────────────────────────────
  RouteDef(method: 'GET', pattern: '/api/v1/tasks', group: 'tasks'),
  RouteDef(method: 'POST', pattern: '/api/v1/tasks', group: 'tasks'),
  RouteDef(method: 'POST', pattern: '/api/v1/tasks/delete', group: 'tasks'),
  RouteDef(method: 'GET', pattern: '/api/v1/tasks/{taskId}', group: 'tasks'),
  RouteDef(method: 'POST', pattern: '/api/v1/tasks/{taskId}/batches', group: 'tasks'),
  RouteDef(method: 'GET', pattern: '/api/v1/tasks/{taskId}/events', group: 'tasks'),
  RouteDef(method: 'POST', pattern: '/api/v1/tasks/{taskId}/cancel', group: 'tasks'),
  RouteDef(method: 'POST', pattern: '/api/v1/tasks/{taskId}/retry', group: 'tasks'),

  // ── queue ───────────────────────────────────────────────────────────────
  RouteDef(method: 'GET', pattern: '/api/v1/queue', group: 'queue'),

  // ── library ─────────────────────────────────────────────────────────────
  RouteDef(method: 'GET', pattern: '/api/v1/library', group: 'library'),
  RouteDef(method: 'POST', pattern: '/api/v1/library/create', group: 'library'),
  RouteDef(method: 'GET', pattern: '/api/v1/library/{name}/files/{seq}', group: 'library'),
  RouteDef(method: 'GET', pattern: '/api/v1/library/{book}/chapters/{no}/files/{seq}', group: 'library'),
  RouteDef(method: 'GET', pattern: '/api/v1/library/{book}/chapters/{no}/resume', group: 'library'),
  RouteDef(method: 'POST', pattern: '/api/v1/library/{book}/chapters/{no}/resume', group: 'library'),
  RouteDef(method: 'GET', pattern: '/api/v1/library/{book}/chapters/{no}/retranslate', group: 'library'),
  RouteDef(method: 'POST', pattern: '/api/v1/library/{book}/chapters/{no}/retranslate', group: 'library'),
  RouteDef(method: 'POST', pattern: '/api/v1/library/{book}/chapters/{no}/renumber', group: 'library'),
  RouteDef(method: 'GET', pattern: '/api/v1/library/{name}/meta', group: 'library'),
  RouteDef(method: 'POST', pattern: '/api/v1/library/{name}/meta', group: 'library'),
  RouteDef(method: 'GET', pattern: '/api/v1/library/{name}/cover', group: 'library'),
  RouteDef(method: 'POST', pattern: '/api/v1/library/{name}/cover', group: 'library'),
  RouteDef(method: 'DELETE', pattern: '/api/v1/library/{name}/cover', group: 'library'),
  RouteDef(method: 'POST', pattern: '/api/v1/library/{name}/merge', group: 'library'),
  RouteDef(method: 'POST', pattern: '/api/v1/library/{name}/reveal', group: 'library'),
  RouteDef(method: 'POST', pattern: '/api/v1/library/{name}/delete', group: 'library'),
  RouteDef(method: 'POST', pattern: '/api/v1/library/{name}/unhide', group: 'library'),
  RouteDef(method: 'GET', pattern: '/api/v1/library/{name}/retranslate', group: 'library'),
  RouteDef(method: 'POST', pattern: '/api/v1/library/{name}/retranslate', group: 'library'),
  RouteDef(method: 'GET', pattern: '/api/v1/library/{name}/resume', group: 'library'),
  RouteDef(method: 'POST', pattern: '/api/v1/library/{name}/resume', group: 'library'),

  // ── translate ───────────────────────────────────────────────────────────
  RouteDef(method: 'POST', pattern: '/api/v1/translate/text', group: 'translate'),
  RouteDef(method: 'POST', pattern: '/api/v1/translate/stream', group: 'translate'),
  RouteDef(method: 'GET', pattern: '/api/v1/translate/options', group: 'translate'),
  RouteDef(method: 'POST', pattern: '/api/v1/translate/settings', group: 'translate'),
  RouteDef(method: 'POST', pattern: '/api/v1/translate/credentials', group: 'translate'),

  // ── engine ──────────────────────────────────────────────────────────────
  RouteDef(method: 'GET', pattern: '/api/v1/engine/status', group: 'engine'),
  RouteDef(method: 'GET', pattern: '/api/v1/engine/runtime', group: 'engine'),
  RouteDef(method: 'GET', pattern: '/api/v1/engine/options', group: 'engine'),
  RouteDef(method: 'POST', pattern: '/api/v1/engine/settings', group: 'engine'),
  RouteDef(method: 'POST', pattern: '/api/v1/engine/unload', group: 'engine'),
  RouteDef(method: 'POST', pattern: '/api/v1/engine/models/verify', group: 'engine'),
  RouteDef(method: 'POST', pattern: '/api/v1/engine/models/download', group: 'engine'),
  RouteDef(method: 'POST', pattern: '/api/v1/engine/models/download/pause', group: 'engine'),
  // D-012：引擎与 LLM 共用开关，故有 start / stop 两个动作端点
  RouteDef(method: 'POST', pattern: '/api/v1/engine/start', group: 'engine'),
  RouteDef(method: 'POST', pattern: '/api/v1/engine/stop', group: 'engine'),
  // D-027：装配整个引擎目录（按平台 + 后端），进度走 GET
  RouteDef(method: 'POST', pattern: '/api/v1/engine/install', group: 'engine'),
  RouteDef(method: 'GET', pattern: '/api/v1/engine/install', group: 'engine'),
  RouteDef(method: 'POST', pattern: '/api/v1/engine/deps/rebuild', group: 'engine'),
  RouteDef(method: 'GET', pattern: '/api/v1/engine/deps', group: 'engine'),
];

/// 路由匹配结果。
class RouteMatch {
  const RouteMatch({required this.route, required this.params});

  final RouteDef route;

  /// 通配段的值（按出现顺序，键为 `{name}` 里的 name）。
  final Map<String, String> params;
}

/// 匹配一条请求；未命中返回 null（调用方回 404 + 错误信封）。
///
/// 匹配规则：段数必须相等；字面段精确相等；`{...}` 段吞任意非空值。
/// **不做前缀匹配** —— `/tasks/x/y` 不会命中 `/tasks/{id}`。
RouteMatch? matchRoute(String method, String path) =>
    matchRouteSegments(method, path.split('/').where((s) => s.isNotEmpty).toList());

/// 按**已解码的段**匹配。
///
/// 调用方应传 `HttpRequest.uri.pathSegments`（框架保证已解码），
/// 不要传 `uri.path` 再自己 decode —— 客户端没编码时会对 `%` 二次解码。
RouteMatch? matchRouteSegments(String method, List<String> segs) {
  for (final r in routes) {
    if (r.method != method.toUpperCase()) continue;
    final pat = r.segments;
    if (pat.length != segs.length) continue;
    final params = <String, String>{};
    var ok = true;
    for (var i = 0; i < pat.length; i++) {
      final p = pat[i];
      if (p.startsWith('{') && p.endsWith('}')) {
        if (segs[i].isEmpty) {
          ok = false;
          break;
        }
        params[p.substring(1, p.length - 1)] = segs[i];
      } else if (p != segs[i]) {
        ok = false;
        break;
      }
    }
    if (ok) return RouteMatch(route: r, params: params);
  }
  return null;
}
