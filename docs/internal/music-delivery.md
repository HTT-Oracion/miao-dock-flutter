# 音乐模块交付说明（design/music/ver1.0 对齐）

> 范围：`design/music/ver1.0`（desktop.html / mobile.html + `#spec` 面板）要求的音乐模块全部交互。
> 代码：`lib/features/music/`、`lib/app/shell/`（侧栏视图组 / 音源组 / 移动顶栏）、`lib/app/router/routes.dart`。
> 决策记录：`docs/internal/spec-notes.md` D-201（首版落地）、D-202（本轮 N41–N44 / M18 与偏差修复）。

## 1. 功能覆盖对照表（`#spec` 互动说明逐条 → 实现位置）

| ID | 交互点 | 实现位置 |
|---|---|---|
| N01 | 侧栏收起 / 展开 212 ⇄ 68、图标换形、窄窗覆盖抽屉 | `shared/widgets/nav_rail.dart`（`NavRail`、`collapse`）+ `app/shell/app_shell.dart`（`_DesktopShell`） |
| N02 | 模块切换（漫画翻译 / 音乐 / 番剧）、内容淡入上移 | `app/shell/module_nav.dart`（`switchModule`）、`app_shell.dart` `_PageTransition` |
| N03 | 四视图切换、记住滚动位置、重复点击回顶 | `app/shell/sidebar_music_views.dart`、`app/shell/view_tabs.dart`、`ui/widgets/music_scroll_memory.dart` + `music_session.dart` `musicScrollMemoryProvider` |
| N04 | 音源切换与登录（三态徽标、切源不清队列） | `ui/sidebar_source_group.dart`、`ui/mobile/music_sheets.dart` `_AccountBody`、`controller/music_session.dart` `MusicAccountNotifier` |
| N05 | 账号菜单（头像 / 昵称 / 四平台 / 退出） | `ui/desktop/account_menu.dart` `AccountMenuPopover` |
| N06 | 搜索浮层（⌘K、输入即分组、未登录说明态、Esc 关闭清空） | `ui/desktop/search_overlay.dart` `SearchOverlay` / `_SearchInput` / `_SearchBody`；快捷键在 `ui/music_screen.dart` `_handleKey` |
| N07 | 主题三态循环（跟随系统 / 浅 / 深） | `app/shell/theme_toggle_button.dart`、`core/theme/theme_mode.dart` |
| N08 | 播放 / 暂停（图标即时切换、缩放反馈） | `ui/mobile/mini_bar.dart` `TapScaleButton`、`ui/desktop/play_bar.dart`、`controller/music_player.dart` `toggle()` |
| N09 | 上一曲 / 下一曲 / 进度拖拽、悬停时间气泡、←→ 5s | `ui/desktop/play_bar.dart` `MusicSeek` / `MusicTimeText`、`music_player.dart` `seekMs/nextTrack/prevTrack`、`music_screen.dart` `_handleKey` |
| N10 | 播放模式点击循环 + 心动模式门槛 | `music_player.dart` `cycleMode()`（不合法档位整档跳过、离开心动队列自动退回并提示）、`ui/widgets/music_shared.dart` `playModeIcon/Label/Desc` |
| N11 | 音质 5 档弹层（码率 / 会员标注） | `ui/mobile/music_sheets.dart` `_QualityBody`、`ui/desktop/play_bar.dart` `_QualityChip`、`domain/music_models.dart` `QualityTier` |
| N12 | 音量滑杆 / 静音 / ↑↓ 5% | `ui/desktop/play_bar.dart` `_VolumeRegion`、`ui/desktop/immersive_player.dart` `_ImmersiveVolume`、`music_player.dart` `setVolume/toggleMute` |
| N13 | 灵动岛折叠 230×34 ⇄ 展开 348×186、≤1120 隐藏 | `ui/desktop/island.dart` `DynamicIsland`、`app_shell.dart`（按 `AppMetrics.musicIslandBreakpoint` 挂载） |
| N14 | 播放队列抽屉（当前行橙底 ♪、悬停移除 / 拖拽、移除当前曲落到下一首、只剩一首禁止移除） | `ui/desktop/queue_drawer.dart` `QueueDrawer`（`ReorderableListView` + `removeAt`）、`music_player.dart` `removeAt` / 单曲保护 |
| N15 | 清空队列只留当前曲 + 6 秒撤销 | `queue_drawer.dart` `_clear/_undo`、`music_player.dart` `clearQueueKeepCurrent/restoreQueue` |
| N16 | 沉浸播放器开 / 收 / 全屏、Esc 逐层关闭 | `ui/desktop/immersive_player.dart` `ImmersivePlayer`、`app_shell.dart` 挂载、`music_screen.dart` `_handleKey`（Esc 顺序） |
| N17 | 播放器样式 6 种（缩略色块 + 勾选，仅现代有「动态」） | `immersive_player.dart` `_SkinPopoverState/_SkinSwatch/_Atmosphere`、`music_session.dart` `playerStyleProvider` |
| N18 | 歌词跟随 / 手动 3 秒恢复 / 点击行跳转 / 译开关 | `immersive_player.dart` `_LyricsView`、`music_session.dart` `translateOn` |
| N19 | 桌面歌词浮层 + 设置（字号 / 高亮 / 未唱色 / 行数，即时预览，≤1100 隐藏） | `ui/desktop/desktop_lyrics.dart` `DesktopLyricsOverlay` / `DesktopLyricsSettingsModal` / `desktopLyricsPrefsProvider` |
| N20 | 评论列表（热门角标、点赞即时 +1） | `immersive_player.dart` `_CommentsView`、`data/demo_music_repository.dart` `comments()`、`data/platform_music_repository.dart` |
| N21 | 发现页推荐栏（9 横卡、点卡整组播放、桌面 hover 箭头） | `ui/views/discover_view.dart` `_RecSection/_RecBar/_RecCard` |
| N22 | 榜单 / 歌单「换一批」（轻提示 700ms、不清旧内容、失败横幅） | `discover_view.dart` `_refreshToast`、`shared/widgets/error_state.dart` `ErrorBanner` |
| N23 | 歌曲行播放 / 右键两项 / ⋯ 完整菜单 / 序号占位 / 当前行橙色 | `ui/widgets/song_row.dart` `SongRow`、`_showContextMenu`、`_showFullMenu` |
| N24 | 歌单详情两个动作（播放全部 / 收藏），心动队列来源约束 | `ui/views/music_detail.dart` `MusicDetailScreen` / `_Hero`、`music_player.dart` `playAll(fromLiked:)` |
| N25 | 本地导入（选择文件 / 文件夹 / 拖放 / 导入中禁用 / 清空 + 撤销） | `ui/views/local_view.dart` `LocalView` `_import/_clear/_restore`、`_DropZone`、`music_local` controller |
| N26 | 播放历史（今 / 昨 / 更早、清空撤销、点行重播、平台色点） | `ui/views/history_view.dart` `HistoryView` `_groupEntries/_replay/_clear` |
| N27 | 加载骨架按真实布局占位（无 CLS） | 各视图 `*Skeleton`（`discover_view.dart` `_RecBarSkeleton`、`playlist_view.dart` `PlaylistLibrarySkeleton`、`music_detail.dart` `_DetailSkeleton`）、`shared/widgets/skeleton.dart` |
| N28 | 整页失败（魔法阵 + 原因 / 上次同步 / 可播数 + 重试 / 切本地 / 服务状态） | `ui/widgets/fail_magic.dart` `FailMagicCircle`、各视图 `_FailPage`（如 `discover_view.dart`、`playlist_view.dart`） |
| N29 | 局部失败横幅（保留旧数据 + 重试） | `shared/widgets/error_state.dart` `ErrorBanner(compact: true)`、`discover_view.dart` / `playlist_view.dart` |
| N30 | 空态（与失败分开、不动画、文案分「无匹配 / 还没有内容」） | `ui/widgets/music_empty_state.dart` `MusicEmptyState` / `MusicEmptyArt`、`local_view.dart`、`history_view.dart`、`search_overlay.dart` |
| N31 | 深浅主题（只换变量、主色浅色加深） | `core/theme/tokens.dart` `AppPalette.dark/light`、`core/theme/theme_mode.dart` |
| N32 | 响应式三档 lg / md / sm（列数、灵动岛、专辑列、播放条按键） | `core/theme/tokens.dart` `AppMetrics.musicIslandBreakpoint/musicNarrowBreakpoint`、`discover_view.dart` `_colsOf`、`playlist_view.dart` `_PlaylistGroupBody`、`play_bar.dart` 断点取舍 |
| N33 | 键盘与焦点（空格 / ←→ / ↑↓ / M / Q / F / ⌘K / Esc；输入框让位） | `ui/music_screen.dart` `_handleKey` / `_isEditing`、`immersive_player.dart` `_handleKey` |
| N34 | 降低动效（旋转 / 位移归零，保留透明与颜色） | `shared/responsive.dart` `reduceMotion`、`island.dart`、`immersive_player.dart`、`full_player.dart`、`fail_magic.dart` |
| M01 | 底部一级导航（四项、橙色 + 顶部指示条、安全区） | `app/shell/mobile_nav.dart` `MobileBottomNav` |
| M02 | 顶部二级页签（发现 / 歌单 / 本地 / 历史，主题按钮在最右） | `app/shell/view_tabs.dart` `MobileViewTabs`、`app_shell.dart` `_MobileShell` |
| M03 | 迷你条两键 + 横滑切歌 + 上滑展开 | `ui/mobile/mini_bar.dart` `MiniMusicBar` / `_MiniSwipeArea` / `_IncomingSlide`、`full_player.dart` |
| M04 | 全屏播放器顶栏（当前歌单 / 歌名·歌手 / 更多）、下滑 >110 收起、返回键收起 | `ui/mobile/full_player.dart` `_topBar`（`PopScope` + 下滑手势）、`music_sheets.dart` `_MoreBody` |
| M05 | 歌词跟随 / 手动定位卡（时间戳 + 纯 icon ▶）/ 3 秒恢复 / 轻点返回光碟 | `full_player.dart` `_LyricsView`、`_markManual/_armRestore/_updateSeekLine` |
| M06 | 光碟视图（黑胶 / 唱针 -14° / 整块可点切歌词 / 暂停停转） | `full_player.dart` `_DiscView/_VinylPainter/_TonearmPainter`、`_spin` |
| M07 | 底部抽屉（队列 / 音质 / 样式 / 更多 / 账号；≤82% 高、拖把手 / 遮罩关闭、选项点即生效） | `ui/mobile/music_sheets.dart` `MusicSheetsHost/_SheetLayer` |
| M08 | 触控热区（图标 ≥40、行 ≥48、播放键 56、按下 scale .94） | `mini_bar.dart` `TapScaleButton`、`song_row.dart`（行高 48）、`full_player.dart` `_ctrlRow` |
| M09 | 安全区与滚动冲突（底部安全区留白、抽屉 overscroll contain） | `mobile_music_screen.dart`、`music_sheets.dart` `_SheetLayer`、`full_player.dart` 底部 `MediaQuery.paddingOf` |
| N35 | 侧栏迷你播放器（整卡可点、播放键不冒泡、28 橙圆） | `ui/sidebar_mini_player.dart` `SidebarMiniPlayer` / `_PlayButton` |
| N36 | 右键两项菜单（跟随鼠标、夹在窗口内、历史行不弹） | `song_row.dart` `showAnchoredMusicPanel` / `_showContextMenu` |
| N37 | 推荐栏 9 卡 / scroll-snap / 顺序 推荐栏→歌单→榜单→推荐歌曲 / 移动首卡 16px | `discover_view.dart` `DiscoverView`（固定顺序）、`_RecBar`、`_colsOf` |
| M10 | 移动顶栏去掉「音乐」、改当前音源品牌 logo、账号抽屉 | `app_shell.dart` `_MusicMobileHeader`、`ui/widgets/platform_logo.dart`、`music_sheets.dart` `_AccountBody` |
| M11 | 长按 480ms 出菜单 + 轻震 + 纵向 12px 取消 + 点 ⋯ 不计时 | `song_row.dart` `onLongPressStart`（`HapticFeedback.lightImpact`） |
| M12 | 队列抽屉清空 / 关闭收进标题栏 icon（≥32 热区、间距 10） | `music_sheets.dart` `_QueueHeader/_SheetIconButton` |
| N38 | 官方榜单横向卡（榜单名 + 更新时间 / 叠层封面 + Top3 + 趋势标记） | `discover_view.dart` `_ChartGrid/_ChartCard` |
| M13 | 底部三行（信息或译 + 爱心 + 评论 / 进度 + 时间 + 音质 + 时长 / 五键） | `full_player.dart` `_infoRow/_progressRow/_ctrlRow` |
| M14 | 评论视图与更多抽屉（记住 prevTab、样式入口、铃声 / 睡眠 / 信息） | `full_player.dart` `_toggleComments/_prevTab/_CommentsView`、`music_sheets.dart` `_MoreBody` |
| M15 | 移动歌曲行浮层菜单（跟随触发点、封面头部、红心即时、点外关闭） | `song_row.dart` `_showFullMenu`、`MusicMenuHeader(coverSeed:)` |
| M16 | mini 横滑滑块推入（封面 + 歌名 + 歌手 + 方向标签、≥56px 先滑到位再切歌） | `mini_bar.dart` `_MiniSwipeArea/_CurrentSlide/_IncomingSlide`（阈值 56、方向锁 9px） |
| N39 | 轻提示沿用原项目（本设计不新增吐司） | `shared/widgets/toast.dart` `showAppToast`（仅业务既有动作调用；横滑切歌 / 歌词定位 / 模式循环 / 状态演示均无提示） |
| M17 | 推荐栏首卡 16px 与滚动溢出边界 | `discover_view.dart` `_RecBar`（移动端内容边距由容器给 16） |
| N40 | 平台品牌 logo（侧栏 / 账号菜单 / 移动顶栏 / 抽屉） | `ui/widgets/platform_logo.dart` `PlatformLogo`、`domain/music_models.dart` `platformBrands` |
| N41 | 我的歌单库（系统歌单置顶 + 创建 / 收藏两组、折叠、四态、下钻返回） | `ui/views/playlist_view.dart` `PlaylistLibraryView/_LibraryBody/_GroupCaption/_LikedCard`、`controller/music_playlist_library.dart` `playlistLibraryProvider/userPlaylistsProvider/groupPlaylists` |
| N42 | 创建的歌单紧凑信息卡（60 封面 / 两行标题 / 作者·N 首 / 4 列、sm 2 列 / 骨架 8 + 4） | `playlist_view.dart` `_PlaylistGroupBody/_CompactGrid/_PlaylistCard/_PlaylistCardState`、`PlaylistLibrarySkeleton/_CardSkeletonGrid` |
| M18 | 歌单库是一级页，返回只出现在详情 | `app_shell.dart` `_isMusicDetailPath` + `_MusicMobileHeader(showBack:)`、`music_detail.dart` `_DetailBackBar` |
| N43 | 收藏的歌单分组 + 取消收藏闭环 | `music_playlist_library.dart` `toggleSubscribe/PlaylistLibraryState.isSaved`、`music_detail.dart` `MusicDetailScreen` 收藏按钮分支、`playlist_view.dart` `_PlaylistCover` 心形角标 |
| N44 | 歌单库去掉页内大标题与总数 | `playlist_view.dart`（直接从横卡开始，无 `pl-lib-h`；骨架无标题条） |

