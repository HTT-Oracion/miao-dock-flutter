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

## D-012 服务分层与翻译来源三选一（待实现，P0 范围内）

- **状态**：开发中（2026-10-31 定案，实现待做）
- **做了什么（架构定案）**：
  - **服务拆三层**：L0 `mangasvc` HTTP 服务（**随应用常驻**）/ L1 翻译引擎 / L2 LLM。L1 与 L2 **共用一个开关**（一次点击拉起两个进程）。
  - **引擎 + LLM 未启动 = 未就绪**，需要引导页（按新分层重做，不再用原项目五阶段）。
  - 自动唤起配置落在「设置 → 翻译服务」（`随应用启动服务` / `翻译时自动启动引擎` / `空闲后自动卸载`）。
  - **翻译来源 2 → 3**：`本地翻译`（引擎+LLM 均在本机）/ `大模型翻译`（引擎在本机，LLM 换云端 API）/ `远程翻译`（本机不下载任何引擎与 LLM，整条链路交给其他端）。
  - **移动端只有 `远程翻译`**（不跑本地服务，与 D-001 一致）。
- **为什么**：原项目把引擎与服务绑死，服务挂了整片不可用。分层后服务常驻，浏览库 / 看已译 / 投放（进队列）在引擎未启动时仍可用，只有「实际翻译」需要 L1+L2。
- **UI 影响（已与产品确认）**：
  - 移除「稍后再说」按钮（原设计稿跳队列会造成死循环）。
  - **移除「服务已启动」独立徽标**：服务常驻后它是废话，且会误导（服务绿 ≠ 能翻译）。
  - 侧栏状态点语义改为**「能否翻译」**四色：绿=就绪 / 黄=服务在但引擎未起 / 红=服务异常 / 灰=未配置。
  - 工具条徽标改为显示**当前翻译来源** + **引擎就绪度**（「引擎未启动」可点击直接拉起）。
  - 设置页「翻译服务」用一张三行卡片呈现三层状态。
- **怎么验证**：设计稿 `ver1.0/index.html` 的 `guide` / `download` 合并为「启动引导」状态页；实现后按 `test/l10n_test.dart` + 新增状态派生断言。
- **关联**：AGENTS §2 服务裁定 · D-001 · `migration-priority.md` P0。

## D-013 日志组件规范（hover 浮出复制 / 导出）

- **状态**：开发中（2026-10-31 定案）
- **做了什么**：日志抽成**独立可复用组件**（`LogBox`）。hover / focus 时右上角浮出两个图标按钮：复制全部、导出 `.txt`。常驻工具条改为悬停浮出。
- **为什么**：
  - **必须封装**：日志在「启动引导 / 服务异常 / 设置页」三处都要用，各写一套必然漂移（原项目就出现过复制在一处、导出在另一处）。
  - **为什么 hover 而不是常驻**：日志是排障时才看的东西，常驻按钮会抢内容区注意力；hover 浮出在小尺寸日志块里也不挤压正文。
- **实现要点**：
  - 复制：优先 `Clipboard.setData`，无权限时降级（Web 用 `execCommand`，桌面走系统剪贴板）。
  - 导出：桌面走**文件保存对话框**（用户能选位置、能取消），不静默落盘。文件名 `miaodock-log-YYYY-MM-DD.txt`。
  - 两个动作都**必须有可见回执**（toast），否则用户会怀疑按钮坏了。
  - 错误行高亮：按 `error|fail|exited|refused|denied|异常|失败` 匹配，只染色不删行。
  - 空态单独绘制（「本地服务还没有输出日志」），不留空黑框。
- **怎么验证**：设计稿已实现并实测：hover 前后 `opacity 0→1`、2 个按钮、导出文件名与内容正确、错误行高亮 1 行。
- **关联**：`ver1.0/assets/app.js` 的 `logBoxHTML` / `bindLogBox` · P0-F2。

## D-014 P0-F 启动引导页与状态标识落地

- **状态**：已完成（UI 部分；真实数据待 P0-C）
- **做了什么**：
  - `lib/features/manga/domain/not_ready_state.dart`：`NotReadyState` 六态 + `TranslateSource` 三选一 + `EngineRuntimeState` + `ReadinessLevel` 四色 + `deriveNotReadyView` 纯函数。
  - `lib/features/manga/ui/notready/not_ready_screen.dart`：六态一张卡，三层状态条 + 三步说明 + 动作区。
  - `lib/shared/widgets/log_box.dart`：日志组件，hover 浮出复制 / 导出（D-013）。
  - `lib/features/manga/controller/engine_controller.dart`：引擎组状态（L1+L2 合并）+ 翻译来源 + 视图模型 provider。
  - 工具条：移除「服务运行中」，改为「引擎就绪度（可点击启动）+ 翻译来源」。
  - 侧栏状态点：改为 `ReadinessLevel` 四色，不再写死绿色。
  - 投放页：引擎未启动时加**提示条**（不挡内容）。
- **为什么**：设计稿把 guide/download 做成两个独立整屏，与原项目的「服务未就绪」语义脱节；且「服务已启动」在服务常驻后无信息量。
- **关键判据（都有断言与反证）**：
  1. **引擎组就绪 = engine 与 llm 都 running**。只判 engine 会让「LLM 没起来」被当成就绪。
  2. **失败态给「重新下载模型」而非「重启」**：引擎运行时坏了，重启无用。
  3. **远程翻译不需要本机运行时**，直接可用（移动端唯一来源）。
  4. **未知翻译来源抛错不降级**：静默回落 local 会让「配错」看起来像「正常」。
