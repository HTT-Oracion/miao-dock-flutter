import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/anime/ui/anime_screen.dart';
import '../../features/manga/ui/drop_screen.dart';
import '../../features/manga/ui/library_screen.dart';
import '../../features/manga/ui/queue_screen.dart';
import '../../features/music/ui/music_screen.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../shell/app_shell.dart';

/// 屏级路由事实源（AGENTS §3）：go_router + StatefulShellRoute。
/// 漫画视图（投放 / 队列 / 漫画库）是 /manga 的子路由，URL 即「屏 + 视图」的唯一事实源。
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/manga/drop',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/manga',
                redirect: (context, state) => state.matchedLocation == '/manga' ? '/manga/drop' : null,
                routes: [
                  GoRoute(path: 'drop', builder: (_, _) => const DropScreen()),
                  GoRoute(path: 'queue', builder: (_, _) => const QueueScreen()),
                  GoRoute(path: 'library', builder: (_, _) => const LibraryScreen()),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/music', builder: (_, _) => const MusicScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/anime', builder: (_, _) => const AnimeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())],
          ),
        ],
      ),
    ],
  );
});