### 数据 / 接口（用户指定口径）

| 平台 | 接口（移植自 miao-dock 的 Rust 客户端，转成 Dart） | 位置 |
|---|---|---|
| 网易云 | `/api/user/playlist`（`specialType == 5` 识别「我喜欢的音乐」，`subscribed` 语义位） | `data/api/netease_api.dart` `userPlaylists()` |
| QQ 音乐 | `fcg_user_created_diss` + `fcg_get_profile_order_asset`（reqtype=3） | `data/api/qqmusic_api.dart` `userPlaylists()/_createdPlaylists/_collectedPlaylists` |
| 酷狗 | H5 网关 `/v7/get_all_list`（`md5(salt + sorted kv + body + salt)` 签名） | `data/api/kugou_api.dart` `userPlaylists()/_parseH5Auth` |
| 咪咕 | `pc/user/home-page/v2.0`（官方 / 自建 / 收藏三块） | `data/api/migu_api.dart` `userPlaylists()` |
| 仓库层 | `MusicRepository.userPlaylists()` → `PlatformMusicRepository` / `DemoMusicRepository` | `data/music_repository.dart`、`data/platform_music_repository.dart`、`data/demo_music_repository.dart` |

## 2. 截图自测结论

- **覆盖范围**：桌面 1440×900 + 移动 390×844；深色 / 浅色两套。
  桌面：发现（成功 / 局部失败 / 整页失败 / 加载骨架）、我的歌单库、收藏歌单详情、歌单详情（深浅）、
  队列抽屉、灵动岛、沉浸播放器（歌词 / 评论、深浅）、未登录搜索、登录弹窗、本地空态、播放历史。
  移动：发现、迷你条、全屏播放器（光碟 / 歌词 / 评论、深浅）、队列抽屉、账号与音源抽屉、
  我的歌单库（深浅）、收藏歌单详情、歌单详情、本地空态、播放历史、搜索浮层。
