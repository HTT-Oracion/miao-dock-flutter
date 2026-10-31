# 决策台账

编号从 D-001 起全局递增、不得重复（见 `AGENTS.md` §1）。落案只写最关键的信息：做了什么 / 为什么 / 怎么验证，并标注状态。

## D-001 移动端不装配翻译引擎，服务由桌面端承担

- **状态**：已完成（2026-10-31）
- **做了什么**：翻译引擎（manga-image-translator + LLM）只在桌面端装配与运行；移动端 / Web 端一律访问桌面端 `mangasvc`（局域网 / 远程）。**放弃**「移动端运行量化版引擎与模型」的备选方案。
- **为什么**：引擎与模型体积、移动端算力、装配复杂度都不可行；统一走远程客户端后，移动端 / Web 与桌面 UI 复用同一份 `packages/protocol` 契约，暴露面收敛到一处（CORS + 鉴权）。
- **怎么验证**：`lib/app/bootstrap.dart` 只存在桌面端进程注入分支；移动端 / Web 客户端实现不包含引擎装配路径；服务端点设计不含「本机引擎」形态。
- **关联**：README §功能模块 · AGENTS §2 架构裁定 · 鉴权方案（待定项，服务设计期定）。

## D-002 Widget 嵌套治理判据

- **状态**：已完成（2026-10-31）
- **做了什么**：AGENTS §4 新增第 12 / 13 条——build 超 ~100 行或嵌套超 4 层必须拆独立 Widget 类（横向拆，返回 Widget 的私有方法不算完成）；状态经 `ref.watch` 在 build 顶层取，派生数据在 controller / selector 算好，`build` 只画。
- **为什么**：嵌套深是 Flutter 可读性头号问题；预防靠架构习惯（AsyncValue 三态、顶层取数、布局组件合并），检出靠明确阈值。机器 lint（custom_lint / DCM）对当前规模收益低，留作升级项。
- **怎么验证**：review 对照 §4 第 12 / 13 条；升级触发条件 = 团队扩大或 review 跟不上时上 custom_lint（候选见 third-party-packages.md）。
- **关联**：AGENTS §4 · third-party-packages.md。


## D-003 应用主体框架按 ver1.0 设计稿重构，脱离原项目 IA

- **状态**：已完成（2026-10-31）
- **做了什么**：
  - 壳层改以 `ver1.0/design.html` 为准：侧栏 208/68 宽度折叠 + 视图组 + MiniPlayer 槽位 + 设置脚；工具条 56；断点 768。
  - 令牌层重写为 `AppPalette`（ThemeExtension）深浅双档，覆盖 design.html §01 全量语义色；新增字号阶梯 / 几何 / 动效常量。
  - 侧栏图标换成 §05 指定值（`languages` / `music` / `clapperboard` / `folder-up` / `list-minus` / `book-text`），废弃值禁入。
  - 队列徽标口径改回原项目 `queueDepth = running + queued`（原实现误用 `tasks.length`）。
  - macOS 红绿灯与侧栏 logo 重叠：新增 `macTrafficLightBand` 让位带，侧栏与工具条整体下移。
- **为什么**：原实现沿用 miao-dock（React）的「视图做成工具条 Tab」IA，与设计稿「视图在侧栏」冲突；原项目侧栏仅 78 宽纯图标，与设计稿 208 展开态不同构。视觉与 IA 均以设计稿为准，业务口径以原项目代码为准。
- **怎么验证**：`test/app_shell_test.dart` 12 条 + `test/app_shell_interaction_test.dart` 3 条；两端 `flutter run` 日志 overflow/exception = 0；render tree 实测侧栏 `Size(208.0, 843.0)`、移动抽屉 210dp；截图取色命中 `--panel #141920` / `--bg #0C0F12` / `--card #1A2028`。
- **关联**：design.html §01–§06 · app_shell.dart · nav_rail.dart · tokens.dart。

## D-004 音乐域未落地：MiniPlayer 与音乐四视图只承载不造假

- **状态**：开发中（2026-10-31）
- **做了什么**：按产品确认「先画出来」——MiniPlayer 组件、音乐发现/歌单/本地/历史四条路由与侧栏视图组全部建成；数据侧 `nowPlayingProvider` 恒为 null，无播放状态时 MiniPlayer 整块不渲染；音乐屏给 `EmptyState` 空态而非假榜单/假曲目。
- **为什么**：设计稿有 MiniPlayer 与音乐视图，但音乐域（四平台音源 / just_audio）尚未接入。旧实现曾在侧栏硬编码 `夜に駆ける / YOASOBI / 60/190`，违反「禁止 Mock」红线。
- **怎么验证**：`app_shell_test.dart` 的「MiniPlayer 无播放状态时整块不渲染」断言；`nowPlayingProvider` 返回 null 时 `SidebarMiniPlayer` 走 `SizedBox.shrink()`。
- **关联**：sidebar_mini_player.dart · player_controller.dart · music_screen.dart。

