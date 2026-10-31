import 'package:test/test.dart';

import 'package:mangasvc/src/server/routes.dart';

/// mangasvc 服务端断言。
///
/// 每条写明「破坏什么会导致它失败」。
void main() {
  group('路由表与契约一致', () {
    test('路由数 = 52 条（45 客户端方法 + health 双路径 + engine 五条扩展）', () {
      // 破坏点：新增/删除任一路由 → 与客户端契约不再对应，本条失败。
      // 48 = 45 个 MangaSvcClient 方法 + /health 与 /api/v1/health 共用 1 个方法（+1）
      //      + engine/start、engine/stop（D-012 引擎共用开关，客户端暂无对应方法）
      expect(routes.length, 52);
    });

    test('每条路由都有分组且 id 唯一', () {
      final ids = routes.map((r) => r.id).toList();
      // 破坏点：复制粘贴出重复路由 → 后一条永远不生效，本条失败。
      expect(ids.toSet().length, ids.length);
      for (final r in routes) {
        expect(r.group, isNotEmpty);
      }
    });

    test('五个分组齐全', () {
      final groups = routes.map((r) => r.group).toSet();
      // 破坏点：漏掉一整组端点，本条失败。
      expect(groups, containsAll(['health', 'tasks', 'queue', 'library', 'translate', 'engine']));
    });
  });

  group('路由匹配', () {
    test('字面路径精确命中', () {
      final m = matchRoute('GET', '/api/v1/tasks');
      expect(m, isNotNull);
      expect(m!.route.id, 'GET /api/v1/tasks');
    });

    test('通配段捕获参数', () {
      final m = matchRoute('GET', '/api/v1/library/未来回归/chapters/3/files/12');
      expect(m, isNotNull);
      // 破坏点：通配段解析错位 → book/no/seq 三个参数会串，本条失败。
      expect(m!.params['book'], '未来回归');
      expect(m.params['no'], '3');
      expect(m.params['seq'], '12');
    });

    test('段数不等不命中（不做前缀匹配）', () {
      // 破坏点：改成前缀匹配 → /tasks/x/y 会误命中 /tasks/{id}，本条失败。
      expect(matchRoute('GET', '/api/v1/tasks/x/y'), isNull);
    });

    test('方法不匹配不命中', () {
      expect(matchRoute('DELETE', '/api/v1/tasks'), isNull);
    });

    test('未注册路径不命中（调用方回 404）', () {
      // 破坏点：加 catch-all → 未知路径被静默吞掉，本条失败。
      expect(matchRoute('GET', '/api/v1/nope'), isNull);
    });

    test('URL 编码的段由 HTTP 层解码一次（不重复解码）', () {
      // HttpRequest.uri.path 已解码；matchRoute 不得再 decode，否则 %25 → % 会二次变形。
      final m = matchRoute('GET', '/api/v1/library/未来/meta');
      expect(m, isNotNull);
      expect(m!.params['name'], '未来');
    });
  });
}