- **踩坑**：
  1. `readiness` 参数在多层组件间传递时重复定义，需逐层核对。
  2. l10n 零容忍检查抓到 `log_box.dart` 里的**正则关键词**（`异常|失败`）——它不是 UI 文案但检查器无法区分，改用 `\u5f02\u5e38` 转义保留功能。
  3. `NotReadyScreen` 拆成「纯展示件 + 路由壳」两层，展示件可单测、壳只做接线。
- **怎么验证**：
  - `test/not_ready_state_test.dart` 11 条（六态派生、引擎组判据、来源三选一、degraded）。
  - `test/not_ready_ui_test.dart` 8 条（四态动作差异、三层状态条、无「稍后再说」、LogBox hover / 空态 / 错误着色）。
  - 反证 2 轮：LogBox 按钮常驻 → hover 断言失败；只判 engine 不看 llm → 2 条失败。
  - macOS 实机：`_EngineOffBanner` / `_TranslateStatusChips` 均渲染，运行时零异常。
- **关联**：D-012 · D-013 · P0-F2/F3/F4 · `ver1.0` 设计稿同步更新。

## D-015 目录约定：用户成果与产品数据分树 + 引擎安装位置可选

- **状态**：开发中（2026-10-31 定案）
- **做了什么**：
  - **漫画库**（用户成果）默认改为 `~/Pictures/MiaoDock Mangas`，**不挂进数据根**。原项目 `paths.rs:719` 有断言「库是用户成果，不得藏进 appData」。
  - **引擎运行时**（产品数据）默认 `<appData>/MiaoDock/manga/runtimes`，结构 `src/` + `venv/` + `models-store/`。
  - **下载引擎时每次弹目录选择**，默认定位到 `<appData>/MiaoDock/manga/runtimes`。**不记忆上次选择**（每次问）。
  - **新增「导入本地」**：用户可指向已有的 runtimes 目录，跳过下载直接使用。
  - **本地导入的完整性校验**：先记账，后做（见 P0-F6）。
- **为什么**：
  - 用户成果要能在 Finder 里找到、能独立备份、不该被卸载器连带删除。
  - 引擎体积大（数 GB），装在系统盘可能是用户的真实痛点；每次询问比"记忆上次"更安全 —— 用户换机器 / 换盘时不会被静默塞回旧位置。
  - 导入本地运行时支持离线安装与内网分发。
- **关联**：`platform/paths.rs`（原项目基准）· P0-C1 前置 · P0-F6（校验，待做）。

## D-016 模型目录改挂 state 下（刻意偏离原项目）

- **状态**：已完成（2026-10-31）
- **做了什么**：模型落盘位置改为 `<数据根>/manga/state/models-state`（`MIAO_MODELS_STORE_DIR` 可覆盖）。
- **为什么**：**原项目把 `models-store` 放在运行时根下**（`<runtimes>/models-store`，见 `model_status.rs` 的 `tmp.join("models-store")`）。但本项目的运行时目录是**用户可选的**（D-015：下载时每次询问 / 支持导入本地），若模型挂在运行时下，用户换个 runtimes 目录就要重下数 GB 模型。挂到 `state/` 后模型成为「状态资产」，与运行时解耦。
- **代价 / 已知偏离**：
  - 与原项目目录布局不一致，若将来要做「旧版数据自动迁移」，需要单独处理 `models-store` → `models-state` 的搬迁。
  - `modelsStoreDir()` 因此**不接受 runtimeRoot 参数** —— 模型位置不随运行时走，签名本身就是这条约束的表达。
- **怎么验证**：`test/paths_test.dart` 中断言「模型目录在 state 下，且**不**在运行时下」，并做了反证（改回 runtimes 下 → 该条失败）。
- **关联**：D-015 · P0-F6a · `paths.dart`。

## D-017 服务状态目录与库根分离（修 D-015 引入的泄漏）

- **状态**：已完成（2026-10-31）
- **做了什么**：`resolveToken` 的落点从 `<库根>/state/token` 改为独立 `stateDir`；新增 `--state` 参数。
- **为什么（真实缺陷）**：D-015 把库根改为 `~/Pictures/MiaoDock Mangas` 后，令牌仍写在 `<库根>/state/token` —— 即**把服务状态写进了用户相册目录**。虽然 `library_store` 用 `if (name == 'state') continue` 跳过了扫描，但那只是掩盖症状：文件仍在用户成果目录里，会被备份工具带走、卸载时不知道要不要删。
- **路径职责（最终）**：
  | 用途 | 路径 | 谁用 |
  |---|---|---|
  | 漫画库（用户成果） | `~/Pictures/MiaoDock Mangas` | `LibraryStore` / `TaskQueue` |
  | 服务状态 | `<数据根>/manga/state` | 令牌 / 隐藏清单 |
  | 引擎运行时 | `<数据根>/manga/runtimes` | 下载 / 导入（**与库无关**） |
  | 模型 | `<数据根>/manga/state/models-state` | 下载 / 校验（**与库无关**） |
- **验证**：`--root /tmp/lib-ok --state /tmp/state-ok` 启动后，库根为空、令牌在 `state-ok/token`；`store/` 与 `queue/` 源码中**零处**引用引擎路径函数。
- **关联**：D-015 · D-016 · `paths.dart`。

## D-018 P0-C1~C5 引擎端点落地

- **状态**：已完成（2026-10-31；进程拉起属 C6）
- **做了什么**：
  - `services/mangasvc/lib/src/engine/engine_runtime.dart`：五态机 `stopped/starting/running/stopping/error` + runtime 探针（三项逐项报真伪）+ 阶段日志。
  - `services/mangasvc/lib/src/engine/engine_facade.dart`：状态 / 运行时 / 选项 / 设置（白名单）/ 校验 / 下载 / 暂停 / 卸载 / 启停。
  - 路由新增 `POST /engine/start`、`/engine/stop`（D-012 引擎共用开关）。路由数 46 → **48**。
  - 客户端契约补 `startEngine` / `stopEngine`；Flutter 侧 `EngineNotifier.start/stop` 改为**调真实端点**并按返回推导状态。