## D-005 壳层偏好持久化不引入新依赖

- **状态**：已完成（2026-10-31）
- **做了什么**：`sidebar-labels` 与 `theme-mode` 两项壳层偏好用 `dart:io` 写单文件 JSON；键值沿用原项目窄枚举（`'1'` / `'0'`，缺键回落到默认显示）。路径均基于 `HOME`：macOS 走 `Library/Application Support/miao-dock-flutter/`，Linux 走 `.config/`，Windows 走 `LOCALAPPDATA`。
- **为什么**：`shared_preferences` 在 `third-party-packages.md` 中仍是候选（未写入 pubspec），按引入纪律不能直接用。偏好只有一个布尔，单文件足够。
- **踩坑**：macOS 启用了 App Sandbox（`macos/Runner/*.entitlements`），**沙箱内 `HOME` 已是容器目录** `~/Library/Containers/<bundle-id>/Data`，故基于 `HOME` 的路径在沙箱内外都合法，不需要单独分支 —— 不要改成硬编码 `~/.config`，那会在沙箱外解析到真实家目录、造成偏好分裂成两处。
- **怎么验证**：写入 `{"miao.sidebar-labels":"0"}` 后冷启动，widget dump 中品牌副标出现次数为 0、`_ModuleItem`/`_ViewItem` 仍为 6/6（只隐文字不关导航）；改回 `"1"` 后副标恢复。
- **关联**：shell_prefs.dart · third-party-packages.md §三。

## D-006 国际化方案：Flutter 官方 gen_l10n，当前只出中文

- **状态**：已完成（2026-10-31）
- **做了什么**：
  - 落地 Flutter 官方 `gen_l10n`：`l10n.yaml` + `lib/l10n/app_zh.arb` + `flutter_localizations`；生成物 `lib/l10n/app_localizations*.dart` 入 `.gitignore`。
  - **当前 `supportedLocales` 只含 `zh`，不做任何语言切换**，UI 上无语言选择器。新增语言是独立提案。
  - 壳层（侧栏 / 工具条 / 主题切换 / 移动端顶栏）已全部改用 ARB 词条，作为接入范式。
  - 新增中文硬编码**棘轮**：`tool/check_l10n.dart` + `tool/l10n_baseline.json`，接进 CI 与 `just check-l10n`。
  - 规范写入 `AGENTS.md` §3「国际化约束」，含 key 命名、占位符、错误码不进 ARB 等细则。
- **为什么选它**：Flutter SDK 官方方案，`flutter_localizations` 来自 SDK、`intl` 为传递依赖，**零第三方 pub 包**，符合依赖红线（`third-party-packages.md` §三）。`easy_localization` / `slang` 能做的 ARB 都能做，且要额外背维护风险。
- **为什么用棘轮而不是直接禁**：现存 20 个文件、115 处中文待迁移，一次性禁止会让检查永远红、进而被忽略。棘轮冻结基线、只准降不准升：新增文案必须走 ARB，存量按域逐步清零。
- **踩坑**：`AppLocalizations.of` 在 `nullable-getter: false` 下缺 delegate 会直接抛 null 崩溃 —— 任何 widget 测试的 `MaterialApp` 都必须显式挂 `localizationsDelegates` / `supportedLocales`，否则组件无关的改动也会连带炸测试。
- **怎么验证**：`test/l10n_test.dart` 3 条（supportedLocales 仅 zh / delegate 可解析 / 词条为中文，均做过反证）；`dart run tool/check_l10n.dart` 正向通过、故意多加一处中文时退出码 1 并打印文件名与数量；macOS 实机运行 l10n 文案正常渲染（widget dump 命中「喵坞」3 次、「投放」4 次），运行时零异常。
- **关联**：`l10n.yaml` · `lib/l10n/` · `tool/check_l10n.dart` · `AGENTS.md` §3 · `third-party-packages.md` §一。

## D-007 P0-A 契约与传输层落地（dio + 端口探测 + 令牌）

- **状态**：已完成（2026-10-31）
- **做了什么**：
  - `packages/protocol` 的 `MangaSvcClient` 按原项目 `mangasvc/routes.rs` 的 50 条路由**逐一重写**；新增 `TaskRow` / `TaskListResponse` / `LibraryResponse` / `EngineStatus` / `ModelDownloadView` / `ApiError` 等 DTO。命名统一为 `MangaSvc` 驼峰（原 `Mangasvc`）。
  - 旧 DTO `MangaTask` / `LibBook` 从 protocol 包**下沉到 `lib/features/manga/domain/`**（原先放错层：契约包不该承载 UI 模型），由 `data/contract_map.dart` 从 DTO 转换。
  - `lib/core/net/`：`MangaSvcHttpClient`（dio）+ `PortProbe`（5180–5190）+ `ServiceLocator`（桌面 Local / 移动 Remote）。
  - `bootstrap.dart` 按平台注入真实客户端；`--dart-define=MIAO_SVC_BASE_URL / MIAO_SVC_TOKEN` 可覆盖。
  - 引入 `dio ^5.7.0`（+ `dio_web_adapter` / `mime` 两个传递依赖，共 3 个包，运行时依赖）。
