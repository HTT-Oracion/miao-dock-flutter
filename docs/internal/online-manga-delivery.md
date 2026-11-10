# 在线漫画模块交付说明（2026-11-10）

> 范围：在「漫画翻译」模块新增第 4 视图【在线】，覆盖桌面端与移动端。
> 视觉依据：`design/online-manga/desktop.html`、`mobile.html` 与 `preview/*.png`；
> 功能依据：`design/manga-online-plan/manga-online-module-plan.md`（v2）。
> 代码入口：`lib/features/manga/online/`，路由 `/manga/online`。

## 一、交付内容

| 层 | 文件 | 说明 |
|---|---|---|
| 路由 / 壳 | `lib/app/router/routes.dart`、`lib/app/shell/shell_controller.dart`、`view_labels.dart` | 第 4 视图、详情 / 阅读器子路由、`isReaderPath` 并列判断 |
| 领域 | `online/domain/`（7 个文件） | 源清单、统一漫画模型、错误码、下载 / 翻译状态、源引擎接口 |
| 数据 | `online/data/`（6 个文件） | 源包导入 / 导出、持久化、演示引擎、翻译网关、仓库注入 |
| 控制器 | `online/controller/`（6 个文件） | 源 / 浏览 / 详情 / 阅读器 / 进度 / 下载 / 翻译 |
| UI | `online/ui/online_screen.dart`、`online_reader_screen.dart`、`ui/widgets/` | 桌面 / 移动两套布局、详情滑层、阅读器、源管理、状态件 |
| 设置 | `lib/features/settings/ui/settings_screen.dart` | 新增「漫画源」分区 |
| 国际化 | `lib/l10n/app_zh.arb` | 新增在线漫画词条，UI 零中文硬编码 |
| 主题 | `lib/core/theme/tokens.dart` | `onBtn` / `accInk` 对比度别名；字体族常量 |
| 断言 | `test/online/`（4 个测试文件 + fixture） | 路由 / 浏览 / 阅读器 / 下载 / 翻译 / 导入校验 |
| 台账 | `docs/internal/spec-notes.md` D-183..D-190 | 架构与取舍 |

## 二、功能覆盖对照表（plan → 实现）