- **比对方式**：Playwright 打开 `design/music/ver1.0/desktop.html` / `mobile.html` 截同状态设计稿，
  与 Flutter 集成测试截图逐张对照（布局顺序、间距、字号、圆角、颜色、图标、动效落点）。
- **已修复的问题**（本轮自测发现）：
  1. 移动端全屏播放器缺封面色氛围层 → 补 `_PlayerWash`；
  2. 浅色主题唱针白色融底 → 唱针改 `ink` + 浅色描边；
  3. 歌词区在桌面窗口里画出滚动条（设计稿无）→ `ScrollConfiguration(scrollbars: false)`；
  4. 评论头写「评论」/「热门评论」→ 改「评论 · N」/「热门」；
  5. 移动账号抽屉监听了桌面的 `accountMenuOpen`，点顶栏 logo 无反应 → 改 `accountSheetOpen`；
  6. 移动搜索是居中弹层 → 改整屏浮层（设计稿 `.m-search`），并隐藏底部导航；
  7. 搜索最近词 chip 被 `Container(alignment:)` 撑成整行 → `Center(widthFactor: 1)`；
  8. 移动本地空态是虚线拖放区 → 改「单环 + 音符轨道」空态图 + 整宽按钮；桌面补 1.5px 虚线；
  9. 播放历史空态只有标题栏 → 补插画 + 「去发现页听听」动作；
  10. 歌单库卡片副行/详情副行与设计稿口径不一致（作者·N 首 / 移动只「曲数·描述」）→ 已对齐；
  11. 详情缺返回栏 / 类型胶囊 / COLLECTED 眉标 / 收藏歌单来源行 → 已补齐；
  12. 歌单曲目按数组下标偏移（设计稿是 `pick`）→ 改 `_playlistPick`；
  13. `SkeletonRows` 尾部定宽条在 390 宽溢出 30px → 改 `Flexible`；
  14. 移动抽屉用屏幕高度算 82% 上限，底部被裁 → 改按宿主约束；
  15. 下钻详情时播放条 / 迷你条消失 → 详情路由复用 `MusicScreen(body:)` / `MobileMusicScreen(body:)`。