- **为什么**：P0-A 是打通真实链路的第一段；不做它，后面所有屏只能跑 A 级 Fake，无法验收。`dio` 早在 `third-party-packages.md` 登记为「manga/data 接真服务时」引入，本次正是该时机。
- **踩坑（已验证，写进代码注释）**：
  1. `flutter_test` 的 `TestWidgetsFlutterBinding` **拦截所有 HttpClient 并强制返回 400**，`HttpOverrides.global = null` 不解。传输层测试与 widget 测试必须**分文件**；同文件出现 `testWidgets` 会掐断整份 suite 的真实网络。
  2. dio 在部分 Content-Type 下返回 **String 而非 Map**：响应解析要两种都吃，否则正常响应被误判为协议错误。
  3. 契约状态词表是**下划线**（`partial_failed` / `canceled`）；`TaskStatus.parse` 对未知值**抛错不降级**（静默降级会把新状态误显示成旧状态）。
- **怎么验证**：
  - `test/p0a_contract_test.dart` 14 条（状态词表往返、未知态抛错、queueDepth 口径、逐页判定、错误码、探测区间、服务名匹配、令牌注入）。
  - `test/p0a_transport_test.dart` 2 条：**真实 socket** → 真实 HTTP → 契约解析；错误信封还原 `code/status/kind`。
  - `test/p0a_ui_integration_test.dart` 1 条：注入替身验证队列屏渲染。
  - 反证：把 `isTranslated` 改成 `seq <= donePages` → 「中间缺页不错位」失败；把服务名校验去掉 → 「非 mangasvc 服务不误判」失败。
  - 真实服务实测：模拟 mangasvc 记录到 `GET /health` ×2（探测）+ `GET /api/v1/tasks`（拉数据），全链路通。
- **关联**：`docs/internal/migration-priority.md` P0-A · `third-party-packages.md` §一（dio）。

## D-008 P0-B 服务端骨架与串行队列落地

- **状态**：开发中（P0-B1–B6 完成，B7–B10 待做）
- **做了什么**：
  - `services/mangasvc` 从 15 行骨架扩成可用服务：路由表（46 条）、HTTP 信封、分发层、串行队列、落盘扫描。
  - **零新增运行时依赖**：用 `dart:io` 裸写 HTTP，不引 `shelf`（`third-party-packages.md` 允许二选一，裸写让路由表完全可控）。仅新增 dev 依赖 `test`（官方包，非运行时）。
  - 端口段 5180–5190「先探测再绑定」+ 就绪行协议 `mangasvc listening on 127.0.0.1:<port>`。
  - 串行队列：并发上限 **1**（原项目 `drain.rs` 同语义），`mock` 引擎按页推进，`real` 引擎显式失败（不假装成功）。
- **为什么**：P0-A 只有契约没有服务端，所有 UI 仍跑 Fake。P0-B 让「点提交」有真实去处。
- **踩坑（实测暴露）**：
  1. `_hidden` 是 `Set<String>`，`jsonEncode` 直接抛 `Converting object to an encodable object failed` → 首次 `/library` 请求 500。改成 `.toList()`。
  2. `matchRoute` 对 `HttpRequest.uri.path`（已解码）又做一次 `Uri.decodeComponent` → 双重解码。
  3. `flutter_test` 的 binding 会拦 HTTP，服务端测试必须用 `dart test`（纯 Dart），不能塞进 `flutter test`。
- **怎么验证**：
  - `services/mangasvc/test/server_test.dart` 9 条（路由数 = 46、id 唯一、五分组齐全、通配捕获、段数不匹配不命中、方法不匹配不命中、未注册 404、不重复解码）。
  - `test/p0b_server_e2e_test.dart` 4 条（真实进程）：health / 建单→串行执行→done / **并发上限 1** / 书架扫描。
  - 反证：把路由匹配改成前缀匹配 → 3 条断言失败。
  - 手工实测：`curl` 建单 3 个 → 队列快照 `running: 1, queued: 2, concurrency: 1`（串行约束成立）；造真实目录 → 扫描出 `已译 [1]`、`缺页 []`。
- **关联**：`migration-priority.md` P0-B · `services/mangasvc/`。

## D-009 P0-B7/B8 与 P0-E1：计划端点与真实落盘闭环