- **为什么**：C1~C5 是引导页六态的数据来源。不落地它们，引导页永远停在「假数据」。
- **三条红线（都有断言 + 反证）**：
  1. **不编造下载进度**：无真实进度来源时 `percent: null`（设计稿 §07）。
  2. **未装配不假装 running**：启动时装配不齐 → 明确 `error` + 缺失原因。
  3. **版本不猜**：读 `src/version.txt`，没有就是 null。
- **已知边界（C6 补）**：
  - `start()` 目前**不 spawn 进程**（缺 Python / llama-server 二进制），装配齐了也如实落 `error: 进程拉起未实现`。
  - `download()` 不真下载（缺模型源 URL 与校验清单），保持 `running` 并明确标记。
  - 这两个「如实失败」是刻意的：假装成功会掩盖真实缺口，等 C6 接入后自然转绿。
- **怎么验证**：
  - `services/mangasvc/test/engine_test.dart` 13 条（五态、探针三项、白名单拒绝、needsRestart、校验路径、下载暂停、percent 为 null、目录创建、卸载语义）。
  - 端到端：真实服务 → 状态/探针/选项/校验/下载/暂停/启动 全链路通过。
  - 反证 2 轮：伪造 `percent` → 断言失败；未装配报 running → 断言失败。
- **关联**：D-012 · D-015 · D-016 · P0-C1~C5。

## D-019 P0-F5 设置页「翻译服务」组落地

- **状态**：已完成（2026-10-31）
- **做了什么**：
  - `lib/features/settings/ui/settings_screen.dart`：左侧分组导航（计数与原项目 `SET_NAV` 同构）+「翻译服务」组。
  - **服务卡片**：引擎组状态点（绿/黄）+ 主操作「启动 / 停止」（D-012 共用开关，一次点击拉起或停止两个进程）。
  - **来源三选一**：`SegmentedButton`，本地翻译 / 大模型翻译 / 远程翻译；移动端切到需本机运行时的来源会被 controller 拒绝。
  - **推理引擎行**：档位 / 加速后端 / 空闲卸载，由 C2 `getEngineOptions()` 的 `current` 初始化，保存走白名单校验。
- **为什么**：C1~C5 已有真实状态数据，设置页是三层状态唯一的完整展示位（工具条只放摘要）。
- **契约修正**：`setEngineSettings` 从 `void` 改为 `Future<bool>`（返回 `needsRestart`）—— 改 tier / accel 需重启引擎，UI 必须能拿到这个信号。服务端白名单校验早在 C2 已有。
- **踩坑**：
  1. 设置页用了 Riverpod，widget 测试宿主**必须包 ProviderScope**，否则 `No ProviderScope found`。
  2. 拼接文案（`引擎 + 大模型 · 本地翻译`）不能用 `find.text` 精确匹配，改用 `find.textContaining`。
  3. Dart 流分析**不提升三元里的可空值**：`trailing != null ? Text(trailing) : control` 会报 `String? → String`，需先落局部变量。
  4. `_SettingRow` 的尾件用 `?tail`（null-aware collection element）替代 if-else 链，消除 lint。
- **怎么验证**：`test/settings_ui_test.dart` 2 条（三层卡片要素 + 来源三选一 + 分组切换内容变化）。
- **关联**：D-012 · C1~C5 · `engine_settings_controller.dart`。

## D-020 P0-C6a~C6d 引擎接入基础件

- **状态**：已完成（2026-10-31）
- **做了什么**：
  - `runtime_setup.dart`（C6a）：解包 tar.gz / tgz / tar / zip，`strip-components` 默认 1。
  - `model_download.dart`（C6b）：真实 HTTP 下载 + `Range` 续传 + sha256 校验 + `.part` 原子改名。
  - `supervisor.dart`（C6c）：spawn + 健康探针 + 崩溃指数退避重启 + 主动停止不重启。
  - `engine_client.dart`（C6d）：`POST /translate/image/stream` 帧协议、图片嗅探、空闲超时、错误归一。
- **依赖**：新增 **1 个**包 `crypto ^3.0.8`（官方 Dart 团队、纯 Dart、运行时依赖，用于 sha256；体积可忽略）。**未**引入 `archive` —— 见下条。
- **为什么不用 Dart 的 archive 包解压**：Python venv 的 `bin/python` 是**符号链接**，且必须保留 `0755`。纯 Dart 解包器普遍把 symlink 写成普通文件 —— 解出来的 venv「文件都在、就是跑不起来」，症状极隐蔽。系统 `tar`（macOS/Linux 的 tar、Win10+ 的 bsdtar）同时认 tar.gz 与 zip，且与原项目 `runtime_setup.rs` 口径一致。
- **四条必须做对的地方（都有断言 + 反证）**：
  1. **续传要看响应码**：服务器可能无视 `Range` 仍返回 200。此时若追加写 = 旧前段 + 新全量 = **静默损坏**（文件大小正常）。必须清空重下。
  2. **健康 ≠ 进程活着**：进程起来要能应答 `/health` 才算就绪；只看 pid 会把加载中的引擎当可用。
  3. **主动停止不得触发重启**：否则「停止」按钮变成「重启」按钮。
  4. **超时是空闲超时**：每收一块重置。用总时长会把正常的慢请求判死；无限等则卡死。
- **踩坑（真实缺陷）**：
  - `Directory.listSync()` 默认 `followLinks: true`，把符号链接解引用成 `File`；目标已被先移走时 `File.renameSync` 的 `existsSync` 检查返回 false → `PathNotFoundException`。必须 `followLinks: false` + 按类型分发 rename，删除同名目标时同理。
  - `_mergeInto` 用 rename 而非 copy：同卷常数时间，避免数百 MB 复制。