| plan 功能点 | 实现位置 | 状态 |
|---|---|---|
| 在线作为漫画第 4 视图、深链 | `shell_controller.dart:mangaViews`、`routes.dart` `/manga/online`、`view_labels.dart` | 完成 |
| 多平台切换、竞态与熔断 | `online_sources_controller.dart`、`online_shelf.dart`、`online_chrome.dart`；失败计数见 `online_browse_controller.dart`；黄条见 `online_screen.dart` | 完成（失败 3 次红点 / 黄条） |
| 首页 explore / 分区 / 换一批 | `online_browse_controller.dart:OnlineFeedNotifier`、`online_browse_views.dart:OnlineDiscoverView` | 完成 |
| 分类 categories / category / 兜底 | `OnlineCategoriesNotifier`、`OnlineCategoryResultsNotifier`、`online_browse_views.dart:OnlineCategoryView` | 完成；分类失败用常用题材兜底 + 黄条 |
| 搜索（当前源）/ 防抖 / 空态 | `OnlineNavNotifier.setSearchInput/submitSearch`、`online_chrome.dart`、`OnlineSearchView` | 完成（300ms、60 字、Esc 清空） |
| 加载更多 / 触底 | `OnlineFeedNotifier.loadMore`、`OnlineAutoLoadMore`、`_LoadMoreRow` | 完成（桌面 200px / 移动 160px） |
| 详情 hero / 继续阅读 / 章节分组 / 已读对勾 | `online_detail_controller.dart`、`online_detail_view.dart:OnlineDesktopDetailView/OnlineMobileDetailSlide/_Chapters` | 完成；分组可折叠 |
| NOT_FOUND / 章节空态 | `OnlineStateBox` 分支、`_Chapters` | 完成（NOT_FOUND 走空态而非错误；章节空态独立） |
| 数据源导入四步 / 覆盖确认 | `source_import.dart:SourceImporter`、`online_source_panel.dart` | 完成静态四步；入口类 / 能力 / 路径 / hosts 校验；覆盖二次确认 |
| 源行开关 / 详情 / 覆盖 / 删除 / 复制 id / 导出 | `online_source_panel.dart:_SourceRow/_SourceDetail`、`OnlineSourcesNotifier` | 完成；删除清缓存 |
| 应用不内置源 / 免责声明 | `online_store.dart`（首次写空清单）、`onlineDisclaimerProvider` | 完成 |
| 在线阅读器内容区路由 / 移动全屏 | `routes.dart`、`online_reader_screen.dart`、`isReaderPath` | 完成 |
| 页图取列表 / headers / 预载 2 页 | `OnlineReaderNotifier.open/_prefetch`、`DemoSourceEngine.loadComicPages/getImageLoadingConfig` | 完成接口与预载；字节管道由演示页替代 |
| 阅读器翻页 / 滑条 / 热区 / 双击缩放 / 键盘 | `online_reader_screen.dart`、`online_reader_widgets.dart:OnlinePageSlider` | 完成；键盘 ←/→/T/C/G/F/?/Esc |
| 工具栏 / OSD / 自动隐藏 / 安全区 | `OnlineReaderTopBar/OnlineReaderFootBar/OnlineReaderMobileBottomBar`、`_SlideBar`、`_Osd` | 完成（移动 3s 自动隐藏） |
| 原文 / 译文切换、未完成页回退 | `OnlineReaderState.showingTranslated/pageHasTranslation`、`OnlineMangaPage` | 完成；300ms 交叉淡化；页角徽标 |
| 翻译 7 态 + 重试 / 仅看原文 / 去设置 | `OnlineTranslationBar`、`OnlineReaderNotifier.startTranslation/retryTranslation` | 完成（DemoTranslationGateway） |
| 章节目录 / 网格 / 帮助 / 亮度 / 夜间 / 条漫 / 全屏 | `_showChapters/_showGrid/_showHelp/_showBrightness`、`online_reader_widgets.dart` | 完成 |
| 翻译语言沿用设置 / 源语言只读 | `OnlineReaderSettingsContent`、`_showSettings` | 完成；语言显示日本語 / 简体中文 |
| 进度记忆（sourceId+comicId+chapterId+page） | `OnlineReaderNotifier._commitProgress`、`OnlineRecentNotifier`、`online_store.dart` | 完成；跨进程持久化 |
| 下载 / 下载并翻译 / 暂停 / 继续 / 取消 / 部分成功 | `online_download_controller.dart`、`OnlineDownloadPanel/OnlineDownloadRow` | 完成（模拟进度）；移动端「离线缓存」 |
| 离线缓存 sheet / 移动端源 sheet | `online_screen.dart:_showCacheSheet/_openSourceSheet`、`AppSheet` | 完成 |
| Web 灰置 | `online_screen.dart` kIsWeb 分支 | 完成入口页说明；未做壳层灰置 |
| 深 / 浅主题 | `AppPalette`、online 全部取 palette | 完成 |
| 移动端 390 适配 / 触控热区 | `context.isMobile` 单断点、移动布局、44px 动作 | 完成；底部导航沿用壳层 |

### 明确未接通的真实服务（重要）

- `SourceEngine` 只有 **DemoSourceEngine**：导入的 JS 不会被执行，浏览数据按 `DemoOnlineData`
  回放；接 `flutter_qjs` 后替换 `sourceEngineProvider` 即可，controller/UI 不变。
- 翻译只走 **DemoTranslationGateway**（260ms/页模拟），没有调用 `mangasvc.createTask`，
  译文也没有落盘；状态条 / 原文译文切换 / 渐进式页面都是真 UI 状态。
- 下载任务只模拟页进度并持久化任务状态，没有写入 `~/Pictures/MiaoDock Mangas`，也没有
  新增 `POST /library/.../images` 端点；「已入库」Toast 是状态机的完成反馈。
- 以上三点是本轮真实缺口，不是视觉近似；台账 D-184..D-188 已记录。

## 三、#spec-panel 交互说明 → 实现位置

### 桌面端（26 条）