- **状态**：已完成（2026-10-31）
- **做了什么**：
  - **契约纠错**：P0-A 把「续做计划」和「返工计划」合并成一个 `RetranslatePlan` 是错的。原项目是两种结构 —— resume 只列「有原图、缺译文」的页（`pendings`），retranslate 列「所有有原图」的页（`candidates` + `overwriteCount`）。已拆出独立 `ResumePlan` / `ResumePending`。
  - B7/B8：`/chapters/{no}/resume|retranslate`、`/renumber`、整本 `/resume|retranslate`（按话聚合）。
  - 话号规则对齐原项目：1–999、最多一位小数、目录名补两位（`01_第1话`）。非法话号**报错不降级**。
  - **P0-E1**：队列不再只推进进度，而是**真的落盘** —— 原图拷到 `<root>/<book>/01_第1话/NNN.ext`，译文写 `NNN_translated.ext`，并自动建 `manifest.json`。
- **为什么**：E1 是 P0 的出口条件；不落盘的话「投放成功」只是内存里的进度条，重启即失，无法验收。
- **踩坑（实测暴露，均写进注释）**：
  1. **不写 `manifest.json` → 书架读不回**：扫描把无 manifest 的目录归到 `others`（未归并单话），`books` 为空。反证已验证（去掉写 manifest 的代码 → E1 断言失败）。
  2. **`uri.path` 与 `pathSegments` 的编码差异**：中文书名用 curl 未编码发送时，`matchRoute(uri.path)` 拿到的是 `%E6%B5%8B...`，目录找不到。改用 `req.uri.pathSegments`（框架保证已解码），并保留 `matchRouteSegments` 供测试直接传段。
  3. `Handlers` 最初建了两个 `LibraryStore` 实例（一个给 store、一个取 rootDir 给 queue），惰性默认值下会产生两份真相。改 factory 保证同一个实例。
- **怎么验证**：
  - `services/mangasvc/test/plans_test.dart` 6 条（续做只列缺译页、全译后 pending=0、返工含已译页且标 hadTranslation、话号接受/拒绝、目录名补零）。
  - `test/p0e_full_loop_test.dart` 2 条（真实进程）：投放 3 张 → 落盘 → 书架读回 3 页全译 → 续做 pending=0。
  - 反证 2 轮：删 manifest 写入 → E1 失败；路由改前缀匹配 → 3 条失败。
  - 手工实测文件内容：`001.png` 与 `001_translated.png` 字节对应，序号连续无错位。
- **关联**：`migration-priority.md` P0-B7/B8 · P0-E1 · `plans.dart` · `library_store.dart`。

## D-011 P0-E4 远程模式：安全层与鉴权头修正

- **状态**：已完成（2026-10-31）
- **做了什么**：
  - 新增 `services/mangasvc/lib/src/server/security.dart`：Origin 白名单、CORS 预检与响应头、`X-Box-Token` 校验（定长比较）、`/health` 豁免。
  - 令牌来源：`MIAO_TOKEN` 环境变量 > `<root>/state/token` > 随机生成（64 hex）。
  - 服务端读 `X-Box-Client` 归因来源（`extension` / `desktop`）。
  - 扫描排除 `state/` 目录（服务自己的状态，不是漫画）。
- **为什么**：跨设备访问是**暴露面**（AGENTS §2 明文），不设防等于把本地服务开放给同网段任何人。
- **修正 P0-A 的契约错误**：鉴权头原写成 `Authorization: Bearer`，**实际是 `X-Box-Token`**。头名不对 → 403，且错误信息完全看不出原因（调试成本极高）。
- **踩坑**：
  1. **`skip:` 在测试注册期求值**，早于 `setUpAll` —— 想在 skip 里做异步服务探测是不可能的。改为在 test 体内 `await` 探测，`markTestSkipped` + `return`。
  2. `HttpResponse` 没有 `headersSent`；响应已写（SSE）后再写头会抛，只能 try/catch 兜住。
  3. `state/` 目录被扫描成漫画：存 token 的地方出现在书架里。
- **怎么验证**：
  - `services/mangasvc/test/security_test.dart` 8 条：无 Origin 放行、`null` 放行、extension id 字符校验、普通网页拒绝、CORS 回显规则、令牌前缀不匹配、health 豁免。
  - `test/p0e4_remote_test.dart` 4 条（真实服务）：远程地址+令牌可访问、无令牌 403、错误令牌 403、地址归一化。
  - 实测：`curl` 覆盖 8 种场景（见 migration-priority.md E4 记录表）。
  - 反证：令牌校验恒通过 → 2 条断言失败。
- **关联**：`migration-priority.md` P0-E4 · `security.dart` · `manga_svc_http.dart` 的 `kTokenHeader`。
