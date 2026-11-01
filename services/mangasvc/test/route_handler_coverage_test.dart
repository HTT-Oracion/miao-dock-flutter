import 'dart:io';

import 'package:mangasvc/src/server/routes.dart';
import 'package:test/test.dart';

/// D-089：**每条路由都必须有 handler 分支**。
///
/// 背景：曾经出现过「路由表声明了 6 个 POST，switch 里一个 case 都没有」——
/// 请求落到 `default` 返回 501，静态检查与单测都发现不了，只有真调接口才炸。
/// 定位 `handlers.dart`：`dart test` 的工作目录是仓库根，也可能在包内。
String _handlersSource() {
  final candidates = ['services/mangasvc/lib/src/server/handlers.dart', 'lib/src/server/handlers.dart'];
  for (final c in candidates) {
    final f = File(c);
    if (f.existsSync()) return f.readAsStringSync();
  }
  throw StateError('找不到 handlers.dart，检查测试工作目录');
}

void main() {
  test('路由表 ↔ handlers switch 全覆盖（无 501 端点）', () {
    final src = _handlersSource();
    // switch 里的 case 形如：case 'POST /api/v1/library/{name}/merge':
    final handled = RegExp(r"case '([A-Z]+ [^']+)':").allMatches(src).map((m) => m.group(1)!).toSet();

    final missing = [
      for (final r in routes)
        if (!handled.contains(r.id)) r.id,
    ];
    // 破坏点：新增路由却忘了写 case → 该端点恒 501，本条列出全部漏网项。
    expect(missing, isEmpty, reason: '以下路由没有 handler（会返回 501 NOT_IMPLEMENTED）：\n${missing.join('\n')}');
  });

  test('没有多余 case（handler 里写了路由表没有的端点）', () {
    final src = _handlersSource();
    final handled = RegExp(r"case '([A-Z]+ [^']+)':").allMatches(src).map((m) => m.group(1)!).toSet();
    final declared = routes.map((r) => r.id).toSet();
    final extra = [
      for (final h in handled)
        if (!declared.contains(h)) h,
    ];
    // 破坏点：改了路由字符串却没同步路由表 → 该 case 永远走不到。
    expect(extra, isEmpty, reason: 'handler 里有路由表未声明的端点：\n${extra.join('\n')}');
  });
}