| # | 说明条目 | 实现位置 |
|---|---|---|
| 1 | `module-entry` 一级导航 | `mangaViews` / `ShellViewTabs` / `OnlineScreen`（第 4 视图） |
| 2 | `platform-switcher` 平台切换 | `OnlineShelf._PlatformRow`、`onlineSourceSelectionProvider`、`activeOnlineSourceProvider` |
| 3 | `platform-region` 平台三态 | `OnlineShelf` 的 `sources.when`；`OnlineStateBox` / `SkeletonRows` 等价骨架 |
| 4 | `search-box` 全平台搜索 | `online_chrome.dart:_OnlineSearchField`、`OnlineSearchNotifier`（300ms / 60 字 / Esc） |
| 5 | `feed-region` 首页分区 | `OnlineFeedNotifier`、`OnlineDiscoverView`、`OnlineBookGrid` |
| 6 | `load-more` 分页 | `_LoadMoreRow`、`OnlineAutoLoadMore`、`OnlineFeedNotifier.loadMore` |
| 7 | `category-region` 分类 | `OnlineCategoriesNotifier`、`OnlineCategoryResultsNotifier`、`OnlineCategoryView` |
| 8 | `detail-region` 详情 | `onlineDetailProvider`、`OnlineDesktopDetailView`、`OnlineMobileDetailSlide` |
| 9 | `chapter-grid` 章节 | `_Chapters`（分组 / 折叠 / 已读对勾 / 44px 移动热区） |
| 10 | `download-region` 下载 | `online_download_controller.dart`、`OnlineDownloadsView` |
| 11 | `source-region` 源导入 | `SourceImporter`、`online_source_panel.dart`；入口只在设置 / 移动 sheet |
| 12 | `source-list` 源行操作 | `_SourceRow`、`_SourceDetail`、`_handleAction` |
| 13 | `reader-open` 进入 / 进度 | `_openReader`、`OnlineReaderLaunch`、`_commitProgress`、恢复 Toast |
| 14 | `page-frame` 页图 | `OnlineReaderNotifier.open/_loadPage/retryPage`、`OnlineMangaPage` |
| 15 | `reader-controls` 翻页 / 跳页 | `_onStageTap`、`OnlinePageSlider`、`_EdgeButton`、`_onScroll`、`_onKey` |
| 16 | `reader-bar` 工具带 | `OnlineReaderTopBar`、`OnlineReaderFootBar`、`_LanguageSeg` |
| 17 | `button-spacing` 按钮间隔 | 顶栏 `SizedBox(width:10)` / 移动 12；`_GroupSep` 1px；`kButtonRadius=6` |
| 18 | `translate-trigger` 翻译触发 | `OnlineReaderTopBar.onTranslate`、`OnlineTranslationBar.onTranslate` |
| 19 | `translate-region` 翻译 7 态 | `OnlineReaderNotifier.startTranslation`、`OnlineTranslationBar` |
| 20 | `lang-switch` 原文 / 译文 | `setShowOriginal`、`showingTranslated`、`OnlineMangaPage(translated:)` |
| 21 | `lang-select` 翻译语言 | `_showSettings`、`OnlineReaderSettingsContent`、跳 `设置?section=translate` |
| 22 | `translate-region` 不可用降级 | `OnlineTranslationBar` unavailable 分支、`_goSettings` |
| 23 | `state-injector` 评审工具 | 不是产品 UI；状态由 `AsyncValue` / 显示态驱动，测试用 store / engine / gateway 覆盖 |
| 24 | `theme-toggle` 深浅主题 | `AppPalette`、`themeModeProvider`；全部色取 palette（含新增 onBtn/accInk） |
| 25 | `disclaimer` 首次声明 | `onlineDisclaimerProvider`、`OnlineScreen._maybeShowDisclaimer` |
| 26 | `web-unsupported` Web 不支持 | `OnlineScreen` `kIsWeb` 分支 |

### 移动端（22 条）

