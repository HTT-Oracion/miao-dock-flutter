import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/anime/ui/anime_screen.dart';
import '../../features/manga/ui/drop_screen.dart';
import '../../features/manga/ui/library_screen.dart';
import '../../features/manga/ui/notready/not_ready_route_screen.dart';
import '../../features/manga/ui/queue_screen.dart';
import '../../features/manga/ui/reader_screen.dart';
import '../../features/music/ui/music_playlist_screen.dart';
import '../../features/music/ui/music_screen.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../shell/app_shell.dart';

/// 屏级路由事实源（AGENTS §3）：go_router + StatefulShellRoute。
///
/// URL 即「屏 + 应用内视图」的唯一事实源（对应原项目 `router/routes.ts`）：
///   · `/manga/{drop|queue|library}` —— 漫画翻译三视图；
///   · `/music/{discover|playlist|local|history}` —— 音乐四视图；
///   · `/anime`、`/settings` —— 单一屏。
///
/// 视图段名与 [mangaViews] / [musicViews] 的 id 必须同名，侧栏高亮据此判定。
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
                // 🔴 必须用 `uri.path`（完整请求路径）判断，不能用 `matchedLocation`：
                // 后者的语义是「命中的路由路径」，访问 `/manga/queue` 时它仍是 `/manga`，
                // 于是**任何子页面都会被重定向回 /manga/drop** —— 表现就是侧栏点了没反应。
                redirect: (context, state) => state.uri.path == '/manga' ? '/manga/drop' : null,
                routes: [
                  GoRoute(path: 'drop', builder: (_, _) => const DropScreen()),
                  GoRoute(path: 'queue', builder: (_, _) => const QueueScreen()),
                  GoRoute(path: 'library', builder: (_, _) => const LibraryScreen()),
                  GoRoute(path: 'reader', builder: (_, _) => const ReaderScreen()),
                  // 启动引导（D-012）：住在主体区，侧栏保留。归属「投放」高亮。
                  GoRoute(path: 'notready', builder: (_, _) => const NotReadyRouteScreen()),
                  GoRoute(path: 'degraded', builder: (_, _) => const NotReadyRouteScreen()),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/music',
                // 同上：用完整路径判断，避免子页面被重定向回首屏。
                redirect: (context, state) => state.uri.path == '/music' ? '/music/discover' : null,
                routes: [
                  GoRoute(
                    path: 'discover',
                    builder: (_, _) => const MusicScreen(view: MusicScreenView.discover),
                  ),
                  GoRoute(path: 'playlist', builder: (_, _) => const MusicPlaylistScreen()),
                  GoRoute(
                    path: 'local',
                    builder: (_, _) => const MusicScreen(view: MusicScreenView.local),
                  ),
                  GoRoute(
                    path: 'history',
                    builder: (_, _) => const MusicScreen(view: MusicScreenView.history),
                  ),
                ],
              ),
            ],
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
