import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/theme.dart';
import 'router/routes.dart';

/// 应用根组件：主题挂载 + go_router。
class MiaoDockApp extends ConsumerWidget {
  const MiaoDockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(title: '喵坞 MiaoDock', theme: buildLightTheme(), routerConfig: ref.watch(routerProvider));
  }
}