| # | 说明条目 | 实现位置 |
|---|---|---|
| 1 | `m-entry` 底部 4 模块 | 沿用 `MobileBottomNav`；视图由 `MobileViewTabs` 第 4 项在线切换 |
| 2 | `m-platform` 横滑 chips | `OnlineMobilePlatformBar`、`_PlatformChip`、`_openSourceSheet` |
| 3 | `m-search` 搜索 / 键盘 | `OnlineMobileSearchBar`、`OnlineNavNotifier`（输入防抖 / Esc / 60 字） |
| 4 | `m-feed` 2 列网格 | `OnlineBookGrid`（窄屏 2 列）、`OnlineDiscoverView` |
| 5 | `m-loadmore` 触底 | `OnlineAutoLoadMore`（160px）、`_LoadMoreRow`（44px 按钮） |
| 6 | `m-tabs` 发现 / 分类 / 最近 | `OnlineMobileSubTabs`、`onlineNavProvider` |
| 7 | `m-detail` 右滑入 | `OnlineMobileDetailSlide`、`TweenAnimationBuilder` 380ms；路由 `/detail/...` |
| 8 | `m-chapters` 章节热区 / 折叠 | `_Chapters`（移动 44px、分组折叠、已读对勾） |
| 9 | `m-sheet-download` 缓存 sheet | `_showCacheSheet`、`_MobileCacheBody`、`AppSheet` |
| 10 | `m-sheet-source` 源导入 sheet | `_openSourceSheet`、`OnlineSourcePanel(sheetMode: true)` |
| 11 | `m-reader` 全屏 / 安全区 | `isReaderPath('/manga/online/reader')`、`OnlineReaderScreen` SafeArea |
| 12 | `m-ract-row` 滑条行 + 动作行 | `OnlineReaderMobileBottomBar`、`_ReaderAction`、`OnlinePageSlider` |
| 13 | `m-reader-bar` 热区 / 间隔 | 移动按钮 44 / 动作行 12 gap / 1.5px 进度线 / 3s 自动隐藏 |
| 14 | `m-page` 页图失败 | `OnlineReaderStageStatus`、`retryPage`、`skip`、403 演示页 |
| 15 | `m-progress` 进度恢复 | `ReadingProgress`、`onlineRecentProvider`、恢复 Toast |
| 16 | `m-translate` 翻译触发 / 状态机 | `OnlineTranslationBar` 移动布局（idle 按钮在状态条内）、7 态 |
| 17 | `m-langswitch` 原文 / 译文 | `_LanguageSeg`（44px）、`OnlineMangaPage` 交叉淡化 |
| 18 | `m-translate-fail` 失败 / 不可用 | `OnlineTranslationBar` 的 partial/failed/unavailable 分支与动作 |
| 19 | `m-injector` 评审工具 | 不还原 UI；状态用测试 store/engine/gateway 注入 |
| 20 | `theme-toggle` 深浅主题 | 同桌面，全部 palette 语义色 |
| 21 | `m-taps` 热区 / 误触 | 移动动作 ≥44、详情 2×2 44px、章节 44px、`_TapHintOverlay` 三分区 |
| 22 | `m-disclaimer` 底部声明 | `AppDialog` 在移动端自动走 `AppSheet`；`onlineDisclaimerProvider` |

## 四、#inject-region / #inject-states

`#inject-region` 模块切换器与 `#inject-states` 状态按钮本身是评审脚手架，**未还原 UI**；
其覆盖的模块与状态逐个实现如下：

| 区域 | 实现位置 | loading | empty | error |
|---|---|---|---|---|
| 平台列表 | `OnlineShelf` / `OnlineMobilePlatformBar` | 3 行骨架 / chip 骨架 | 「还没有漫画源」+ 导入 | `NETWORK` + 重试 |
| 首页 | `OnlineDiscoverView` | `OnlineGridSkeleton` | 源空文案 | `OnlineErrorBox` + 重试 |
| 分类结果 | `OnlineCategoryView` | 骨架 | 分类空态 | 错误 + 重试；分类失败兜底 |
| 搜索 | `OnlineSearchView` | 骨架 | 无结果文案 | 错误 + 重试 |
| 详情 | `OnlineDesktopDetailView` / `OnlineMobileDetailSlide` | 固定详情骨架 | NOT_FOUND 空态 | 错误 + 重试 |
| 章节 | `_Chapters` | 随详情骨架 | 暂无章节 | 随详情错误 |
| 阅读器页图 | `OnlineReaderScreen._stageBody` | 固定黑色舞台 + 1.6s spinner | — | 403 + 重试 / 跳过 |
| 下载 / 缓存 | `OnlineDownloadsView` / `_MobileCacheBody` | 行骨架 | 空态 | 错误 + 重试 |
| 源导入 | `OnlineSourcePanel` | 导入中 / 校验条 | 空态 + 导入 | 分级错误对话框 |
| 翻译 | `OnlineTranslationBar` | queued / running | — | partial / failed / unavailable |

## 五、截图自测结论

> 自测脚本与产物位于 `.tmp/online-impl/`（**交付前已删除**，见第六节）。
> 自测时将 `MemoryStore` 注入设计稿的 3 个源 / 进度 / 下载，正式构建首屏为空态。

- **端与尺寸**：桌面 1440×900（深浅）、移动 390×844（深浅）；覆盖无侧栏 / 详情滑层 /
  阅读器整屏 / 安全区 / 底部导航隐藏。
- **模块**：发现、分类、最近、下载、详情、章节、阅读器、源管理、移动端导入 sheet、
  移动端缓存 sheet、移动端翻译设置 sheet、网格 / 章节抽屉 / 帮助。
