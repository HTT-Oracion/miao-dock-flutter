import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 屏级路由事实源（AGENTS.md §3）：新增屏在此登记。
/// 各业务域落地后改为 StatefulShellRoute，按 manga / music / anime / settings 分栈挂载。
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Center(child: Text('喵坞 MiaoDock'))),
      ),
    ],
  );
});
