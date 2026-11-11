import 'package:flutter/material.dart';
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
import '../../features/music/domain/music_models.dart';
import '../../features/music/ui/mobile/mobile_music_screen.dart';
import '../../features/music/ui/music_screen.dart';
import '../../features/music/ui/views/music_detail.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../../core/theme/tokens.dart' show AppMetrics;
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
                    builder: (_, _) => const _MusicBranch(view: MusicScreenView.discover),
                  ),
                  // 「我的歌单」= 歌单库列表（N41/N44）；点条目才下钻 `playlist/:id`。
                  GoRoute(
                    path: 'playlist',
                    builder: (_, _) => const _MusicBranch(view: MusicScreenView.playlist),
                    // 歌单详情（歌单 / 专辑 / 推荐卡复用同一详情屏，N24）。
                    // 详情仍套模块容器：底部播放条（桌面）/ 迷你条（移动）不消失。
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (_, state) => _MusicBranch(
                          view: MusicScreenView.playlist,
                          body: MusicDetailScreen(kind: MusicSourceKind.playlist, id: state.pathParameters['id']!),
                        ),
                      ),
                    ],
                  ),
                  // 榜单详情（N38：点整张卡进详情页）。
                  GoRoute(
                    path: 'chart/:id',
                    builder: (_, state) => _MusicBranch(
                      view: MusicScreenView.playlist,
                      body: MusicDetailScreen(kind: MusicSourceKind.chart, id: state.pathParameters['id']!),
                    ),
                  ),
                  // 每日推荐详情（登录 CTA 卡 / 推荐栏首卡入口）。
                  GoRoute(
                    path: 'daily',
                    builder: (_, _) => const _MusicBranch(
                      view: MusicScreenView.discover,
                      body: MusicDetailScreen(kind: MusicSourceKind.daily, id: 'daily'),
                    ),
                  ),
                  GoRoute(
                    path: 'local',
                    builder: (_, _) => const _MusicBranch(view: MusicScreenView.local),
                  ),
                  GoRoute(
                    path: 'history',
                    builder: (_, _) => const _MusicBranch(view: MusicScreenView.history),
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

/// 音乐四视图的双端分支（桌面 = [MusicScreen] 模块容器；移动 = [MobileMusicScreen]）。
///
/// 断点与壳层同源（[AppMetrics.breakpoint]，AGENTS §4 第 16 条唯一判据）。
class _MusicBranch extends StatelessWidget {
  const _MusicBranch({required this.view, this.body});

  final MusicScreenView view;

  /// 子页（歌单 / 榜单 / 每日推荐详情）覆盖内容区，容器外壳保持不卸载。
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width <= AppMetrics.breakpoint) {
      return MobileMusicScreen(view: view, body: body);
    }
    return MusicScreen(view: view, body: body);
  }
}