- **截图数量**：**50 张** 1440×900 / 390×844 实渲染（含状态注入与 14 个交互场景）。
- **状态**：平台 loading / empty / error；首页 loading / empty / error；分类 empty / error；
  详情 empty / error；章节 empty；下载 empty / error；页图 loading / 403 error；
  翻译 idle / queued / running / partial / failed / unavailable / done；源管理 error；
  首次声明（桌面 modal / 移动 sheet）；移动端缓存 / 源导入 / 翻译设置三个 sheet。
- **修复过的问题**：浅色主色按钮白字对比度不足 → 新增 `onBtn`/`accInk`；错误码等宽字体在
  测试字体下渲染为空 → 自测环境补 monospace 字体；`›` 字形缺失 → 补 Arial fallback；
  最近阅读移动端提示被截断 → 移动端隐藏长 hint；页 403 重试仍失败 → 去掉重试时的
  `_failedOnce.remove`；源失败自动重试导致骨架不消失 → 所有在线 async provider
  `retry: null`；移动端章节行 36→44；翻译计数 0/0 → 页列表加载后补 total；
  翻页 OSD 与 loading 重叠 → loading 期间不渲染 OSD；详情返回文案「返回列表」→「返回」；
  翻译设置分区标题重复 → 拆成「语言 / 范围」；移动 disclaimer 改为底部 sheet + 通栏 44 按钮；
  移动搜索按钮 / 缓存操作按钮补 ≥44 热区；源管理移动端说明按 plan 改为文件选择器文案。
- **覆盖不到的截图环境**：设计稿工具条 / 状态注入器 / 平台切换器示范 UI（按需求不还原）；
  真实 Web 构建（本机为 macOS test 渲染，kIsWeb 分支只做了代码路径保护）。

## 六、自测脚本 / 临时产物清理

交付前删除：

- `test/online_shot_scene_test.dart`（单场景截图 harness，已删）
- `test/online_shot_tmp_test.dart` / `online_shot_flow_test.dart` / `online_smoke_tmp_test.dart`（已删）
- `.tmp/online-impl/`（50 张截图、probe / 批量截图脚本、日志，已删）

保留的 `test/online/` 是**正式产品断言**，不依赖截图脚本；`flutter test` 可独立运行。
`design/online-manga/` 下的设计稿与 `preview/` 是用户输入资料，保持原样未删。

## 七、验证命令与结果

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter test test/online
```

- `dart format --set-exit-if-changed lib test`：**0 changed**。
- `flutter analyze`：**0 issues**。
- `flutter test test/online`：**16 passed**（4 个测试文件）。
- `flutter test`：**319 passed / 11 skipped**（原 303，新增 16）。
- `flutter build macos --debug`：**✓ Built** `build/macos/Build/Products/Debug/miao_dock_flutter.app`。
- 真机：仅以 Flutter test 的 1440×900 / 390×844 逻辑尺寸与 macOS 字体渲染验证；未在真机
  iOS / Android 上跑安装包，未验证系统返回手势与原生文件选择器的实际行为。

## 八、已知偏差与合理差异

1. **左栏宽度**：设计稿 168（含品牌 + 导航）；正式壳层沿用项目 `NavRail` 208 / 68 折叠，
   在线内栏 246 不变。桌面截图的横向起点因此整体右移 40px。
2. **macOS 红绿灯让位**：真实窗口在 AppTitleBar 上方多 28px 让位；test 截图的 AppTitleBar
   没有系统标题栏，顶部结构有 28px 差异。
3. **字体**：设计稿 Noto Sans SC / PingFang；实现用系统字体回落。测试截图加载
   Hiragino Sans GB + Arial + Menlo，个别字形（`›`）与真机不同。
4. **图标**：Lucide 线性图标；个别图标名与设计稿贴图不是同一枚（如全屏 / 条漫），
   线宽与尺寸按 1.8 / 16 口径。
5. **按钮圆角**：统一 `kButtonRadius=6`；设计 `.ibtn` 的 8px 圆角未破例。
6. **AppTitleBar 状态 chip**：沿用项目「引擎未就绪 / 本地翻译」，设计稿写「引擎就绪 / 本地」；
   在线模块本身不要求本地引擎。
7. **源 / 翻译 / 下载服务**：见第二节「明确未接通的真实服务」；属于真实缺口。
8. **Web 灰置**：在线视图内显示「Web 端不支持」；壳层页签未做成灰置不可点（项目
   `ShellViewTabs` 当前没有 disabled 变体）。
9. **自动隐藏 / 首次提示**：移动阅读器按 3s 自动隐藏、1.6s 三分区提示；截图在隐藏前捕获。