- **仍存在的已知偏差**：见 §4。

## 3. 自测脚本清理清单（最终提交不含）

已删除，且正式代码不引用：

| 路径 | 内容 |
|---|---|
| `integration_test/music_selftest_test.dart` | 截图自测 harness（34 张图）+ 运行时临时加的 `integration_test` dev 依赖（`pubspec.yaml` / `pubspec.lock` 已还原） |
| `.tmp/music-selftest/` | 34 张 Flutter 自测截图（桌面 / 移动 × 深浅 × 各状态） |
| `.tmp/music-selftest-logs/` | 13 次自测运行日志 |
| `.tmp/music-design/` | Playwright 抓的设计稿对照截图 |
| `.tmp/design-run/shot-music-new.mjs`、`shot-music-fp.mjs`、`shot-music-states.mjs`、`shot-search.mjs`、`music-shots.mjs`、`music-shots2.mjs` | 设计稿截图脚本 |

删除后校验：`flutter analyze` 0；`flutter test` 全绿；`flutter build macos --debug` 与
`flutter build apk --debug` 均通过（自测脚本不参与构建）。

## 4. 还原差异说明（与设计稿的已知偏差及原因）

1. **播放是模拟时钟**（`Timer.periodic(500ms)` 推进进度），未接 `just_audio` 真实音频流：
   AGENTS §2 把「music 走 just_audio」列为待 spike 的架构项，引入音频依赖需先过台账（D-201 已记录）。
   因此进度条拖拽、切曲、暂停全部是状态机行为，听感需等音频接入后验证。