- **反证记录**：解引用符号链接 → 3 条红；不剥顶层 → 3 条红；200 也追加 → 续传用例红；校验失败不删坏文件 → 用例红；不区分主动停止 → 需**同时**移除两道守卫才红（守卫为纵深防御，已记录）；固定退避 → 递减用例红；帧头小端 → 3 条红；不拦非图片 → 用例红；无空闲超时 → 用例红（30s 后失败）。
- **验证**：`services/mangasvc` 测试 39 → **78 条**全绿（setup 9 / download 9 / supervisor 7 / client 14）。
- **关联**：P0-C6a~d · D-015 · D-016。

## D-021 P0-C6 接线：启动规格与状态机打通

- **状态**：已完成（2026-10-31；C6e 真引擎仍需模型与硬件）
- **做了什么**：
  - `engine_launch.dart`：`<runtimeRoot>/launch.json` 描述「怎么起」（command / args / healthPath / port）。
  - `EngineRuntime.start()` 改为：装配检查 → 读启动规格 → 建 `EngineSupervisor` → 等健康 → running / error。
  - `EngineRuntime.stop()` 走监督器 `stop()`（主动停止，不触发重启）。
  - 下载骨架换为 **manifest 驱动**（`<modelsDir>/manifest.json` 的 `files[]`），逐个真实下载 + sha256。
- **为什么**：C6a–d 四个模块各自的单测都过，不代表接进状态机还能起来。接线必须单独验。
- **关键设计**：
  - **启动规格是数据不是代码**：引擎可执行文件/参数/健康路径随版本与平台变化，写死会在换版本时静默失效；读文件则「起不来」时能直接指出缺哪一项。
  - **command 提前解析并检查存在**：拖到 spawn 才失败会变成笼统的「启动失败」。
  - **缺 manifest 明确失败**，不进 running —— 否则界面显示一个永远 0% 的进度条。
- **反证记录**：不真起进程却报 running → 2 条红（pid 为 null）；忽略健康探测结果 → 「健康地址指错」红。
- **验证**：`services/mangasvc` **89 条**全绿（新增 launch/接线 9 条）。端到端真起子进程：规格正确 → running + pid + port；停止后端口可重绑（无僵尸）；manifest 下载 → 文件内容与 sha256 一致。
- **关联**：P0-C6 · D-020 · `engine_launch.dart` · `supervisor.dart` · `model_download.dart`。

## D-022 macOS 必须关闭 App Sandbox（P0-D 前置冲突）

- **状态**：已完成（2026-10-31）
- **做了什么**：`macos/Runner/{DebugProfile,Release}.entitlements` 的 `com.apple.security.app-sandbox` 改为 `false`。
- **为什么（实测发现，不是预设）**：P0-D 接线后首次真机运行报
  `起不了 mangasvc（.../dart）：Operation not permitted`。
  沙盒同时挡住三件**产品硬需求**：
  1. 拉起 `mangasvc` 子进程（P0-D1）；
  2. 写 `~/Pictures/MiaoDock Mangas` 漫画库（D-015）——沙盒会把 HOME 重定向进容器；
  3. 读 `~/Library/Application Support/MiaoDock` 下的引擎运行时（D-016）。
- **代价 / 已知影响**：
  - 无法上架 Mac App Store（本项目是本地桌面工具，不在目标内）。
  - 沙盒关闭后 `HOME` 是真实用户目录，此前写在容器里的偏好会「看起来丢失」（仅影响开发期）。
- **怎么验证**：关闭后 `[bootstrap] mangasvc dev-source → 端口 5180`，`/api/v1/health` 返回 200，
  且 `rootDir` = `/Users/doro/Pictures/MiaoDock Mangas`（证明写的是真实用户目录）。
- **关联**：P0-D1 · D-015 · D-016。

## D-023 P0-D 桌面端进程管理落地

- **状态**：D1/D2/D3 完成；D4 编译验证通过、打包未自动化
- **做了什么**：
  - `core/process/service_launch.dart`：解析启动方式（显式指定 → 随包 exe → 开发期源码）。
  - `core/process/service_supervisor.dart`：spawn + **就绪行**判定 + 退出清理 + 崩溃重启。
  - `core/process/service_controller.dart`：`ServiceStatus` provider + 生命周期清理观察者。
  - `app/shell/readiness.dart`：服务进程 + 引擎两侧合成侧栏四色。
  - `bootstrap.dart`：桌面端启动服务并注入容器。
- **三条关键判据（都有断言 + 反证）**：
  1. **就绪只认那一行**：`mangasvc listening on 127.0.0.1:<port>`。不用「端口能连上」——
     端口可能被别的进程占着，连错进程后所有请求都会莫名其妙失败。断言比对**真实端口**。
  2. **主动停止不重启**：否则「停止」变成「重启」。
  3. **失败是最终结论**：超时路径里主动杀进程不得把 `failed` 改写成 `stopped`，
     否则掩盖根因（只显示「已停止」）。杀进程触发的退出也不得覆盖超时这个根因。
- **踩坑**：
  - `Platform.resolvedExecutable` 在真实 App 里是**应用自己的二进制**，不是 dart ——
    用它 `run` 脚本只会得到「找不到命令」。改为优先 `FLUTTER_ROOT` 下的 SDK dart。
  - `flutter run -d macos` 起 App 的工作目录**不是项目根**（实测是 `/`）——
    开发期解析还要从 App 二进制目录**向上找**项目根。
  - `flutter test` 里 `Platform.resolvedExecutable` 是 `flutter_tester`，
    测试若直接用它 spawn 会全红；复用产品代码的 dart 解析。
  - 超时路径若 `unawaited(stop())`，调用方拿到的 pid 仍非空（进程还活着）。
