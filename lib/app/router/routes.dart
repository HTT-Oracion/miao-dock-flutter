import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/anime/ui/anime_screen.dart';
import '../../features/manga/controller/library_controller.dart';
import '../../features/manga/ui/drop_screen.dart';
import '../../features/manga/ui/library_screen.dart';
import '../../features/manga/ui/notready/not_ready_route_screen.dart';
import '../../features/manga/ui/queue_screen.dart';
import '../../features/manga/ui/reader_screen.dart';
import '../../features/manga/online/ui/online_screen.dart';
import '../../features/manga/online/ui/online_reader_screen.dart';
import '../../features/music/ui/music_playlist_screen.dart';
import '../../features/music/ui/music_screen.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../shell/app_shell.dart';
import '../shell/shell_controller.dart';

/// 「阅读器保活」的路由规则：会话还开着时，进漫画库 = 回到阅读器。
///
/// 阅读器是**叠在漫画库上的会话**，不是并列视图 —— 只有手动关掉（顶栏 × /
/// Esc / 系统返回）才清会话。清掉之后这里返回 `null`，漫画库才真正显示。
/// 页码由 [readerPageProvider] 保存，所以回到的是**原来那一页**，不是第 1 页。
///
/// 抽成纯函数：重定向规则可单测，不必起整套 widget 树。
String? readerResumeRedirect(ReaderSession? session) => session == null ? null : readerPath;

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
                  GoRoute(
                    path: 'library',
                    // 阅读器开着 ⇒ 进漫画库就回到阅读器（续读同一页），见 [readerResumeRedirect]。
                    redirect: (_, _) => readerResumeRedirect(ref.read(readerSessionProvider)),
                    builder: (_, _) => const LibraryScreen(),
                  ),
                  GoRoute(
                    path: 'online',
                    builder: (_, _) => const OnlineScreen(),
                    routes: [
                      // 详情复用在线屏：桌面主区切换、移动端右侧滑层。
                      GoRoute(path: 'detail/:sourceId/:comicId', builder: (_, _) => const OnlineScreen()),
                      GoRoute(path: 'reader', builder: (_, _) => const OnlineReaderScreen()),
                    ],
                  ),
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