2. **网易云二维码只给登录 URL + 状态，不绘制二维码图形**：Flutter 无内置 QR 编码器，
   新增 `qr_flutter` 属新依赖（未确认不引入）。二维码区域按设计稿画了框与角标，内容为说明文案。
3. **队列拖拽落点**用 M3 `ReorderableListView` 的默认位移反馈，未自绘 2px 插入指示线
   （设计稿 N14 要求 2px 线；自绘需接管整个拖拽会话，收益与风险不匹配，已记 D-201）。
4. **字体**：设计稿用系统 `-apple-system / PingFang SC`，Flutter 走 `AppFonts.family` + 回退链；
   同字号下中文行高有 1–2px 差异，属渲染栈差异。
5. **封面渐变**：设计稿是 CSS 四层渐变（含 conic），Flutter 用三层等价（conic 用径向光斑替代，
   避免 `SweepGradient` 起始接缝），色相与设计稿 FNV-1a 哈希一致。
6. **灵动岛 / 抽屉动效**用 Flutter `AnimationController` 复刻设计稿 320ms / 380ms 与
   `cubic-bezier(.22,.61,.36,1)`，帧率与浏览器合成层不同，观感有细微差别。
7. **窄窗侧栏转抽屉的断点是 768，不是设计稿写的 900**：AGENTS §4.16 把
   `AppMetrics.breakpoint = 768` 定为全项目唯一断点、禁止页面另写一套；设计稿 N32 的
   sm<900 属于音乐模块自己的三档，若在壳层再切一次会出现「外壳还是侧栏、内容已按手机排」。
   因此 900–768 之间保留侧栏（内容列数 / 专辑列 / 音量已按 sm 收起），抽屉在 ≤768 出现。
8. **平台接口**是第三方站点，未在 CI 做在线断言（离线用例覆盖签名 / 解码 / 映射）；
   真实网络探针仅在开发期手动跑过，线上风控变化可能导致某些分区降级为空。