- **验证**：
  - `test/service_supervisor_test.dart` 11 条；`test/readiness_test.dart` 3 条。
  - 反证 4 轮：解析固定端口 → 端口断言红；不区分主动停止 → 红；忽略服务状态 → 红；解析到假端口 → 红。
  - macOS 真机：自动拉起 → health 200 → Cmd+Q 后 `[lifecycle]` 两条日志出现、服务退出、端口释放。
  - `dart compile exe` 产出 6.7 MB 自包含可执行文件，能打印就绪行并返回 health 200。
- **关联**：P0-D1~D4 · D-022。

## D-024 P0-D4 打包形态：mangasvc 随 App 分发

- **状态**：已完成（macOS）；Windows / Linux 未自动化
- **做了什么**：
  - `tool/package_macos.sh`：用 `dart compile exe` 编出自包含二进制，再复制进 App（带**增量**：源码没变就跳过编译）。
  - Xcode 新增构建阶段 **Bundle mangasvc**（`macos/Runner.xcodeproj`），`flutter build macos` / `flutter run` 自动带上。
- **为什么放进构建阶段而不是事后复制**：构建阶段在**代码签名之前**执行，Xcode 之后统一签名整个 bundle ——
  额外二进制会被一并签进去。事后复制会破坏签名封条（`codesign --verify --deep --strict` 会失败）。
- **实测数据**：
  - 开发期 `dart run` 启动约 **10 s**；打包后 **395 ms** 到服务就绪。
  - Debug / Release 两种构建都产出 `Contents/MacOS/mangasvc`（6.7 MB），签名校验均通过。
  - `[bootstrap] mangasvc bundled → 端口 5180`，`/api/v1/health` 200，
    `rootDir` = `~/Pictures/MiaoDock Mangas`（D-015 生效）。
- **失败不静默**：脚本在目标目录不存在、找不到 dart 时**非零退出**，Xcode 构建随之失败 ——
  不产出「看起来构建成功、其实缺服务」的包。
- **已知限制**：
  - 应用被 **SIGKILL** 时 `didRequestAppExit` 不会执行，子进程会变孤儿占住端口。
    彻底解法是让服务在 stdin 关闭（父进程死亡）时自行退出，属后续增强。
  - 通过 `osascript quit` 退出时 AppleScript 报 `-128`：因为 `didRequestAppExit` 里
    **先**等清理完成**再**回复，Apple 事件超时。App 与服务都正常退出，仅自动化脚本会看到该码。
  - Windows / Linux 的分发目录未脚本化（解析逻辑已支持「与 App 同目录」）。
- **验证**：`flutter build macos --debug/--release` → 包内有 mangasvc → `open` 启动 → 健康 200 →
  退出后 App 与服务都消失、端口释放。
- **关联**：P0-D4 · D-022 · D-023。

## D-025 更正：C6e 不是「无法验证」，是「验证代价高且需授权」

- **状态**：更正已记录（2026-10-31）
- **要更正什么**：D-020 / D-021 与迁移文档里写「C6e 需真实模型与硬件」，说法**过于笼统**，
  会让人以为本机根本做不了。实测后应改为下面这三档。
- **实测环境事实（2026-10-31）**：
  | 项 | 实测 | 对 C6e 的影响 |
  |---|---|---|
  | 系统 Python | 3.14.2 | torch / manga-image-translator **没有 3.14 轮子**，须另装 3.11 |
  | GitHub release | 200，**支持 Range（206）** | 真实下载与断点续传**可验证** |
  | HuggingFace 直连 | 000（不通） | 模型权重不能走官方站 |
  | hf-mirror.com | 200 | 模型权重**可经镜像获得** |
  | GPU | Apple M4 / Metal 3，无 CUDA | 只能用 MPS/Metal，能跑但性能不同 |
  | 内存 | 16 GB | 7B 量化 + 视觉栈偏紧，有 OOM 风险 |
  | 磁盘 | 50 GiB 可用 | 够（依赖 + 权重约 7 GB） |
- **因此分三档**：
  1. **可立即验证（小）**：真实 CPython 包 → `runtime_setup` → 可执行位 → 能跑。
     已实测：`cpython-3.11.10 install_only.tar.gz`（17 MB）解出后 `python3` 权限 755、`Python 3.11.10` 正常输出版本。
  2. **可用桩验证（中）**：用 Python 写一个说同样帧协议的桩引擎，
     把 supervisor + 帧解析 + 状态机跑在**真实 Python 进程**上。
  3. **须授权（重）**：真装 manga-image-translator（torch 约 2 GB）+ 经镜像下 Sakura（约 3.3 GB）+ 跑 7B。
     约 7 GB 下载与数十分钟计算，属对本机的实际占用，**需用户明确同意**。
- **关联**：P0-C6e · D-020 · D-021。

## D-026 模型分发走 HF 镜像优先；测试漫画不入库

- **状态**：已定案（2026-10-31）；下载清单见 `docs/internal/engine-downloads.md`
- **做了什么**：
  - **HuggingFace 策略改为镜像优先**：`hf-mirror.com` 首选，官方站仅兜底。
  - `test-manga/` 加入 `.gitignore`（本地 2 张 800×1142 JPEG，用于翻译冒烟验证）。
- **为什么**：实测本机 `huggingface.co` **不可达（000）**、`hf-mirror.com` 200 ——
  不优先镜像就装不上，这不是偏好问题。`sources` 字段已在 manifest 里，但目前只写了镜像一条，
  兜底顺序需补。
- **测试漫画为什么不入库**：体积与版权都属本地素材，仓库不该承载；
  但引擎验证必须有真实漫画页，故固定目录名 `test-manga/` 作为约定。
- **关联**：P0-C6e · D-025 · `engine-downloads.md`。

## D-027 引擎目录收束为一个可搬的根（废止 D-016）

- **状态**：已完成路径层 / 部件模型 / 校验 / 设置页部件表（2026-11-01）；下载流程与后端选择待接
- **做了什么**：
  - 引擎目录 `<数据根>/manga/runtimes` → **`<数据根>/manga/engine`**。
  - 模型从 `<state>/models-state` 挪进 **`<engine>/models`**（MIT 的 `model_dir`）。
  - Sakura 权重放 **`<engine>/llm`**（与 `models/` 平级）。
  - **删除 venv**：依赖直接装进 `<engine>/python` 的 site-packages。
  - 新增「部件模型」（`packages/protocol/lib/src/engine_parts.dart`）：7 个部件 + manifest 前缀改写表 + 后端枚举。
  - 新增「校验」（`lib/core/storage/engine_inspect.dart`）：结构 → 可运行（真的 `import torch`）→ 元数据。
  - 导入对话框加「校验」按钮；**失败才出日志**（复用 `LogBox`），并给「重新下载缺失部件」。
  - 设置页「引擎与模型」小节：目录 + 更改 + 导入 + 部件表 + 校验结论。
  - 🔴 **三态**：未校验 / 通过 / 失败。「未校验」必须与「通过」长得不一样 ——
    把没检查过的画成绿色，等于给出虚假的安心。
- **为什么（推翻 D-016 的实测依据）**：
  - **venv 不可搬迁**：`pyvenv.cfg` 记录绝对路径，移动后 `bin/python` 直接坏
    （实测 `bad interpreter: No such file or directory`）。
  - **自带 Python 可搬迁**：移动后 `sys.prefix` 自动跟随、pip 与已装依赖照常可用
    （实测 `numpy 2.4.6` 与 `einops` 导入正常）。「一个目录可搬」与 venv 互斥。
  - D-016 当初的理由是「换 runtimes 不重下模型」；该场景现由**部件级导入**覆盖，
    理由不再成立。
- **目录职责**：`engine/` 全是「下载来的、可搬、可分享」的资产；
  `state/` 全是「运行期自产」的状态（令牌 / 队列）。混放会让「导入别人的引擎目录」
  顺带把别人的令牌导进来。
- **为什么 Sakura 不放进 `models/`**：`models/` 就是 MIT 的 `model_dir`，
  结构要能原样对照上游；Sakura 归 llama-server（`SakuraTranslator` 只是 HTTP 客户端，
  MIT 一行代码都不读它的权重）。混放会让升级引擎与我们的资产互相牵制。
- **踩坑**：
  - python-build-standalone 在 **Windows 是完整安装**（`python/python.exe`），不是 venv 的
    `Scripts/python.exe`；解释器路径必须按平台分叉。
  - MIT 的 `model_dir` 默认是 `<src>/models`，启动引擎**必须显式 `--model-dir`**，
    否则会去源码目录找，离线机器上表现为卡住。
  - 校验的 deps 必须**真的 import 一次**：只查 site-packages 非空会把「装了一半」判成就绪。
- **反证**：nllb 改成必需 → 3 条红；Sakura 留在 `models/` 下 → 2 条红。
- **验证**：`test/paths_test.dart` 21 条（两棵树、逐部件落点、前缀映射、平台分叉、长路径、结构级校验、后端枚举）。
- **关联**：D-015 · D-016（废止）· D-025 · `engine-downloads.md`。

## D-028 装配端点与真实小样验证

- **状态**：已完成（2026-11-01）；deps（pip）与 launch 规格仍待做
- **做了什么**：
  - `POST/GET /api/v1/engine/install`：按平台 + 后端装配整个引擎目录，进度可轮询。
  - `parts` 参数支持**只装某几个部件**（小样验证与「补下单个部件」共用一条路径）。
  - 客户端加 `installEngine` / `getEngineInstall`。
- **真实小样验证（macOS arm64，2026-11-01）**：
  - 只装 `python + src + llama`（约 91 MB），真实走 GitHub / 南大镜像下载。
  - 结果：`/tmp/sm-eng` 289 MB，`python/` `src/` `bin/llama/` 齐全，`.engine.json` 记录平台与条目 sha256。
  - `python/bin/python3` **仍是符号链接**（`lrwx`）—— 系统 tar 保留了链接，与 D-020 的结论一致。
  - App 侧 `inspectEngine` 对真实目录的结论：
    `python OK (Python 3.11.17)` · `src OK` · `llama OK` · `deps FAILED`（`ModuleNotFoundError: No module named 'torch'`）· `models-visual / llm` 缺失 · `nllb` 按需。
- **发现的两个阻塞点（下一步必做）**：
  1. **`server/args.py` 没有 `--model-dir`** —— 模型目录如何传给引擎**尚未确认**，
     `launch.json` 不能凭空写。需要读 `server/main.py` 的 `prepare()` / `instance.py` 找到真实入口参数。
  2. **deps 未实现**：`python/` 里没有 torch，校验如实报 `ModuleNotFoundError`。
- **踩坑**：`parts` 过滤最初只加在门面签名里、没往下传，导致一次真实请求按「全部必需件」下了 4.7 GB
  （已及时停掉）。**教训：新增参数后必须验证它真的到达使用点**，否则默认分支会静默接管。
- **关联**：D-027 · `engine_install.dart` · `engine-downloads.md`。

## D-029 依赖重建走国内镜像优先

- **状态**：已完成服务端（2026-11-01）；UI 按钮待接
- **做了什么**：
  - `engine_deps.dart`：用**自带 Python** 跑 `pip install -r src/requirements.txt`。
  - 默认源 `https://pypi.tuna.tsinghua.edu.cn/simple`（国内优先，可覆盖；传空串表示用 pip 默认）。
  - `POST /api/v1/engine/deps/rebuild` + `GET /api/v1/engine/deps`；客户端 `rebuildDeps` / `getDepsStatus`。
  - 参数带 `--progress-bar off`：进度条会把日志刷满，排障时反而看不到错误。
- **为什么是「重建」而不是「安装」**：带别人的引擎目录过来时，依赖可能因 Python 小版本 / 架构 / 平台不匹配而不可用；
  这时需要的是重装依赖，**不是**重下 4 GB 模型（D-028 的 `deps` 部件就是为这个留的）。
- **体积必须提前告知**：macOS 的 torch 是数百 MB 量级；**Windows CUDA 版约 2.5 GB**。
  不告知就点，用户会以为只是几十 MB。
- **怎么验证**：`services/mangasvc/test/engine_deps_test.dart` 7 条（前置检查、镜像默认与覆盖、空串语义、参数透传、非零退出）。
  反证：把默认源改空 → 「默认走国内镜像」立即红。
- **关联**：D-028 · `engine-downloads.md` §三（pip 依赖）。

## D-030 引擎模型目录的实际解析链（推翻 D-027 的假设）

- **状态**：已查明（2026-11-01）；**需要改落点，待定案**
- **查到了什么**（读源码得出，不是推测）：
  1. HTTP API 入口是 `python server/main.py --host … --port … --start-instance`
     （`server/main.py` 末尾直接 `uvicorn.run(app, …)`）。
  2. 它会再 spawn 一个翻译进程（`server/main.py:244`）：
     `python -m manga_translator shared --host … --port … --nonce …`，且 **`cwd=src`**。
  3. 翻译进程的模型根 = `BASE_PATH/models`，其中 `BASE_PATH = os.path.dirname(MODULE_PATH)`
     （`utils/generic.py:25`）→ 即 **`<engine>/src/models`**，与 cwd 无关。
  4. `--model-dir` **只存在于顶层 `g_parser`**（`args.py:85`），而子命令
     `ws` / `shared` 创建时**没有继承它**（`args.py:114` 起 `add_parser` 未传 `parents`），
     所以**命令行无法指定模型目录**。
- **结论**：D-027 把模型放在 `<engine>/models` 与引擎实际读取的 `<engine>/src/models` **不一致**。
  按现状启动，引擎会去 `src/models` 找，找不到就表现为卡住或尝试联网下载。
- **候选方案**：
  | 方案 | 做法 | 代价 |
  |---|---|---|
  | A **软链** | 装配后建 `<engine>/src/models` → `../models` | macOS/Linux 天然支持；Windows 建软链需权限（开发者模式/管理员），可能失败 |
  | B **直放** | 模型直接装到 `<engine>/src/models` | 与「MIT 的 model_dir 独立」初衷相悖，但零平台风险 |
  | C **改上游** | 给 MIT 打补丁让 `shared` 支持 `--model-dir` | 维护成本；每次升级引擎要重打 |
- **建议**：默认 **B（直接放 `src/models`）**，把 `<engine>/models` 去掉。
  理由：软链在 Windows 上是**权限陷阱**（普通用户建不了），而「模型放哪」对我们的价值远低于「Windows 上能装上」。
  若将来要支持「模型与运行时分离」，再引入 C 或平台分支。
- **关联**：D-027（部分推翻）· `engine-downloads.md` §六。

## D-031 模型落点改为 `<engine>/src/models`（方案 B，部分推翻 D-027）

- **状态**：已完成（2026-11-01）
- **做了什么**：
  - `mapManifestDest` 的 `models-store/` → **`src/models/`**（`models/sakura/` 仍是 `llm/`）。
  - `engineModelsDir()` = `<engine>/src/models`；部件 `models-visual` / `models-nllb` 同步。
  - 部件归属判定改为**先判模型再判源码**，否则 `src/models/...` 会被算成 `source`。
  - 装配成功后写 `launch.json`：`python server/main.py --host 127.0.0.1 --port <空闲端口> --start-instance`，健康检查 `/openapi.json`。
- **为什么选 B 而不是软链（方案 A）**：Windows 建软链需要管理员或开发者模式，**普通用户会失败**；
  而这类失败在 macOS 上完全测不出来。「模型放哪」的收益远低于「Windows 上能装上」。
- **为什么 launch 用 `server/main.py`**：HTTP API（`/translate/image/stream`）在 `server/main.py`；
  `manga_translator shared` 是它自己 spawn 的**翻译子进程**，那上面没有这个路由。
- **为什么健康检查用 `/openapi.json`**：上游没有 `/health`；FastAPI 默认提供 openapi，无需改上游。
- **仍未验证**：`launch.json` 是**推测性**装配（字段 `provisional: true`）。
  真正能否起来要等依赖装完 + 模型到位后实测；`--start-instance` 与 `upload-cache` 的工作目录行为也待确认。
- **验证**：`test/paths_test.dart` 21 条、`engine_install_test.dart` 11 条（含 launch.json 内容断言）。
- **关联**：D-027（部分推翻）· D-030 · `engine-downloads.md`。

## D-032 真实 pip 失败根因：上游依赖直连 GitHub

- **状态**：已查明并加固（2026-11-01）；macOS 仍需 GitHub + Xcode CLT
- **实测**：在真实装配出的 289 MB 目录上跑 deps 重建，pip 失败：
  `github.com didn't respond within 15 seconds (while establishing a connection)`，退出码 1。
- **根因**（读下载下来的 `src/requirements.txt` 得出，共 63 行）：
  ```
  pydensecrf@https://github.com/lucasb-eyer/pydensecrf/archive/refs/heads/master.zip
  --extra-index-url https://frederik-uni.github.io/manga-image-translator-rust/python/wheels/simple/
  rusty-manga-image-translator
  ```
  也就是说：**deps 重建必然依赖 GitHub 可达**，不是纯 PyPI 行为。
- **加固**：pip 参数加 `--timeout 60 --retries 5`（默认 15s 太短，实测直接失败）。
- **两个重要发现**：
  1. **`miao-dock/runtimes/manga-translator/src/requirements.txt` 与我们下载的源码版本不一致**
     （本地那份 25 行、无 GitHub 依赖；下载的 63 行、有 `pydensecrf@github`）。
     ⇒ 依赖必须从**实际下载的源码**读，不能照抄仓库里那份旧的。
  2. **macOS 没有 pydensecrf 预编译 wheel**（`wheels.manifest.json` 只有 `win32-x64`），
     所以 macOS 上它要**从源码编译** ⇒ 需要 **Xcode 命令行工具**。
     这正是原项目注释里说的「macOS 零配置唯一缺口」。
- **对产品的含义**：
  - Windows：可走预编译 wheel，避开编译；仍需 GitHub（除非我们把 wheel 随包分发）。
  - macOS：需要 GitHub **且** 已装 Xcode CLT，否则 deps 必然失败 —— 界面必须把这两条写进失败提示。
- **关联**：D-029 · `engine-downloads.md` §三。

## D-033 引导页接上真实装配（UI 接线完成）

- **状态**：已完成（2026-11-01）
- **做了什么**：
  - `engine_install_controller.dart`：装配状态 provider（`running/done/error/logs/percent`），
    调 `installEngine` 后每 800ms 轮询 `getEngineInstall`，终态自动停止。
  - `notReadyViewProvider` 改为由**真实状态**驱动：
    装配中 → `downloading`（进度透传，无来源则为 null）；失败 → `failed`（日志交给 `LogBox`）；
    完成 → `installed`。
  - 引导页主按钮：未装配/失败 → 选目录 → 开始装配；已装 → 起引擎。
  - 导入本地：校验通过后记住目录（会话内），让「导入」立刻生效。
- **为什么状态放 Notifier 而不是 FutureBuilder**：装配是分钟级长任务，
  用户切走再回来进度不能归零。
- **临时取舍（需后续补）**：
  - 导入的目录**只在会话内有效**，未落盘 —— 落盘要等设置页有「引擎目录」设置项。
  - Windows/Linux 的**后端选择弹窗尚未接**，目前传 `null`（服务端按 auto 处理）。
- **反证**：`if (install.running)` 改成 `if (false)` → 「装配中 → downloading」立即红。
- **验证**：`test/engine_install_view_test.dart` 4 条；全量 `flutter test` 106 通过 + 11 跳过。
- **关联**：D-027 · D-028 · D-029 · D-031。

## D-034 引擎目录落盘 + 后端选择弹窗

- **状态**：已完成（2026-11-01）
- **做了什么**：
  - **引擎目录持久化**：`engineRootProvider` 读 `shell_prefs`（键 `miao.engine-dir`），
    导入/选择后立即落盘。此前只在会话内有效，重启即回默认 —— 等于「导入白做」。
  - **后端选择弹窗**（`backend_picker.dart`）：只在 **Windows / Linux** 出现；
    候选取 `自动 / CPU / Vulkan / CUDA 12.4`，**不含 DirectML**（llama.cpp 无该构建）。
    体积直接写在选项上（CUDA ≈ 626 MB vs Vulkan ≈ 32 MB，差 20 倍）。
  - 探测只返回**结构化结论**（推荐后端 + 厂商），文案在 UI 层由 ARB 拼 ——
    否则 UI 层会出现硬编码中文（l10n 零容忍会拦）。
- **为什么探测与文案分离**：`probeBackend()` 在测试里要能脱离 `BuildContext` 跑；
  而文案必须走 ARB（D-006）。两者混在一起，要么测试起不来，要么文案绕过 ARB。
- **未验证**：Windows / Linux 上的真实探测（本机是 macOS）。
  macOS 不适用后端概念（只有一种构建），走不到这个弹窗。
- **反证**：把「无卡」分支改成推荐 CUDA → 「没有 NVIDIA → 不推荐 CUDA」立即红。
- **验证**：`test/backend_picker_test.dart` 3 条；全量 109 通过 + 11 跳过。
- **关联**：D-027 · D-033 · D-035（镜像结论）。

## D-035 依赖清单清洗（解决 404 索引）

- **状态**：已完成（2026-11-01）；**完整 pip 安装未重跑**（需再下数百 MB）
- **做了什么**：`sanitizeRequirements()` 读上游 `requirements.txt`，产出 `requirements.miaodock.txt`：
  - 丢弃 `--extra-index-url` / `--index-url` / `--find-links` / `--trusted-host`（我们自己给源）；
  - `pkg@https://…` 默认保留；传 `githubMirror` 时可整体加前缀改写。
  - **不改上游原件**：出问题时能对照「我们改了什么」。
- **为什么**：实测上游 `--extra-index-url https://frederik-uni.github.io/.../simple/` 已 **404**；
  该索引上的包在 PyPI 上仍可装（`rusty-manga-image-translator 0.12.1` 实测存在），
  所以**删掉这行反而是正解** —— 找镜像救不了一个已经不存在的索引。
- **真实验证**（用真上游清单跑的，不是构造数据）：
  - 只装 `src`（53.5 MB）到 `/tmp/deps-verify`；
  - 清洗结果：**丢弃 1 个索引项、改写 0 个**，63 行 → 62 行；
  - 清洗后 `pydensecrf@https://github.com/...` 保留，404 索引消失。
- **仍未做的验证**：完整 `pip install`（会再下数百 MB 到 GB 级）。所以「依赖能装完」
  仍属**未证实**；已证实的只是「清单不再指向 404 索引」。
- **关联**：D-029 · D-032 · D-034。
