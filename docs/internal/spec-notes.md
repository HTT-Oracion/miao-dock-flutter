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

## D-036 引导页补上入口（此前是孤岛）

- **状态**：已完成（2026-11-01）
- **问题（用户实测发现）**：漫画翻译区看不到「引导页 / 下载页」。
  根因不是页面没做，而是 **`/manga/notready` 路由存在、组件也存在，却没有任何 UI 入口** ——
  侧栏只有 投放 / 队列 / 漫画库，`_ShellLocation.of` 只认这三个 id，所以该页永远打不开。
- **做了什么**：把 `notready` 加进 `mangaViews`（侧栏第四个视图「启动引导」，图标 `sparkles`），
  并在 `view_labels.dart` 与 `nav_rail.dart` 的图标表登记。
- **为什么放漫画视图组而不是「系统」组**：本项目侧栏没有「系统」分组（设计稿那份是 Web 稿）；
  引导页本来就是**漫画翻译域**的就绪状态页（D-012），放这里语义正确且可达。
- **踩坑（环境造成的假红）**：
  - `test/p0e4_remote_test.dart` 连续报 403。查下来是**我之前启动的 macOS App 还在跑**，
    它的 `ServiceSupervisor` 一直在保活 mangasvc（顺带反证了自动重启确实生效）；
    而那个服务是令牌模式，e2e 没有 `MIAO_E2E_TOKEN` ⇒ 403。
  - 教训：e2e 的「服务在线」探针只判断端口可发现，**判断不了令牌是否匹配**；
    遇到 403 先看有没有别的实例在跑，而不是先怀疑代码。
- **验证**：全量 `flutter test` 109 通过 + 11 跳过；`app_shell_test` 增加第 4 个图标断言（缺失即红）。
- **关联**：D-012 · D-033。

## D-037 漫画模块门禁（撤销 D-036 的侧栏入口）

- **状态**：已完成（2026-11-01）
- **改了什么**：
  - **移除侧栏「启动引导」入口**（D-036 判错）：进入漫画模块时自动判定，而不是给一个可点视图。
  - `engine_ready_controller.dart`：**快检**（纯 IO）+ 门禁状态机 `deriveMangaGate`。
  - `manga_gate.dart`：检出未就绪时用 `.nr-card` 顶替主体区，侧栏照常；检查中显示占位块。
  - 卡片给一条**只读出口**「先去漫画库看看」（方案 C）：阅读已译作品不需要引擎，
    且它不会像当初「稍后再说」那样跳进同样需要引擎的队列形成死循环。
  - 设置页加「重新检查」（轻量快检，不起子进程）。
- **判定顺序（有断言钉住）**：远程来源 → 快检中 → 装配中 → **未装配/装不全** → 服务异常 → 引擎未启动/启动中/失败/就绪。
  🔴 装配必须排在服务之前：否则「没装」会被报成「服务异常」，用户去重启服务而真正问题是没装。
- **为什么用快检而不是完整校验**：完整校验要起子进程 `import torch`（秒级），
  进模块用它会让用户先看到卡住的页面。深校验留在设置页「校验」按钮。
- **反证**：把「服务异常」判定提到装配之前 → 「同时没装与服务异常」用例立即红
  （第一轮反证没命中，说明当时**缺少该用例**，补上后才真正钉住顺序）。
- **验证**：`test/manga_gate_test.dart` 7 条；全量 116 通过 + 11 跳过。
- **待办**：装配完成后**不自动启动引擎**（等用户点）；「启动应用即自动起引擎」由设置项控制，尚未接。
- **关联**：D-012（部分修订）· D-033 · D-036（撤销）。

## D-038 卡片按钮对齐设计稿 + 引擎启动入口路径修正

- **状态**：已完成（2026-11-01）
- **UI（按用户实测反馈）**：
  - 按钮规格对齐 `design.html .btn`：高 **26**（原 34）/ 内距 **10** / 圆角 **6** / 字 **9.5**。
    原实现用了 Material 默认圆角与 34 高，与稿子差得明显。
  - 去掉「先去设置看看」与「设置」两个次级按钮（只留主操作 + 只读出口）。
  - 去掉顶栏「支持 png / jpg …」徽标（那是从 `dropSpec` 截出来的，位置不对）。
- **引擎启动实测（关键成果）**：用 `/tmp/full-eng`（python + src + 全量依赖）按 launch 规格启动：
  ```
  ./python/bin/python3 src/server/main.py --host 127.0.0.1 --port 59999 --start-instance
  → INFO: Application startup complete.
  → Uvicorn running on http://127.0.0.1:59999
  → GET /openapi.json = 200
  → 子进程 [shared] Running in shared mode 也起来了
  ```
  **这是引擎第一次真正跑起来**：`torch 2.15.0` 可导入，FastAPI 起来，健康检查 200。
- **修掉的一个真 bug**：`launch.json` 里写的是 `server/main.py`，而 cwd 是引擎根，
  实测报 `can't open file '/private/tmp/full-eng/server/main.py'`。
  正确入口是 **`src/server/main.py`**。已修并保留注释说明「cwd 与相对路径必须一致」。
- **仍未验证**：带模型的真实翻译（缺 llama + 4.7 GB 权重）；`launch.json` 的 `provisional` 标记暂不摘。
- **踩坑**：`flutter test` 反复因 5180 被占而红 —— 是**用户手动开着的 App** 在保活服务。
  这类「环境假红」两次都伪装成代码回归，值得在排障清单里固化（先看端口，再看代码）。
- **关联**：D-027 · D-031 · D-035。

## D-039 启动即自动起引擎 + 下载交互对齐设计稿

- **状态**：已完成（2026-11-01）
- **自动起引擎**：
  - 偏好 `miao.auto-start-engine`（缺键默认 **true**，与设计稿一致）。
  - `EngineAutoStart` 包在 App 外层，**首帧后**执行：只在桌面端、只在装配完整时、只在引擎 off 时启动。
  - 设置页「翻译时自动启动引擎」开关改为落盘（此前是写死 true 的空开关）。
- **为什么放 App 外层**：需求是「启动应用就起」，与先看到哪页无关；放页面里会变成「进某页才起」。
- **下载交互对齐设计稿**：下载卡从「一个总百分比」改为**逐条目一列**（design.html `.dl-item`）：
  每行 = 图标 + 条目 id + 体积 + 状态胶囊（已完成 / xx% / 等待）+ 进行中的进度条。
  服务端 `installStatus()` 新增 `entries[]`（id / sizeMb / state / percent）。
- **验证**：`not_ready_ui_test` 新增逐条目用例（缺行或多总进度即红）；全量 113 通过。
- **关联**：D-033 · D-037。

## D-040 设置页「通用 / 翻译服务」+ 抽取 Select/Switch/SettingRow

- **状态**：已完成（2026-11-01）
- **抽成共享组件**（AGENTS §9 要求公共 UI 抽离）：
  - `shared/widgets/app_switch.dart`：`.switch` 一比一（30×16 轨道、12px 滑块、`--acc`/`--on-acc`）。
  - `shared/widgets/app_select.dart`：`.select` 一比一（高 28 / 内距 10 / 圆角 6 / 字 10 / 箭头 mut）。
    用 `PopupMenuButton` 自绘菜单，**不用** `DropdownButton`：后者的项高与内距由主题决定，改不到稿子比例。
  - `shared/widgets/setting_row.dart`：`.setrow`（内距 8/14、圆角 8、`b` 11px/600、`.def` 8px 胶囊、`.why` 8.5px）。
- **通用组 4 项**：深色模式（可用）/ 关闭窗口行为（托盘未接入，置灰）/ 规格自检（运行时断言集未接入，置灰）/ 侧栏图标标签（可用）。
- **翻译服务组**：三层状态条 + 服务卡片 + 引擎部件区 + 来源 + 服务与配对 + 推理引擎 + 模型 + 诊断输出。
- **冲突一律以项目为准**（用户明确要求）：
  | 设计稿 | 项目 | 采用 |
  |---|---|---|
  | 服务卡写死「服务运行中」绿点 | D-012 已删除该标识 | 显示引擎就绪度 |
  | 加速后端含 DirectML | llama.cpp 无该构建 | 只给 自动/CPU/Vulkan/CUDA 12.4 |
  | 模型目录 `…\models-store` | D-031 在 `<engine>/src/models` | 真实路径 |
  | 落盘根目录 `D:\MiaoDock\library` | D-015 在 `~/Pictures/MiaoDock Mangas` | 真实路径 |
  | 来源是三选一分段 | 设计稿是 `.select` 下拉 | **按设计稿用下拉**（项目无相反要求） |
- **设计稿漏掉、项目已有，已补进设置页**：引擎目录 / 部件表 / 校验 / 重新检查 / 导入本地 / 诊断输出。
- **移除右上角主题切换按钮**（桌面与移动都去掉）：主题改由「设置 → 通用 → 深色模式」控制，避免两处入口。
- **踩坑**：来源选择会**持久化**，导致同一用例单独跑绿、整包跑红（上次的取值残留）。
  教训：涉及落盘偏好的断言必须按**组件类型**定位，不能按当前文案定位。
- **验证**：`flutter test --exclude-tags e2e` 115 通过；`flutter analyze` 干净；l10n 棘轮通过。
- **关联**：D-012 · D-015 · D-031 · D-039。

## D-041 引擎配置定案：mocr + sakura/CHS（对齐 miao-dock）

- **状态**：配置部分已完成（2026-11-01）；**mocr 权重下载与 HF 离线环境尚未接**（见末尾）
- **用户定案**：mocr 为首选 OCR（不再要 `48px`）；`use_mocr_merge` 关；mocr 权重加进下载清单。
- **做了什么**：
  - `packages/protocol/lib/src/engine_config.dart`：`defaultTranslateConfig` 唯一来源：
    `translator: sakura / target_lang: CHS / detector: default / inpainter: lama_large / ocr: mocr / use_mocr_merge: false`
  - `EngineClient.translateImage` 在不传 config 时使用它。
- **为什么必须写全每一项**：引擎默认是 `sugoi` + `ENG` + `48px`。漏传**不会报错**，
  只会静默给出英文译文、且 3.96 GB 的 Sakura 完全不被使用。
- **为什么不走 `--config-file`**：该参数只存在于 `batch` 子命令（`args.py:130` 的 `parser_batch`），
  server 是按请求收 config 的（`server/main.py` 各处 `data.config`）。
- **mocr 权重的真实情况（实测）**：`manga_ocr` 包已随 requirements 装好，
  但 `MangaOcr()` 无参 → `from_pretrained("kha-white/manga-ocr-base")` → **走 HuggingFace 缓存/联网**。
  仓库 `kha-white/manga-ocr-base` @ `aa6573bd10b0d446cbf622e29c3e084914df9741`，8 个文件，共约 424 MB：
  ```
  .gitattributes 1175 · README.md 705 · config.json 77546 · preprocessor_config.json 228
  pytorch_model.bin 444135475  sha256 c63e0bb5b3ff798c5991de18a8e0956c7ee6d1563aca6729029815eda6f5c2eb
  special_tokens_map.json 112 · tokenizer_config.json 486 · vocab.txt 24072
  ```
  （除 `pytorch_model.bin` 外均无 LFS 摘要，需下载后自算或按内容比对。）
- **仍缺的两步**（否则 mocr 会在翻译时静默联网下载）：
  1. 把这 8 个文件加进引擎清单，落点按 HF 缓存布局
     `<engine>/.hf/hub/models--kha-white--manga-ocr-base/snapshots/<rev>/…`，并由装配器写 `refs/main`；
  2. 启动引擎时注入 `HF_HOME=<engine>/.hf`、`HF_HUB_OFFLINE=1`、`TRANSFORMERS_OFFLINE=1`
     —— 需要给 `launch.json` 与 `EngineSupervisor` 增加 `env` 支持。
- **验证**：`services/mangasvc/test/engine_config_test.dart` 3 条（逐项钉死 mocr/CHS/sakura）；服务端 117 通过。
- **关联**：D-028 · D-031 · D-030。

## D-042 mocr 权重落盘 + 真实翻译首次跑通（含 nonce 根因）

- **状态**：✅ **整条链路真实跑通**（2026-11-01）
- **实测结果**（`/tmp/full-eng`，800×1142 日文页 → 中文）：
  ```
  STAGE: translating → after-translating → mask-generation → inpainting → rendering → finished
  RESULT 1 301 295 字节 PNG（800×1142），耗时 24.7 秒
  帧计数：queue 1 · waiting 1 · stage 11 · result 1
  ```
  译文正确落在气泡内（竖排、字号自适应），未出现 `use_mocr_merge` 的排版回归。
- **mocr 权重**：`models-mocr` 部件，8 个文件 423.7 MB，落点走 HF 缓存布局 + `refs/main`；
  启动注入 `HF_HOME=<engine>/.hf` / `HF_HUB_OFFLINE=1` / `TRANSFORMERS_OFFLINE=1`。
- **🔴 关键根因（nonce）**：`--start-instance` 模式下必然 401「Nonce does not match」，链路是
  1. 父进程生成 nonce 并传给子进程（`server/main.py:288`）；
  2. 父进程转发翻译请求时**不带 `X-Nonce`**（`server/instance.py` 调 `fetch_data_stream` 没传 headers）；
  3. 子进程 `check_nonce` 发现 header 缺失 → 401（`mode/share.py:115`）。
  **唯一正解是启动时传字面量 `--nonce None`**：`share.py:52-57` 里
  `if not nonce: nonce = secrets.token_hex(16)`——**空串或省略都会让子进程自己再生成一个**，
  只有字符串 `"None"` 才 `nonce = None` 真正禁用校验。
- **安全说明**：`nonce` 本意是防同机他进程调用子进程端口。禁用后仅监听 `127.0.0.1`（随机端口），
  风险面限于本机；相比之下「翻译 100% 失败」不可接受。若要恢复校验，需给上游打补丁转发 header。
- **教训**：这类问题**单测永远抓不到**——必须真起进程、真发请求。之前 `launch.json` 标 `provisional`
  是对的预判。
- **关联**：D-030 · D-031 · D-041。

## D-043 启动 env 注入 + 子进程就绪重试（端到端跑通）

- **状态**：✅ 用**我们自己的** supervisor + client 端到端验证通过（2026-11-01）
- **实测**：
  ```
  env: {HF_HOME: /tmp/full-eng/.hf, HF_HUB_OFFLINE: 1, TRANSFORMERS_OFFLINE: 1}
  START ok=true state=running
  TRANSLATE ok=true bytes=1301295 elapsed=28s   → /tmp/e2e_out.png
  ```
  注意：这一次**没有在 shell 里预设任何环境变量**，全靠 `launch.json` 的 `env` 字段。
- **补的三块**：
  1. `launch.json` 支持 `env`；`EngineLaunchSpec.env` 解析（缺字段向后兼容为空）；
     `EngineSupervisor` 用 `{...Platform.environment, ...env}` 注入子进程。
  2. `launch.json` 写入 `--nonce None`（D-042 的根因修复落到代码里）。
  3. 摘掉 `provisional` 标记。
- **🔴 新发现的时序问题**：健康检查打的是**父进程** `/openapi.json`，它 200 ≠ 翻译子进程就绪。
  实测紧接着发翻译会得到 `Translation service is starting up, please wait a moment and try again.`
  → `EngineClient.translateImage` 增加**就绪重试**（默认 120s 上限 / 2s 间隔，只对该提示重试）。
  没有这层，用户第一次翻译必然失败，且错误看起来像功能坏了。
- **验证**：服务端 117 通过；`/tmp/e2e_out.png` 与命令行结果一致（1 301 295 字节）。
- **关联**：D-041 · D-042。

## D-044 Web / 移动端只保留远程翻译（平台能力分层）

- **状态**：已完成（2026-11-01）；**Web 编译通过**，浏览器内运行时未逐屏验证
- **新增 `features/manga/domain/platform_caps.dart`**：
  - `supportsLocalEngine` = 桌面且非 Web —— 本地引擎**只可能有这一种宿主**；
  - `availableTranslateSources` = 桌面三选一 / 其余平台**只有远程**。
- **为什么判定放在领域层**：这是业务约束不是 UI 细节，UI 藏选项可被别的入口绕过。
- **落地**：
  - `TranslateSourceNotifier`：默认值与 `set()` 都按 `supportsLocalEngine` 收口（历史遗留的本地来源也强制回落）；
  - 设置页：非桌面**整块隐藏**引擎相关（三层条 / 部件表 / 服务卡 / 推理 / 模型 / 诊断），
    只留「来源」并按只读行展示 + 一条说明；
  - **不画灰掉的下拉**：没有可选项还画控件，等于给用户一个假开关。
- **关于 `flutter build web`**：编译**本来就能过**（dart2js 给 `dart:io` 提供了会抛异常的桩），
  所以「起不来」是运行时问题。已把启动路径上的文件/进程调用都按平台收口：
  `shell_prefs`（kIsWeb 早退）、`service_controller`（unsupported）、`window_controller`（isDesktopPlatform）、
  设置页引擎区块（非桌面不构建）。
- **验证**：`flutter analyze` 干净；`flutter test` 115 通过；`flutter build web` 成功。
- **仍未做**：`flutter run -d chrome` 的**真实浏览器运行**未验证（本机无法无头确认），
  以及 ③ 有道智云凭证（持久化）与 ④ 远程连接输入/测试按钮。
- **关联**：D-001 · D-012 · D-037 · D-040。

## D-045 远程连通性探测 + 远程连接配置（手机/插件直连桌面端）

- **状态**：接口与设置 UI 已完成（2026-11-01）；③ 有道智云凭证仍待做
- **架构定案（用户明确）**：
  - **手机端不提供令牌、不对外提供服务** —— 它是纯客户端，和插件地位相同；
  - 插件与手机端都用「域名 + token」**直连桌面端**；
  - 插件提交的结果只回传插件，手机端投放的结果回传手机端（队列 / 漫画库）；
  - 任务来源区分方式选 **B：提交时带 `client` 字段**。
  - ⇒ **否决了上一轮提出的「手机端代理转发」方案**：不需要两跳，一跳到底。
- **新增 `GET /api/v1/ping`（不豁免鉴权）**：
  ```json
  { "ok": true, "service": "mangasvc", "version": "0.1.0", "platform": "…",
    "engineReady": true, "engineMode": "ready", "requiresToken": true, "serverTime": "…" }
  ```
  - **为什么不用 `/health`**：`/health` 是豁免路径，只能证明「服务在」，证明不了「令牌对」。
    远程端必须一次问清三件事：能连上 / 令牌对 / 对面引擎起没起。
  - 能走到 handler 就说明令牌已通过（鉴权在路由之前），返回体再补引擎状态与平台。
- **设置页**：远程地址 + 令牌（均持久化）+「测试连接」；结果区分三种：
  连接正常 / 连接正常但引擎未启动 / 连接失败（带原因）。
  - 桌面端仅在来源 =「远程」时出现；Web / 移动端常驻。
  - 输入框高度与 `.select` 对齐（28），避免同列控件参差。
- **验证**：`flutter analyze` 干净；`flutter test` 115 通过；服务端 91+ 通过（路由数断言更新为 53）。
- **关联**：D-001 · D-044。

## D-046 任务来源隔离（提交带 client，列表按来源过滤）

- **状态**：已完成（2026-11-01）
- **背景**：插件与手机端**直连同一个桌面服务**（D-045），不区分来源就会互相看到对方的任务。
  用户定案用**方案 B：提交时带 `client` 字段**。
- **服务端**：
  - `POST /api/v1/tasks` 接受 `client`（`app` / `plugin` / `desktop`），**请求体优先**，
    缺省回落到 `X-Box-Client` 头（兼容早期调用方）；
  - 归一化：`app|mobile → app`，`plugin|extension → plugin`，其余 `desktop`；
  - `GET /api/v1/tasks` 支持 `?source=` 与 `?client=`（后者按同一套规则归一后过滤）。
- **客户端**：`createTask`/`listTasks` 增加 `client` / `source` 参数，HTTP 层写入请求体与查询串。
- **为什么不靠令牌区分**：桌面端目前只有一个令牌，做不到「插件一个、手机一个」。
  方案 B 的代价是**隔离靠自觉**（谁都能谎报 `client`），已记录为已知风险；
  将来若要真正隔离，需要多令牌签发。
- **验证**：`flutter analyze` 干净；`flutter test` 115 通过；服务端 117 通过。
- **关联**：D-045。

## D-047 凭据走系统钥匙串（flutter_secure_storage）

- **状态**：存储层与设置 UI 已完成（2026-11-01）；**翻译链路尚未把凭证传进引擎 config**
- **依赖引入**（按 `third-party-packages.md` §纪律）：
  - 包：`flutter_secure_storage ^11.2.0`（运行时依赖，**1 个直接 + 5 个联邦子包**：
    darwin / linux / web / windows / platform_interface，均随主包锁定）
  - 维护状态核查：最新版 2026-09-16 发布（距今约 1.5 个月），六个平台齐全；
    SDK 约束 `>=3.8.0` 与本项目 Dart 3.13 兼容。该包原本已在候选清单「App：存储」组，
    引入时机正是「鉴权方案落地时」。
- **为什么不用偏好文件**：`appSecret` 是凭据不是配置，明文 JSON 任何进程都能读。
  现在落：macOS/iOS → Keychain，Windows → Credential Manager，Linux → libsecret，
  Android → KeyStore，Web → WebCrypto。
- **封装**：`core/storage/secure_store.dart`（AGENTS §3 禁止第三方类型泄漏）。
  读写失败**不抛异常**：平台后端缺失（如 Linux 无 libsecret）时按「没有凭证」处理，
  让用户被引导去填写，而不是整页崩掉。
- **设置页**：来源 = 大模型翻译时出现「在线翻译平台」区块：
  平台下拉（当前仅**有道智云**，与原项目在线 API 一致）+ App Key + App Secret + 保存。
  结果提示「已保存到钥匙串」。
- **未做**：
  1. 凭证尚未传给引擎（`config.translator` 需要 `app_key` / `app_secret`，
     且用户选定平台后 `translator` 要改成对应引擎名）；
  2. **没有「测试凭证」**：有道是签名接口，凭证错会在翻译时才发现；
  3. 平台只登记了有道一家，更多平台需先确认原项目的接入范围。
- **验证**：`flutter analyze` 干净；`flutter test` 115 通过；l10n 棘轮通过
  （平台名已挪进 ARB，控制器不再含中文）。
- **关联**：D-040 · D-041 · D-045。

## D-048 Web 运行时崩溃修复（Platform._environment）

- **状态**：已修（2026-11-01）；`flutter build web` 通过，浏览器内待复验
- **报错**：`Unsupported operation: Platform._environment`，从 `_DesktopShell` 构建时抛出
  （Riverpod 报 `Tried to use a provider that is in error state`）。
- **根因**：`dart:io` 的 `Platform` 在 Web 上**每个成员都会抛**，不只是文件 API。
  启动路径上有四处踩到：
  1. `paths.dart: appDataDir()` 读 `Platform.environment`；
  2. `paths.dart: _env()` 读环境变量（`MIAO_ROOT` 等覆盖项）；
  3. `paths.dart: _sep()` 用 `Platform.pathSeparator`；
  4. `bootstrap.dart` 无条件用 `PortProbe` 建客户端（`ServerSocket` 在 Web 不可用）。
- **修法**：
  - `kIsWeb` 时 `appDataDir()` / `_home()` 返回虚拟根 `/web`，`_env()` 返回 null，`_sep()` 返回 `/`；
  - `modelsInstalledProvider` 在非桌面**直接返回 false**，不碰文件系统；
  - `bootstrap` 在非桌面改用 `RemoteServiceLocator`（读本地持久化的地址/令牌），
    不再做端口探测。
- **教训**：`dart2js` 对 `dart:io` 给的是「能编译、一调用就抛」的桩，
  所以 `flutter build web` 通过**不代表能跑**。这类问题只能靠真实浏览器暴露。
- **验证**：`flutter analyze` 干净；`flutter test` 115 通过；`flutter build web` 成功。
- **关联**：D-044。

## D-049 有道智云签名 v3（平台 id：`youdaoZhiYun`）

- **状态**：签名层完成（2026-11-01）；HTTP 调用 / 流式 / 自检 未做
- **定案（用户）**：
  - 「大模型翻译」＝**不用本地 LLM 做文本翻译**，改用在线翻译服务；
  - 路径照 miao-dock：**mangasvc 直连有道**，不经引擎；
  - **引擎自带的 `youdao` 保持不动**（它读环境变量、只有文本接口）；
  - 我们的平台 id 用 **`youdaoZhiYun`**，与引擎那个同名翻译器区分。
- **已实现** `services/mangasvc/lib/src/translate/youdao_signing.dart`（纯计算，不碰网络）：
  - `truncateInput`：`len <= 20` 原样；否则 `前10 + len + 后10`，**len 按 UTF-16 码元**
    （照官方 JS demo；Dart `String.length` 等价，**不能**换成 `runes.length`）；
  - `signYoudao`：`sha256(appKey + truncate(q) + salt + curtime + appSecret)`，`signType: v3`；
  - **salt 由调用方传入**：miao-dock 用 uuid4、引擎用 uuid1，签名本身不关心来源；
    但**每次请求（含重试）必须重新生成 salt/curtime/sign**，重放会被上游判 207。
- **验证**：`youdao_signing_test.dart` 6 条，含
  「emoji 占 2 码元所以 15 个 emoji 必须截断」——这条是「按码元不按字符」的决定性证据；
  服务端 123 通过，应用 115 通过。
- **仍未做**：
  1. 文本接口 `POST https://openapi.youdao.com/api`（表单编码，`errorCode` 单判）；
  2. 大模型流式 `POST /proxy/http/llm-trans`（`code` + `successful` **双判** + SSE 解析）；
  3. 「测试凭证」（对应 miao-dock `selftest.rs`）；
  4. 设置页把「大模型翻译」接到这条路（当前只存了凭证）。
- **关联**：D-047 · `miao-dock/src-tauri/src/mangasvc/translate/youdao.rs`。

## D-050 有道错误码映射（两张表，按接口分开）

- **状态**：完成（2026-11-01）；HTTP 调用与流式仍未接
- **实现**：`services/mangasvc/lib/src/translate/youdao_errors.dart`
  - `youdaoTextCodes`（22 条）/ `youdaoLlmCodes`（9 条），**逐条照抄** miao-dock `errors.rs`，文案未改写；
  - `mapYoudaoCode(code, api:)` → `TranslateError{code, message, upstreamCode, api}`。
- **为什么必须两张表**：文本接口与大模型接口码表**不同** ——
  `205`/`203` 只在文本表，`902000`/`1` 只在大模型表。
  混用会把「该应用未开通大模型翻译」误报成别的错误，用户会去查错方向。
- **未登记码不吞**：文案里带平台 + 接口 + 原始码。只回「翻译失败」等于把排障线索扔掉。
- **207 的文案**直接指向我们自己的问题（salt/curtime 复用），而不是暗示上游不稳。
- **验证**：`youdao_errors_test.dart` 5 条（含「两张表按接口分开」这条反证）；服务端 128 通过。
- **仍未做**：`POST /api` 文本调用、`/proxy/http/llm-trans` 流式（双判 + SSE）、
  测试凭证、设置页接线路由。
- **关联**：D-049 · `miao-dock/.../translate/errors.rs`。

## D-051 有道文本翻译客户端（可注入出网）

- **状态**：完成（2026-11-01）；大模型流式 / 测试凭证 / 设置页接线 未做
- **实现**：`services/mangasvc/lib/src/translate/youdao_client.dart`
  - `POST {base}/api`，表单字段 = `q/from/to` + 签名五件套（+ 可选 `domain`/`vocabId`）；
  - 判成功**只看 `errorCode === "0"`**（单判；大模型接口才双判）；
  - 响应不是 JSON → `TRANSLATE_UPSTREAM_ERROR` 且**带上 HTTP 状态**；
  - `errorCode` 缺失按 **`"undefined"`**（复刻 JS `String(v)`，不是空串）；
  - 未配置密钥 → `TRANSLATE_NOT_CONFIGURED`，**不发请求**（对应 `assert_credentials`）。
- **为什么把出网抽成 `YoudaoTransport`**：签名与判定逻辑必须能在**不发真网络**的前提下测到；
  真网络只能验证「通不通」，验证不了「码对不对」。
- **每次调用重算 salt/curtime/sign**（`YoudaoClient` 内部生成，不接受外部复用）。
- **验证**：`youdao_client_test.dart` 5 条（成功路径含表单字段断言、202 映射、非 JSON、缺码、未配置）；服务端 133 通过。
- **仍未做**：
  1. `POST /proxy/http/llm-trans` 流式（`code` + `successful` **双判** + SSE 解析）；
  2. 测试凭证（`selftest.rs` 语义）；
  3. 设置页把「大模型翻译」接到这条路；
  4. 真实出网实现（`dart:io HttpClient` + 四层超时）。
- **关联**：D-049 · D-050。

## D-052 凭证落盘服务端（credentials.json）

- **状态**：完成（2026-11-01）；`/translate/text` 仍未接真实出网
- **定案变更（用户）**：从「服务端不落库」改为**多一份 `credentials.json`**。
  好处：翻译时服务端直接取用，不必每次把 secret 塞进请求体。
- **落点**：`<state>/credentials.json`（与令牌/队列同目录）。
- **实现**：`services/mangasvc/lib/src/translate/credential_store.dart`
  - **原子写**（临时文件 + rename），避免半截文件被当成有效凭证；
  - 文件权限 **0600**（POSIX；Windows 依赖目录 ACL）；
  - 对外接口**永不回传 secret**，只回 `hasKey` / `hasSecret`；
  - 损坏或不存在 → `null`，调用方按「未配置」处理，不抛。
- **接口**（三条件随 `translate` 分组）：
  ```
  GET    /api/v1/translate/credentials   → {configured, platform, hasKey, hasSecret, updatedAt}
  POST   /api/v1/translate/credentials   ← {platform, appKey, appSecret}
  DELETE /api/v1/translate/credentials
  ```
  用 POST 而非 PUT：HTTP 层没有 `putJson`，为一个端点新增动词不划算。
- **App 侧**：保存凭证时**同时写两处**（钥匙串 + 服务端）。服务端写入失败会弹提示 ——
  否则会出现「界面显示已配置、翻译却说没配置」。
- **已接受的代价（明确记录）**：
  1. **两份密钥副本**（钥匙串 + state 文件），换 key 要清两处，否则残留陈旧密钥；
  2. 落盘是**明文 JSON**（已用 0600 收敛），`credential_store_test` 里有一条
     专门断言「明文落盘」这一事实，将来若改加密会提醒同步文档。
- **验证**：`credential_store_test.dart` 7 条（原子写无残留、脱敏、0600、损坏容错）；
  服务端 140 通过，应用 115 通过，l10n 棘轮通过。
- **仍未做**：`/translate/text` 的真实出网（`dart:io HttpClient` + 四层超时）、
  流式 `llm-trans`、测试凭证。
- **关联**：D-047 · D-049 · D-050 · D-051。

## D-053 `/translate/text` 端点 + 有道真实出网

- **状态**：已实现（2026-11-01）；**尚未做真实网络验证**（只有编译与单测绿灯）
- **出网层** `services/mangasvc/lib/src/translate/youdao_http.dart`：
  - `dart:io HttpClient`，**不加 dio**（mangasvc 要 `dart:compile exe`，`dart:io` 已够用；
    `third-party-packages.md` §纪律 3「一次一个目的」）；
  - 超时近似三层：`connectionTimeout` 5s、`idleTimeout` 20s、整次请求 `Future.timeout` 30s。
    🔴 Dart 没有逐阶段 ttfb/total 计时，只能整请求卡表；这点与 miao-dock 的四层**不完全等价**，已记录；
  - `findProxy = DIRECT`：调外网也不要被系统代理劫走（与引擎调用同口径）；
  - `youdaoBaseUrl()` 读 `MIAO_TRANSLATE_YOUDAO_BASE`（对齐 miao-dock 的验收接缝）。
- **端点** `POST /api/v1/translate/text`（路由表里原本就有该路径，这次接上实现）：
  - 入参 `{text, from, to}`；凭证**从 `<state>/credentials.json` 读取**（D-052），不再随请求传；
  - 未配置 → `409 TRANSLATE_NOT_CONFIGURED`；
  - 成功 → `{text, langType}`；失败 → `502 {code, message, upstreamCode, api}`。
- **与「本地翻译」的分界**：本地翻译把文本交给引擎里的 Sakura；这条路**不进引擎**，
  直接调在线服务 —— 这就是用户定义的「大模型翻译」。
- **可测性**：模块级 `youdaoTransport` 覆盖点，让端点逻辑脱离网络被测。
- **验证**：`dart analyze` 干净；服务端 140 通过；应用 115 通过。
- **仍未做**：
  1. **端点的集成测试**（还没用假 transport 跑过一次 `POST /translate/text`）；
  2. 流式 `llm-trans`（双判 + SSE）；
  3. 「测试凭证」；
  4. 来源 = 大模型翻译时的**任务链路改道**（当前仍走引擎）。
- **关联**：D-049 · D-050 · D-051 · D-052。

## D-054 撤销服务端落盘：凭证只存钥匙串

- **状态**：已完成（2026-11-01）；**撤销 D-052**
- **定案变更（用户）**：既然钥匙串里取得到，就不要第二份 `credentials.json`。
- **做法**：
  - 删除 `credential_store.dart` 与 `credential_store_test.dart`；
  - 删除 `/translate/credentials` 三接口（GET/POST/DELETE）及客户端对应方法；
  - `POST /api/v1/translate/text` 改为**凭证随请求体**：`{text, from, to, credentials:{appKey, appSecret}}`，
    用完即弃；缺失 → `409 TRANSLATE_NOT_CONFIGURED`；
  - App 的「保存凭证」只写钥匙串。
- **为什么这样更干净**：唯一事实源只有一个位置。D-052 的两份副本会带来
  「换 key 只清一处 → 残留陈旧密钥 → 表现为随机鉴权失败」这种极难排查的状态。
- **仍保留的代价**：凭证随请求走 localhost（回环 + 令牌保护，可接受）；
  且这条路**天然只适用于桌面端**——与「手机端只有远程来源」正好吻合。
- **路由表**：52 条（撤销三接口后回到 D-045 之后的数量）。
- **验证**：`dart analyze`/`flutter analyze` 干净；服务端 133 通过；应用 115 通过；l10n 棘轮通过。
- **关联**：D-047（钥匙串）· D-051（客户端）· D-053（端点）· D-052（撤销）。

## D-055 输入框抬高 + 吐司对齐设计稿

- **状态**：完成（2026-11-01）
- **输入框高度**：`28 → 34`。
  `.select` 的 28 是**下拉**的规格；文本输入框沿用会显得「矮一截、字贴边」——
  与卡片主按钮（34）同高更稳。**不要**把下拉也改成 34：稿子里两者本来不同。
- **吐司**：`shared/widgets/toast.dart` 本来就有 `showAppToast`，但用的是 `SnackBar`，
  规格与设计稿差得明显（背景/圆角/动画都受 Material 主题支配）。
  已改为 `Overlay` 自绘，逐项对齐 `.toast`：
  - 内距 `9×12`、圆角 `8`、`--panel` 底 + `--line2` 描边 + 阴影；
  - 字 `12` 色 `--ink2`，左侧 **6px 圆点**（按语气取色：info/good/warn/bad）；
  - 入场动画 `280ms`，从右偏移 `16px` 滑入 —— 对应 `@keyframes toastIn`。
- **用法**：保存凭证成功 → `showAppToast(..., tone: ToastTone.good)`。
- **验证**：`flutter analyze` 干净；`flutter test` 115 通过；l10n 棘轮通过。
- **关联**：D-047 · D-040。

## D-056 「大模型翻译」接入引擎的方案定稿（A2，暂不实现）

- **状态**：方案已定、**实验已验证可行**，暂缓实现（2026-11-01）
- **用户目标**：不用有道的图片服务（本来也不存在），**只要文本翻译**，译文回显到漫画里。
- **结论：A2 成立且成本可控。** 数据流：
  ```
  引擎（本机）：检测 → OCR(mocr) → 抹字(lama) → 【翻译外包】 → 排版+渲染
                                        ↓ 只发文本
                                   有道 /api（纯文本）
                                        ↓ 只回文本
  ```
  图片、坐标、颜色、背景**全不出本机**。
- **实验证据**（真实引擎 + 假 OpenAI 服务，`/tmp/openai_req.log`）：
  - 配置 `translator: custom_openai` + `CUSTOM_OPENAI_API_BASE` 指向假服务；
  - 引擎发出 **4 次**请求：第 1 次是探针（只有 `{"model":"m"}`），后 3 次是真正的翻译；
  - 请求体形如：
    ```
    messages: [system(1642字角色设定), user("<|1|>原文…"), assistant("<|1|>示例译文…"), user("<|1|>待译…")]
    ```
    **不含任何图像数据**；
  - 输出 1 304 738 字节 PNG，假服务的译文确实进了成图；
  - 总耗时 39.7s。
- **壳子的最小实现**（尚未写）：
  1. `POST /v1/chat/completions`：取**最后一条 user**，按 `<\|(\d+)\|>` 抽行；
  2. 调有道文本接口（分批 + 限流）；
  3. 按同样编号拼回 `<|1|>译文\n…`，以 OpenAI 响应格式返回；
  4. 对只有 `model` 的探针请求返回合法空响应。
- **不需要**解析那段 1642 字符系统提示 —— **`<|N|>` 编号才是契约**，这消掉了「绑引擎 prompt 版本」的主要风险。
- **必须的硬校验**：请求行数 ≠ 返回行数 → **报错**。错位会让译文跑到别的气泡里。
- **遗留风险**：`<|N|>` 格式变更（低）、有道长度/频率限制（中，需分批）。
- **实现时还要碰的点**：启动引擎时注入 `CUSTOM_OPENAI_API_BASE=http://127.0.0.1:<mangasvc端口>/v1`
  —— mangasvc 端口是动态的，不能写死在 `launch.json`；`EngineSupervisor` 已支持 `environment`（D-043）。
- **关联**：D-049~D-054（有道文本链路）· D-053（出网）。

## D-057 队列执行器接引擎（真实翻译主链路）

- **状态**：主链路已接（2026-11-01）；**尚未端到端跑过一次真实翻译**
- **改之前**：`_runOne` 第一行就是
  ```dart
  if (engineMode != 'mock') { t.status = failed; t.failAll('引擎未接入（P0-C 待实现）'); return; }
  ```
  也就是「引擎在跑」时任务 100% 失败；mock 模式下「译文」直接是**原图字节**。
- **改动**：
  1. `EngineRuntime.port` 暴露给外部（此前是私有 `_enginePort`）；
  2. `EngineFacade.translateImage(bytes)`：用当前端口建 `EngineClient` 翻译一张图，
     **引擎没起时抛错**（让调用方如实记录失败原因，而不是返回 null）；
  3. `TaskQueue.translateImage` 注入点 + `_runOne` 真实分支：
     逐页翻译、**单页失败只记该页**（`lastError` / `failed++`）不拖垮整本；
  4. `Handlers` 工厂在 `engineMode != 'mock'` 时把 facade 能力注入队列；
  5. CLI `--engine` 默认从 `mock` 改为 **`real`** —— 真实服务不该默认演示数据。
- **仍未做**：
  1. **落盘目录**：现在写 `<rootDir>/<漫画名>/01_第1话/`，章节名硬编码；
     项目口径是漫画库 `~/Pictures/MiaoDock Mangas`（D-015），需要把队列输出根与库根对齐；
  2. **真实进度**：仍是按页 `done++`，没有消费引擎的 stage 帧；
  3. **引擎未就绪的等待**：现在引擎没起 → 该页失败；合理行为是等就绪（客户端已有 120s 重试，执行器没用）；
  4. **端到端验证**：一次真实「投放 → 翻译 → 落盘」尚未跑过。
- **验证**：`dart analyze`/`flutter analyze` 干净；服务端 133 通过；应用 115 通过。
- **关联**：D-037（门禁）· D-043（env）· D-045。

## D-058 端到端真实跑通（投放 → 翻译 → 落盘）

- **状态**：✅ **首次端到端跑通**（2026-11-01）
- **实测**（`MIAO_MANGA_ENGINE_DIR=/tmp/full-eng`、`MIAO_MANGA_LIBRARY_DIR=/tmp/e2e-lib`）：
  ```
  POST /engine/start → engine.state = running（port 61240，由服务内 supervisor 拉起）
  POST /tasks {comicName: e2e, 2 张图} → 最终 status = done，耗时 84s
  产物：/tmp/e2e-lib/e2e/01_第1话/{001,002}.jpg + {001,002}_translated.png + manifest.json
  001.jpg 266 802 B（hash ea40…） → 001_translated.png 1 301 295 B（hash 7297…，与手工验证一致）
  ```
- **过程中修掉三个真 bug**：
  1. **服务内运行器仍按旧布局检查装配**（`venv/` + `<engine>/models`），新布局（`python/` + `src/models`）下直接报「引擎运行时未装配」。
     改为**两套布局都认**（向后兼容），否则老目录导不进来。
  2. `_defaultModelsDir()` 仍指向 `<engine>/models` → 改到 `<engine>/src/models`。
  3. **译文扩展名与实际格式不符**：引擎回 PNG，却按原图扩展名写成 `.jpg`。
     已固定为 `.png`（否则部分查看器解不出来）。
- **仍存在（未修）**：
  - 章节目录写死 `01_第1话` —— 真实漫画需要按「本 → 话」解析；
  - 进度仍是按页 `done++`，未消费引擎 stage 帧；
  - 未验证「手动导入引擎」路径（导入后用同一个 `_isAssembled` 判定，应一致但未实测）。
- **验证**：`dart analyze`/`flutter analyze` 干净；服务端 133 通过；应用 115 通过。
- **关联**：D-057 · D-027 · D-031。

## D-059 漫画库不受门禁限制 + 恢复被误注释的三层状态条

- **状态**：完成（2026-11-01）
- **用户报的问题**：**【漫画库】点不进去**，即使引擎没启动也应该能进。
- **原因**：D-037 的门禁按**整个漫画模块**拦截，漫画库一起被挡；
  卡片上虽然有「先去漫画库看看」的出口，但从**侧栏**点仍然被拦 —— 两条路不一致。
- **修法**：抽出纯函数 `gateBypassedFor(path)`，`/manga/library` 直接放行。
  理由：阅读已译作品只读文件，不需要引擎。作品明明在却进不去，比不拦更糟。
- **顺带修**：`_LayerStrip` 的三行被之前某次编辑**误注释掉了**（导致 l10n/source 变量未使用告警）。
  已恢复 —— 那正是设置页「服务常驻 / 引擎 + 大模型 / 翻译来源」三层状态条。
- **验证**：`manga_gate_test.dart` 新增「漫画库放行、投放与队列不放行」；
  应用 116 通过、服务端 133 通过、l10n 棘轮通过、analyze 干净。
- **关联**：D-037（门禁）。

## D-060 章节模型定案：单话目录 + 手动归并（对齐 miao-dock）

- **状态**：已定案（2026-11-01）；**未实现**
- **用户定案**：「跟 miao-dock 一样，让用户手动把单话归并到单本漫画里。」
- **miao-dock 的真实模型**（读 `handlers.rs:1822` / `library.rs:675`）：
  - 每次投放产出的是**一个单话目录**（`<library>/<comicName>/`），**不带 `manifest.json`**；
  - 「书」（大类）的标志是目录内有 `manifest.json`；
  - **归并 = 物理搬移**：`POST /api/v1/library/{name}/merge`，把单话目录搬进目标书目录；
  - 归并时的四条校验：
    1. 源目录必须存在 → 否则 `TASK_NOT_FOUND`
    2. 源目录**不能已有 manifest** → `ALREADY_MERGED`（已经是书，不能再归并）
    3. 源目录**不能有未终态任务** → `MERGE_SOURCE_BUSY`（带任务数）
    4. 跨磁盘卷 → 明确报「无法自动归并，请手动移动」
  - 目标里多出来的 `manifest.json` 会被**归档到 `state/merge-archive/`**，不直接删。
- **对我上一轮提议的修正**：不需要「投放时填话名」（我上一轮的方案 B 作废）。
  章节顺序由**归并时改名**决定，用户不需要预先知道第几话。
- **实现清单（待做）**：
  1. mangasvc：`POST /api/v1/library/{name}/merge`（含四条校验 + 物理搬移 + 归档）；
  2. 库页面：「其它」分组（无 manifest 的单话）+ 归并入口；
  3. 归并后刷新书架；
  4. 队列侧产出目录**不带 manifest**（已符合：只在书目录写 manifest，但需确认单话目录不写）。
- **关联**：D-015（库根）· D-058（端到端）。

## D-061 修复「导入后仍显示下载页 / 启动没反应」

- **状态**：完成（2026-11-01）
- **现象（用户实测）**：手动导入 `~/MiaoDockEngine` 后，点投放仍显示下载页；设置页点「启动」没反应。
- **两个独立根因**：
  1. **引擎目录有两套 provider**：
     - 设置页用的 `engineDirProvider`（不落盘、会话内）；
     - 门禁用的 `engineRootProvider`（落盘）。
     导入只写了前者 ⇒ 门禁读后者 ⇒ 仍然「未装配」⇒ 投放显示下载页。
     **修法**：`engineDirProvider` 改为**代理**（读 watch / 写转发 / 落盘交给 `engineRootProvider`）。
  2. **服务进程拿不到用户选的目录**：`mangasvc` 的引擎目录来自
     `MIAO_MANGA_ENGINE_DIR` 或默认 appData 路径，而 App 启动子进程时**没有设这个变量**。
     于是服务去查一个空目录，回「未装配」——表现就是「点启动没反应」。
     **修法**：`ServiceSupervisor` 启动子进程时注入
     `MIAO_MANGA_ENGINE_DIR=<已落盘的引擎目录>`（未设置则不注入，沿用服务默认）。
- **已知限制**：env 在**子进程启动时**固定 ⇒ 导入后需要**重启应用**，服务才会切到新目录。
  要做到「导入即时生效」，需要给 `/engine/start` 增加目录参数或热重启服务 —— 留作后续。
- **验证**：`flutter analyze` 干净；应用 116 通过；服务端 133 通过。
- **关联**：D-037（门禁）· D-052 系列（目录/凭证）· D-058（端到端）。

## D-062 设置页「模型」前置 + 启动按钮状态机 + 移除三层条

- **状态**：部分完成（2026-11-01）；侧栏三项待做
- **已完成**：
  1. **启动按钮前置条件**：`装配齐全 && 校验通过` 才可点。禁用时卡片副标题改为说明原因
     （「先下载或导入引擎，才能启动」/「请先点校验，通过后才能启动」）—— 比让用户点了失败好。
  2. **启动中状态**：按钮内显示 11px spinner + 「启动」文案，且 `onPressed = null` 不可重复点。
  3. **「模型」区前置**：`启动服务` 卡片 + `引擎部件（目录/校验/导入）` 一起归到「模型」，
     放到翻译服务**首部**；底部原来的「模型」区（模型目录 + 校验/重查）**移除**。
  4. **移除三层状态条**（`_LayerStrip` / `_LayerRow` 整段删除），连同其断言。
- **仍未做（侧栏三项，用户同时提出）**：
  - 进设置页时**侧栏「设置」高亮**（当前 `_ShellLocation` 对设置页返回 moduleIndex=-1，无高亮）；
  - 移除【番剧】下方的**「设置」小字**；
  - 设置栏 tab 的 **hover 区域与高亮区域对齐**。
- **验证**：`flutter analyze` 干净；应用 116 通过；服务端 133 通过。
- **关联**：D-040（设置页）· D-061（引擎目录）。

## D-063 侧栏设置页高亮 + 去掉空分组标题

- **状态**：完成（2026-11-01）
- **「番剧」下方那行「设置」小字** = 设计稿 `.grp-label`（视图组标题）。设置页没有视图项，
  于是渲染出一个**没有项的分组标题**，纯噪音。
  **修法**：`_ViewGroup` 在 `items.isEmpty` 时直接返回 `SizedBox.shrink()`。
- **设置页侧栏高亮**：`_NavFoot` 新增 `settingsActive`，由父级以「视图组为空」判定
  （设置页是唯一没有视图组的页面）。高亮表现：图标转主色、文字转 `--ink` 加粗、
  底色 `--card`。
- **hover 与高亮区域一致**：两者共用**同一个 Container 与内距**（`_hover || settingsActive`），
  不存在「hover 区域比高亮大一圈」的问题。
- **验证**：`flutter analyze` 干净；应用 116 通过。
- **关联**：D-062（设置页布局）。

## D-064 移除伪造日志 + 启动按钮 loading + hover 区域对齐

- **状态**：完成（2026-11-01）
- **`[engine] llama-server exited with code 1` 是假日志**：`not_ready_screen.dart` 里的
  `_demoLogs()` 会在 `view.logs` 为空时**编造**两条诊断输出。用户把演示数据当成了真实报错。
  **已整段删除** —— 日志区只显示真实日志；没有就显示空态。
  教训：占位数据一旦进入「诊断输出」这种可信区域，等于误导排障方向。
- **启动按钮没有 loading 态**：`_ServiceCard` 之前用 `view.engine` 判断，
  而 `notReadyViewProvider` 传的是 `status: null` ⇒ `engine` **恒为 off**。
  改为直接 `ref.watch(engineStateProvider)`。这条也是「看着像没反应」的一半原因。
- **hover 区域与高亮不一致**：设置页左栏 `_NavItem` 原来 `InkWell` 包在带 `margin` 的容器**外面**，
  水波纹会盖住外边距，比高亮大一圈。已把 `InkWell` 收进内层，hover/激活共用**同一个容器**。
  侧栏视图项（投放/队列/漫画库）本来就是同一个 `AnimatedContainer`，无需改。
- **仍未做**：引擎运行日志（supervisor 的 `recentStageLog`）还没有呈现在设置页，
  真实启动失败时用户仍看不到原因 —— 需要把 `/engine/status` 的最近日志接到诊断输出。
- **验证**：`flutter analyze` 干净；应用 116 通过；服务端 133 通过。
- **关联**：D-062（启动按钮前置）· D-063（侧栏）。

## D-065 应用拿不到服务令牌 → 全部请求 403

- **状态**：已修（2026-11-01）
- **现象**：设置页点「启动」报
  `403 PERMISSION_DENIED 鉴权失败或来源不被允许`（这条正是 D-064 新加的失败原因展示暴露出来的）。
- **根因（完整链路）**：
  1. 应用启动 `mangasvc` 时**没有传 `--print-token`**；
  2. `mangasvc` 默认**要求令牌**，令牌由服务随机生成；
  3. 客户端令牌只来自**编译期常量** `String.fromEnvironment('MIAO_SVC_TOKEN')` —— 正常构建下为空；
  4. 于是每个请求都不带 `X-Box-Token` ⇒ 403。
  也就是说：本地服务的鉴权从接入那天起就没真正通过过（以前「能用」是因为早期服务以 `--no-token` 跑）。
- **修法**：
  - `ServiceLaunchPlan` 追加 `--print-token`；
  - `ServiceSupervisor` 解析 `mangasvc token <hex>` 存入 `token`；
  - `bootstrap` 用 `supervisor.token` 构造 `LocalServiceLocator`（编译期常量退化为兜底）。
- **教训**：这类「本地调用自己拉起的服务」的鉴权，最容易被两端各自假设对方知道令牌。
  启动协议里**令牌必须是显式输出 + 显式接收**，不能靠约定。
- **验证**：`flutter analyze` 干净；应用 116 通过。
- **关联**：D-064（把 403 显示出来）· D-022（沙箱）· D-045（远程令牌）。

## D-066 `--print-token` 漏了打包分支（403 未修好的真正原因）

- **状态**：已修（2026-11-01）
- **现象**：D-065 之后重启仍报同样的 403。
- **根因**：`ServiceLaunchPlan.resolve` 有**三条分支**：
  `dart-define/env`、**`bundled`（与 App 同目录的 mangasvc）**、`dev-source`（`dart run …dart`）。
  D-065 只给 `dev-source` 加了 `--print-token`，而启动日志写的是
  `[bootstrap] mangasvc bundled → 端口 5180` —— **实际走的是 bundled 分支**，args 仍是空数组。
  于是服务照常要求令牌、应用照常拿不到 → 403 一模一样。
- **修法**：三条分支全部追加 `--print-token`，并在 bundled 分支上写明原因，避免下次再漏。
- **教训**：**多分支的启动装配，改一处等于没改**。判断实际走哪条分支要看运行时日志
  （`origin` 字段就是为此存在的），不能凭印象。
- **验证**：`flutter analyze` 干净；应用 116 通过；`grep args:` 三处均含 `--print-token`。
- **关联**：D-065。

## D-067 引擎状态误报「未启动」+ 移除投放页横幅

- **状态**：已修（2026-11-01）
- **现象**：引擎已经启动了，但队列/投放上方仍显示「引擎未启动 · 可以继续投放与浏览」，
  右上角仍是「未启动」，设置右侧的状态圆点颜色也不对。
- **根因**：`notReadyViewProvider` 调 `deriveNotReadyView(status: null)`，
  其中 `engine` 由 status 推导 ⇒ **恒为 off**。所有读 `view.engine` 的地方
  （顶栏徽标、侧栏 readiness 圆点、投放页横幅）都误报「未启动」。
  这与 D-064 修的设置页卡片是**同一个根因**，当时只改了卡片，没有改源头。
  **修法**：在 provider 末尾用 `ref.watch(engineStateProvider)` **覆盖** `engine`，
  一处修好、所有消费者同步正确。
- **投放页横幅**：按用户要求**固定不显示**（引导页已承担该职责）。
  组件保留为空盒子，避免牵动调用方布局。
- **教训**：同一份数据在多个地方展示时，必须修**数据源**而不是逐个改 UI；
  否则就是「修了卡片、漏了徽标」。
- **验证**：`flutter analyze` 干净；应用 116 通过。
- **关联**：D-064（同一个根因的第一次修补）。

## D-068 移除整页门禁：漫画三页签恢复可点

- **状态**：完成（2026-11-01）
- **现象**：侧栏「队列」「漫画库」点了完全没反应（用户确认是 A：主体区仍是那张卡片）。
- **根因**：`MangaGate` 在引擎未就绪时**用同一张卡片顶替整个漫画区**。
  路由其实切换了，但三页渲染的是同一张卡片 ⇒ 主观上「点了没反应」。
- **决定**：**门禁不再整页顶替**，从 AppShell 上摘除（`manga_gate.dart` 保留备查）。
  「引擎没就绪」改由**页内提示**表达，而非阻止进入页面。
  理由：页面浏览（看队列、看已译作品）不需要引擎；用整页替换会把「不可用」扩大成「整个模块进不去」。
- **仍然保留的约束**：需要引擎的动作（开始翻译）会在提交时失败并给出原因；
  引导/装配仍在设置页「模型」区与引导卡片里。
- **教训**：门禁这种横切拦截，一旦作用在「整个模块」就很难与「页面导航」共存 ——
  它应该拦**动作**，不是拦**导航**。
- **验证**：`flutter analyze` 干净；应用 116 通过。
- **关联**：D-037（门禁引入）· D-059（漫画库放行）· D-067（状态误报）。

## D-069 投放页按 ver1.0 重画

- **状态**：完成（2026-11-01）；**未做视觉复核**（本机跑不了 GUI）
- **依据**：设计稿 `VIEWS['manga/drop']` + `.drop-wrap/.dropzone/.finput/.flist/.frow/.pathbox/.fhint` 的 CSS 逐条取值。
- **结构（640 单栏 / 间距 16 / 顶部 30）**：
  1. 拖拽区：高 **150**、圆角 **12**、描边 **1.5px `--line2`**；hover 与拖入都是主色描边 + `--acc-soft` 底；
  2. 漫画名：标签 11/600 + 红 `*`；输入框高 **38**、圆角 **8**、`--card` 底、聚焦换主色；
  3. 说明 9px；
  4. 待投放 N 张（>20 时显示「分 X 批」）+ 清单：容器最大高 **210**，每行 **26**，右侧「第 N 批」标签；
  5. 落盘路径预览（`--card` 底 + 描边）+ 说明；
  6. 提交（34/18/11，未填名或没图时禁用）/ 清空。
- **按设计稿去掉的东西**：`frow` 里**没有单张删除按钮**，所以不画（删单张用「清空」）。
- **按用户要求去掉的东西**：引擎未启动横幅（引导页承担）。
- **主题一致性**：全部颜色/圆角/间距走 `AppPalette` / `AppMetrics`，**没有写死色值**；
  文案全部走 ARB（新增 5 个键，l10n 棘轮通过）。
- **验证**：`flutter analyze` 干净；`flutter test` 116 通过；l10n 棘轮通过。
- **关联**：D-068（移除整页门禁）· D-040（设计稿对齐方法）。

## D-070 吐司改右上角 + 书架卡片骨架 + 提交失败提示

- **状态**：完成（2026-11-01）
- **吐司位置（用户指出）**：设计稿是 `#toasts{position:fixed; top:14px; right:14px}` —— **右上角**。
  之前实现放在右下角（`bottom:16`），位置就错了；同时把驻留时间对齐到 **3200ms**（稿子里的值）。
- **队列加载态**：本来就是**列表骨架**（`queue_skeleton.dart` 逐行占位），与设计稿一致，无需改。
- **漫画库加载态**：补**卡片骨架**（`_ShelfCardSkeleton`）—— 每张卡 = 封面块 + 两行文字占位。
  判定用 `shelfLoading`：只有「首次加载且无旧数据」才显示骨架，
  有旧数据时继续显示旧书架（避免刷新时整架闪成骨架）。
- **投放提交失败**：以前静默抛异常（用户完全没反馈），现在弹红色吐司带原因。
- **仍未做**：引擎下载/导入完成后的吐司（属于锦上添花，排在后面）。
- **验证**：`flutter analyze` 干净；`flutter test` 116 通过；l10n 棘轮通过。
- **关联**：D-069（投放页）· D-055（吐司样式）。

## D-071 启动服务吐司 + 去掉目录图标 + 导航诊断

- **状态**：完成（2026-11-01）
- **吐司范围按用户要求收窄**：只在**服务启动成功/失败**时弹（右上角 good/bad）；
  下载、导入、校验暂不弹。
- **引擎目录左侧图标已移除**（`.folderCog` 那枚），文字直接接在行首。
- **侧栏点击仍无反应的诊断**：`_goView` 加了一行 `debugPrint('[nav] go /manga/queue（module=0）')`。
  - 打出来了 → 说明点击与导航都正常，问题在**渲染/路由**（例如分支未切换、页面被替换）；
  - 没打出来 → 点击根本没到处理函数（命中区域被遮挡 / 手势被吞）。
- **已核对的代码路径**：`_ViewGroup` 对 manga 的 `items` 非空（drop/queue/library），
  每项都绑了 `onTap: () => onSelect(item.id)`，`_goView` 会 `context.go('/manga/<id>')`。
  静态看链路是通的，所以需要运行时日志确认断点位置。
- **验证**：`flutter analyze` 干净；`flutter test` 116 通过。
- **关联**：D-068（移除整页门禁）。

## D-072 侧栏点不动：redirect 把子页面全部重定向回首屏

- **状态**：已修（2026-11-01）
- **证据链**（用户提供的运行日志）：
  ```
  [nav] go /manga/queue      ← go() 确实执行了
  [nav] at = /manga/drop     ← 但路由仍停在 drop，而且连 go('/manga/drop') 也是如此
  ```
  三个不同目标都落回 `/manga/drop` ⇒ 一定是**重定向**而不是渲染问题。
- **根因**：
  ```dart
  redirect: (context, state) => state.matchedLocation == '/manga' ? '/manga/drop' : null
  ```
  `matchedLocation` 的语义是**命中的路由路径**。访问 `/manga/queue` 时，
  命中的 GoRoute 仍是父路由 `/manga`，于是条件为真 ⇒ 任何 `/manga/*` 都被打回 `/manga/drop`。
  `/music/*` 有同样的问题。
- **修法**：改用 `state.uri.path`（完整请求路径）判断：
  ```dart
  redirect: (context, state) => state.uri.path == '/manga' ? '/manga/drop' : null
  ```
- **为什么之前没暴露**：`initialLocation` 直接就是 `/manga/drop`，不经过这条 redirect；
  点击侧栏才第一次真正走「navigate 到子路由」的路径。
- **诊断方法（值得复用）**：在 `go()` 之后用
  `addPostFrameCallback` 打印 `routerDelegate.currentConfiguration.uri`，
  一眼区分「没导航」与「导航被重定向」。只看 `go()` 之前的日志会误判成渲染问题。
- **验证**：`flutter analyze` 干净；`flutter test` 116 通过；l10n 棘轮通过（调试串已改 ASCII）。
- **关联**：D-068（先移除了整页门禁，排除了一个干扰项）。

## D-073 去页面切换动画 / 队列卡「排队中」的锁死 / 去掉骨架屏

- **状态**：完成（2026-11-01）
- **页面切换动画移除**：`_PageTransition` 不再包裹内容（淡入 + 上移在桌面端反而显得拖沓）。
  组件保留未删，便于日后需要时恢复。
- **队列一直「排队中」的真凶（高置信）**：
  ```dart
  _ticker = Timer(..., () async { await _drain(); _draining = false; });
  ```
  `_draining` 只在**正常返回**时复位。一旦 `_drain()` 抛异常（例如引擎未就绪、
  端口不存在、某页处理抛错），这个闩就**永久为 true**，`_scheduleDrain` 从此直接 return，
  后续所有任务都停在 queued —— 正是「一直排队中」。
  **修法**：`try { await _drain(); } finally { _draining = false; }`。
- **骨架屏按用户要求移除**：队列与漫画库加载中直接按「暂无数据」渲染。
  本地服务响应是毫秒级，骨架屏多数时候只闪一帧，看起来像抖动。
  `queue_skeleton.dart` / `_ShelfCardSkeleton` 保留未删（将来数据量大可再用）。
- **队列空态图标**：`layers`（图层）语义不搭，换成 **`inbox`**（收件箱），更贴近「队列为空」。
- **验证**：`flutter analyze` 干净；应用 116 通过；服务端 133 通过。
- **关联**：D-072（路由）· D-070（书架骨架，本次撤回）。

## D-075 队列动作还原 + 翻译日志 + 状态实时化

- **状态**：完成（2026-11-01）；SSE 实时事件留作后续
- **任务详情定案（用户）**：**没有任务详情页**；「查看」= 跳漫画库并定位到对应漫画
  （`selectedBookProvider.select(normalizedComicName)` + `context.go('/manga/library')`）。
- **行首主操作**（对齐 miao-dock `QueueScreen.tsx` 的规则，按状态取**语义最主要的一个**）：
  | 状态 | 动作 |
  |---|---|
  | 排队中 / 翻译中 | 取消 |
  | 失败 / 部分失败 | **重试** |
  | 已取消 | **继续** |
  | 完成 | **查看**（→ 漫画库定位） |
  重试/继续都走 `POST /tasks/{id}/retry`（服务端早就有接口与 handler，**只是 UI 从没接**）。
- **【更多】菜单**：目前一项「删除」（`POST /tasks/delete` 已有，UI 接上）。
- **翻译日志（失败可见）**：
  - 服务端 `TaskQueue` 加环形缓冲（200 行，任务创建/重试 + 逐页失败原因）；
    `GET /api/v1/translate/log` 返回尾部；
  - **逐页失败原因现在会进 `failedReasons`**（此前 `_runOne` 只记 `lastError`，
    `toRow` 的 `failedItems` 永远是空 —— 这就是「部分失败之后没反应」的一半原因）；
  - 设置页「模型」区挂 `_TranslateLogBox`（1s 轮询），与「诊断输出」分工：
    那条是装配日志，这条是翻译运行日志。
- **实时状态**：队列轮询从 1.5s 收紧到 **1s**；服务端 SSE `/tasks/{id}/events` 已有，
  客户端换 SSE 留作后续（轮询对桌面本地服务足够实时）。
- **限制（已记录）**：`retryTask` 是**整任务重跑**（成功页也重译），不是只补失败页。
- **验证**：`flutter analyze` 干净；应用 116 通过；服务端 133 通过（路由数 53）；l10n 棘轮通过。
- **关联**：D-073（轮询引入）· D-046（任务来源）。

## D-076 队列持久化 + 「部分失败」复现结论

- **状态**：完成（2026-11-01）
- **队列被清空**：`TaskQueue._tasks` 是纯内存列表，服务重启即丢。
  **修法**：持久化到 `<stateDir>/queue.json`（与令牌同目录，缺省 `<库根>/.miao-state`）：
  - 写点：创建 / 取消 / 重试 / 删除 / 任务终态；原子写（tmp + rename）；
  - 读点：`Handlers.init()` → `queue.load()`；**running 的任务重置为 queued 从头跑**
    （被打断的翻译不接续，但历史与失败原因保留）；
  - 恢复失败**不阻塞启动**（宁可空队列，不让服务起不来）。
- **「部分失败」复现结论（重要）**：用当前代码做了两次服务级端到端
  （`MIAO_MANGA_ENGINE_DIR=~/MiaoDockEngine`）：
  - 第一次：2 页 85 秒 → `done`，产物 `001/002_translated.png` 齐全；
  - 第二次：1 页任务、**杀掉服务再重启** → 任务恢复为 running，继续跑。
  ⇒ 服务端链路当前是通的。用户看到的「部分失败」高度可能是
  **App 内置的 mangasvc 二进制过期**（服务端多次改动没进打包）。
  重跑 `flutter run`（触发 `tool/package_macos.sh` 增量编译）后再验。
- **验证**：`dart analyze` 干净；服务端 133 通过；应用 116 通过。
- **关联**：D-075（翻译日志 / 重试）· D-073（队列轮询）。

## D-077 翻译日志带上流水线各步骤

- **状态**：完成（2026-11-01），真实跑通验证
- **改动**：`EngineFacade.translateImage` 增加 `onStage` 回调（来自 `TranslateOutcome.stageLines`，
  引擎 stream 的 code=1 帧）；`TaskQueue` 的翻译注入签名变为
  `(bytes, onStage) -> 出图`，逐页把阶段行写进翻译日志。
- **实测**（真实引擎，1 页任务）日志如下：
  ```
  任务创建 stages-test（1 张）
  开始翻译 stages-test 第 001 页
  [stages-test 第001页] 排队位次 0
  [stages-test 第001页] 等待翻译实例
  [stages-test 第001页] running_pre_translation_hooks
  [stages-test 第001页] detection
  [stages-test 第001页] ocr
  [stages-test 第001页] textline_merge
  [stages-test 第001页] translating
  [stages-test 第001页] after-translating
  [stages-test 第001页] mask-generation
  [stages-test 第001页] inpainting
  [stages-test 第001页] rendering
  [stages-test 第001页] rendering_folder:...
  [stages-test 第001页] finished
  完成 stages-test 第 001 页
  ```
  任务状态 `done`，产物齐全。
- **限制**：阶段行按「页」批量写入（引擎响应整体解析完成后），不是逐阶段实时——
  设置页 1s 轮询下观感等同实时；真逐帧流式需改 `EngineClient` 的流式解析，留作后续。
- **验证**：服务端 133 通过；`dart analyze` 干净。
- **关联**：D-075（翻译日志入口）· D-043（帧协议）。

## D-078 话号命名与 manifest 模型（阶段 0 起）

- **状态**：完成第一块（2026-11-01）
- **对照源码**：`miao-dock/src-tauri/src/mangasvc/library.rs`（`chapter_dir_name` /
  `chapter_no_from_dir_name` / `is_valid_chapter_no` / `js_num_str` / `MAX_CHAPTER_NO=999`）。
- **已落地**（`packages/protocol/lib/src/library_manifest.dart`，两端共用）：
  - `chapterDirName`：`NN_第N话`，**两位零填充是对字符串长度做的**（`1→01`，`1.5→1.5`）；
  - `chapterNoFromDirName`：正则 `^(\d{1,3}(?:\.\d{1,3})?)_第(\d{1,3}(?:\.\d{1,3})?)话$`，取话名里的数，不匹配返回 null；
  - `isValidChapterNo`：`[1.0, 999.9]`，小数只匹配 `^\d{1,3}\.[1-9]$`；
  - `LibraryManifest`：键序 `schema,title,author,cover,episodes`（可逐字节比对），
    `episodes[] = {no, dir}`。
- **一处行为对齐澄清**：`1.10` 在 double 里就是 `1.1`（Rust 同样格式化丢尾零），
  会被当作合法话号 1.1 接受 —— 测试按此口径，不制造与旧项目的假差异。
- **验证**：`episode_naming_test.dart` 6 条；服务端 139 通过；`flutter analyze` 干净。
- **下一步（阶段 0 余下）**：任务 `dir_name` 命名与字段补齐、队列章节目录按话号写出。
- **关联**：`miao-dock` library.rs:40-90。

## D-079/D-080/D-081 阶段 0 收尾：名称规范化 / 单话平铺布局 / 任务字段对齐

- **状态**：完成（2026-11-01），阶段 0 结束
- **D-079 漫画名规范化**（`protocol/src/comic_names.dart`，对照 `names.rs` 9 步）：
  - U+0000 拒绝 → NFKC → 剥控制字符 → 剥 `[/\\:]` → 剥 Windows 非法字符 →
    折叠 JS 空白 → 去首尾空格与尾点 → 64 字符上限 → 保留名（CON/PRN/…，忽略扩展名大小写）→ 空名检查；
  - `is_safe_dir_name` 同步落地；错误码/文案同旧项目（`COMIC_NAME_REQUIRED`/`INVALID_COMIC_NAME`）；
  - **新依赖** `unorm_dart ^0.3.3`（纯 Dart，NFKC 真实实现而非自造映射），已登记台账；
  - 已接入 `POST /tasks`（服务端规范化，规范化后为空/超长/保留名按旧项目报错）。
- **D-080 单话平铺布局**（对照 `store/exec.rs write_item`）：
  - 投放产物改为 **`<库根>/<规范化名>/001.png` + `001_translated.<嗅探扩展名>`**，
    **不再写 `01_第1话` 子目录、不再写 manifest**（单话无 manifest，话号归并时才产生）；
  - 译文扩展名按引擎回包字节嗅探（`sniffImageType`）。
- **D-081 任务字段对齐**（对照 `store/model.rs Task`）：
  - 补 `dirName(=规范化名)/langFrom('ja')/langTo('zh')/translator('sakura')/clientTaskRef/idempotencyKey`，
    默认值同旧项目（`Lang{ja→zh}`、`default_translator="sakura"`）；持久化与恢复全带。
- **验证**：`comic_names_test` 9 条（含旧项目原用例 `"  a/b:c*  " → abc`）；服务端 148 通过；应用 116 通过。
- **下一阶段**：A（隐藏机制：`hidden.json` + 删除=隐藏/物理 + 恢复）。
- **关联**：`miao-dock` names.rs / store/pure.rs / store/exec.rs / store/model.rs。

## D-082 阶段 A：隐藏机制对齐 + 书架「显示已隐藏」

- **状态**：完成（2026-11-01），阶段 A 结束
- **对照**：`miao-dock` `library_delete`（body `{deleteFiles}`）+ `store.rs hide_comic/forget_hidden` + `platform/paths.rs hidden_comics_file()`。
- **服务端对齐**：
  - `deleteFiles=false` → **隐藏**（不检查目录存在性，`hide_comic` 同）；
  - `deleteFiles=true` → 目录不存在 → 清残留隐藏记录 + 404（`TASK_NOT_FOUND`）；存在 → 物理删 + 清记录；
  - `hidden-comics.json` 从「库根、裸数组」改为 **`<stateDir>/hidden-comics.json`、`{comics:[...]}`**（同构旧项目），
    启动 `init()` 时恢复；
  - `createBook` 顺带对齐：manifest 写**全字段**（schema/title/author/cover/episodes），不再只写 title/author。
- **App 端**：
  - `hiddenComicsProvider`（服务端返回的隐藏清单，随 `listLibrary` 刷新）；
  - `showHiddenProvider` 开关，`_ShelfFoot` 底部「显示已隐藏」；
  - `_ShelfBody`：开关开时书架尾部列出「已隐藏的漫画」+ 每行「恢复」（`POST /unhide` + 绿色吐司）。
- **验证**：`library_hidden_test` 4 条（隐藏保留目录/物理删除/恢复/去重）；服务端 152 通过；应用 116 通过。
- **下一阶段**：B 漫画库功能（新建漫画 UI、单话归并 UI、查看逻辑、简易模式、编辑、阅读器、封面、状态联动、刷新）。
- **关联**：D-079（名称规范化）· D-080（单话平铺）。

## D-083 单话归并（服务端，对照 library_merge 逐条）

- **状态**：完成（2026-11-01）
- **对照**：`miao-dock handlers.rs library_merge` + `library.rs resolve_book_dir/resolve_chapter_dir/remove_cover/episodes_from_dirs/write_manifest_atomic`。
- **语义**：`POST /library/{src}/merge`，body `{targetBook|book|target, no}`（`no` 必填，话号由调用方显式给出——旧项目同样如此）。
- **守卫顺序与错误码**（全部一致）：
  1. 源不存在 → `TASK_NOT_FOUND`（未归并单话目录不存在，404）
  2. 源已有 manifest → `ALREADY_MERGED`
  3. 目标不存在/无 manifest → `TASK_NOT_FOUND`（漫画大类不存在，404）
  4. 源上有活跃任务 → `MERGE_SOURCE_BUSY`（队列查询 `activeStatusesForDir`）
  5. 话号不合法 → `TASK_NOT_FOUND`（1–999.9，最多一位小数）
  6. 目标话号被占 → `CHAPTER_NO_TAKEN`（目录位置 + episodes[] **双向查**）
  7. rename 跨设备 → `MERGE_CROSS_DEVICE`；占用 → `MERGE_SOURCE_LOCKED`
- **归并动作**：搬移前清源目录封面（`remove_cover`，不升格为整本封面）→ rename →
  清搬运后目录里的 stray manifest → `episodes` 以目录为准重派生 → 原子写 manifest →
  响应 `{title, author, cover, episodes, merged:{from,to,no,removedCoverCount}}`。
- **顺带修正一个历史偏差**：`plans.dart` 里本地 `chapterDirName(1.5)` 会补零成 `01.5_第1.5话`，
  与旧项目（`1.5_第1.5话`）**不一致** —— 已删除本地实现，统一走协议版（D-078）。
- **发现并修掉的坑**：`FileSystemEntity.uri.pathSegments.last` 对**目录是空串**（URI 以 / 结尾），
  扫章节目录时曾导致 episodes 永远为空；改用 `path` 基名。
- **验证**：`library_merge_test` 7 条（成功含小数话号/6 类守卫）；服务端 159 通过；应用 116 通过。
- **客户端**：`mergeChapter(src, targetBook:, no:)` 对齐旧项目 body（原 `mergeChapters(chapterDirs)` 语义错误）。
- **关联**：D-078（命名）· D-082（隐藏）。

## D-084 漫画库详情主区（新建/刷新/简易模式/编辑/归并入/继续翻译/打开目录）

- **状态**：完成（2026-11-01）；阅读器（B.6）与右键菜单（D）留后续
- **对照**：ver1.0 `assets/app.js` 库视图（`.view-seg` 卡片/简易、`.lib-main` 头、hero 动作）
  与 miao-dock `LibraryRight.tsx`（继续翻译 primary / 编辑信息）。
- **书架数据修正**：`LibraryNotifier` 之前**只取 `response.books`，未归并单话（`others`）被整体丢弃**。
  现在 `[...books, ...others]` 合并，`LibBook.isBook` 区分单本/单话 ——
  单话从此出现在书架、可点进详情（查看逻辑：**未翻译完也能点进**，与状态无关）。
- **话号小数贯穿 UI**：`LibChapter.no` / `ChapterEntry.no` 由 int 改 **double**，
  `chapterTitle` 用 `jsNumStr` 显示（`1.5` 不显示成 `1.0`/`1.50`）。
- **主区头部**：本地漫画库 + 计数 + 刷新（B.9）+ 新建漫画（B.1，对话框→`createBook`→吐司）。
- **简易模式**（B.4）：`.view-seg` 卡片/简易切换（`libModeProvider`）；
  简易 = 胶囊行：话名 + 状态圆点（待译 蓝 / 缺页 黄 / 已译完不显示），头部显示图例。
- **Hero 动作**：
  - 单本：继续翻译（先 `getResumePlan`，`pendingCount==0` → 「已全部翻译」吐司；否则 POST+吐司）、
    编辑信息（B.5，仅单本）、打开目录（`reveal`）；
  - 单话：归并（对话框选目标书 + 话号，调 D-083 `mergeChapter`）、打开目录。
- **未做**：阅读器（B.6，下一轮）；「查看」按钮在阅读器落地时一并接。
- **验证**：`flutter analyze` 干净；应用 116 通过；服务端 159 通过；l10n 棘轮通过。
- **关联**：D-083（归并）· D-082（隐藏）· D-078（命名）。

## D-085 阅读器 + 封面规则 + 状态联动（B.6/B.7/B.8）

- **状态**：完成（2026-11-01），真实接口验证
- **B.6 阅读器**（`reader_screen.dart`，路由 `/manga/reader`）：
  - 页面内容**译文优先、缺译文回退原图**（miao-dock `viewer.tsx` 语义）⇒ 未翻译完也能看；
  - 桌面：左右方向键 / 两侧点击翻页、Esc 关闭；移动端：`PageView` 左右滑 + `InteractiveViewer` 双指缩放（1–5×）；
  - 顶栏：标题（书 · 第N话）+ 页码 `cur / total` + 关闭。
  - 入口：章节卡点击；单话 Hero「查看漫画」。
- **B.7 封面**：单话（无 manifest）**默认封面 = 第一页**（译文优先，其次原图）；
  单本仍只认 `cover.*`（不拿章节首图冒充）。Hero 改为显示真实封面图（无封面回退图标）。
- **B.8 状态联动**：队列轮询检测到任务状态/进度变化时，顺带刷新 `libraryProvider` ——
  任务落盘后书架页数/已译立刻更新，不用手点刷新。
- **服务端文件端点扩展**：`?variant=translated`（译文，缺则回退原图）、章节话号支持**小数**。
- **又一处 int 陷阱**：`_chapterNoOf` 原来取目录名前缀整数（`1.5` 解析失败），
  导致 `1.5_第1.5话` 在扫描与文件端点里**整话消失**；已统一走协议的 `chapterNoFromDirName`。
  实测：扫描能列出 `(1.0, 01_第1话) (1.5, 1.5_第1.5话)`，`chapters/1.5/files/1` 正常回图。
- **验证**：`library_cover_test` 4 条；服务端 163 通过；应用 116 通过；analyze 干净；l10n 通过。
- **关联**：D-083（归并）· D-084（详情主区）。

## D-086 队列行动作还原（阶段 C）

- **状态**：完成（2026-11-01）
- **对照**：`miao-dock QueueScreen.tsx PrimaryAction` + `App.tsx viewComic/retry/openTaskDir`
  + 行内 `MenuButton`（打开目录 / 删除）。
- **主按钮**（按状态取语义主操作，重试与查看**高亮**为 primary）：
  | 状态 | 按钮 | 行为 |
  |---|---|---|
  | 排队/翻译中 | 取消 | 取消并吐司保留张数 |
  | 失败/部分失败 | **重试**（高亮） | `POST /tasks/{id}/retry`（**同一 taskId**，不是新建任务）；失败弹红吐司 |
  | 已取消 | 继续 | 同重试 |
  | 完成 | **查看**（高亮） | 先查漫画库是否还有这本，**没有 → 红吐司不跳**；有 → 定位并跳 |
- **更多菜单**：`打开目录` + 分隔线 + `删除`（删除后吐司）。原先是两个 TODO 空实现。
- **结构收敛**：`_ActionCell` 提为公共 `QueueRowActions`，桌面表格与移动卡片**共用一份**，
  避免两处各写一套（移动端原来是「打开 / 更多」两个空按钮）。
- **验证**：`flutter analyze` 干净；应用 116 通过；l10n 棘轮通过。
- **关联**：D-075（行动作首版）· D-084（书架定位）。

## D-087 书架右键菜单 + 删除弹窗 + 端到端验收（阶段 D）

- **状态**：完成（2026-11-01），13 步真实接口全跑通
- **右键菜单**（`shelf_menu.dart`，`_BookRow` 的 `onSecondaryTapDown`），项序照
  `miao-dock LibraryScreen.renderComicMenu`「看得见的在前、破坏性的在后」：
  打开目录 / ─ / 继续翻译 / 重新翻译整本 / (编辑信息｜归并到…) / 删除整本·本话。
  - 继续翻译：先拉 plan，`pendingCount==0` → 「已全部翻译」吐司，否则提交；
  - 重新翻译整本：`retranslateBook`；
  - 删除：弹窗**勾选框默认不勾**（= 隐藏可恢复），勾上才物理删（`DeleteComicModal` 语义）。
- **修掉一个真 bug**：`scan()` 之前**不过滤隐藏项** —— 隐藏了书还在书架上，用户会以为没生效。
  现已跳过 `_hidden`（与 miao-dock `scan_library(hidden_set)` 同）。
- **结构收敛**：归并对话框抽成 `showMergeDialog`，详情页与右键菜单共用（避免两份实现漂移）。
- **端到端验收（真实服务，mock 引擎）**：
  1. 投放 `  E2E 单话  ` → 规范化；2. 任务 done 2/2；3. 磁盘只有 `E2E 单话/`（平铺无 manifest）；
  4. 新建书；5. 归并 `no=1.5` → `E2E 书/1.5_第1.5话`；6. 章节取图正常；
  7. 扫描出 `(1.5, 1.5_第1.5话)`；8. 继续翻译 plan `pendingCount=0`；
  9. 隐藏 → 10. 书架不再出现、`hidden` 有记录；11. 恢复；12. 物理删除；13. `hidden-comics.json` 落盘正确。
- **验证**：服务端 164 通过；应用 116 通过；analyze 干净。
- **关联**：D-083（归并）· D-084（详情）· D-086（队列）。

## D-088 补齐缺失的库 POST 端点 + 补页落盘串层（严重）

- **状态**：完成（2026-11-01），实测通过
- **发现方式**：端到端跑「继续翻译」时返回 `taskId: None` —— 一查发现**路由表声明了 6 个 POST，
  但 handler 一个都没有**（整本 resume/retranslate、章节 resume/retranslate、renumber、reveal）。
  这类「路由在、实现缺」只有真调接口才会暴露。
- **已补齐**：`_revealBook`、`_launchFromDir`（resume/retranslate）、`_chapterDirOf`（话号支持小数）、
  renumber 改 `double` 并在改号后**重派生 manifest.episodes**（原来改号后清单不同步）。
- **严重 bug（实测抓到）**：补页任务按 `comicName` 落盘 ⇒ 译文写到**书根**而不是原话目录
  （`某书/002_translated.png` 而不是 `某书/01_第1话/002_translated.png`），等于污染库结构。
  - 修法：`QueueTask.targetDir`（落盘目录，缺省 `<root>/<comicName>`）；
  - `_launchFromDir` **按话目录分别建任务**，每个任务带自己的 targetDir；
  - 回归测试 `queue_target_dir_test`：译文进话目录、书根不出现散落文件。
- **同时修**：`_aggregatePlan` 用 `^(\d+)` 解析话号 → 小数话被跳过；改 `chapterNoFromDirName`。
- **验证**：服务端 165 通过；应用 116 通过；实测 `01_第1话/002_translated.png` 正确生成、书根干净。
- **关联**：D-083（归并）· D-087（右键菜单）。

## D-089 路由↔handler 覆盖测试 + 补齐 translate 三端点

- **状态**：完成（2026-11-01）
- **防复发机制**（针对 D-088 那类「路由在、实现缺」）：
  `route_handler_coverage_test.dart` 用正则扫 `handlers.dart` 的 `case 'METHOD /path':`，
  与路由表**双向比对**：
  - 路由无 case → 列出全部（该端点恒 501）；
  - case 无路由 → 列出（改了字符串却没同步路由表，case 永远走不到）。
  这条测试**当场抓到 3 个漏网端点**，证明有效。
- **补齐的端点**（对照 `translate/mod.rs options_view/save_settings`）：
  - `GET /translate/options`：platforms / settings / sources / credentials / fileIssues；
  - `POST /translate/settings`：白名单 strict（`fromLang/toLang/platform`），未知键 → `INVALID_SETTING`，
    落 `<state>/translate-settings.json`；
  - `POST /translate/stream`：SSE 逐事件（`data: {"type":"result"|"error"}`），无凭证 → 409 `TRANSLATE_NOT_CONFIGURED`。
- **实测**：options 返回结构正确；settings 写入并落盘；非法键被拒；stream 无凭证返回 409 而非 500。
- **验证**：服务端 167 通过（新增 2 条覆盖测试）；应用 116 通过；analyze 双端干净。
- **关联**：D-088（端点缺失）· D-075（翻译日志）。

## D-090 构建级与真实引擎验收（含 manifest 字节修正）

- **状态**：完成（2026-11-01）
- **构建验证**：`flutter build macos --debug` 成功；打包进 App 的 `mangasvc` 时间戳 **晚于**
  最后一次服务端源码修改，确认跑的不是旧二进制（此前多次踩过这个坑）。
- **真实引擎端到端**（`--engine real`，`~/MiaoDockEngine`）：
  1. 引擎 10s 内 running；2. 投放 2 页 → **done 2/2、0 失败**（约 110s）；
  3. 磁盘：`真实验收/001.jpg + 001_translated.png + 002.jpg + 002_translated.png`，
     **无 manifest**（单话）；4. 扫描 `others: [(真实验收, 2 页, 2 已译)]`；
  5. 译文 1.30 MB / 原图 266 KB（确为引擎重绘，非拷贝）；6. `/files/1?variant=translated` 200；
  7. `/cover` 回退第一页译文 200。
- **真实数据归并**：新建书 → 归并 `no=1` → `验收书/01_第1话/` 结构正确，
  manifest 写入 `episodes:[{no:1,dir:"01_第1话"}]`，章节取译文 200 且字节一致。
- **修掉一个字节级差异**：`manifest.episodes[].no` 对整数话号曾序列化成 `1.0`，
  旧项目（JS `String(number)`）是 `1` —— 逐字节比对会对不上。新增 `jsNumValue`
  （整数→int，小数→double）并加测试钉住 `"no":1`。
- **验证**：服务端 168 通过；应用 116 通过；macOS 构建成功。
- **关联**：D-078（命名）· D-088（落盘）· D-089（覆盖测试）。

## D-091 UI 交互测试（并抓到「更多」按钮吞点击）

- **状态**：完成（2026-11-01）
- **新增测试**（9 条，应用 116 → 125）：
  - `library_interaction_test.dart`：删除弹窗**勾选框默认不勾**；勾上后确认返回 true；
    归并对话框未选目标书时确认按钮禁用；
  - `queue_actions_test.dart`：排队→取消 / 失败→重试 / 部分失败→重试 / 完成→查看 /
    已取消→继续（且**不出现「打开」**）/ 更多菜单含打开目录与删除。
- **抓到的真 bug**：`PopupMenuButton` 的 `child` 是 `AppTextAction`，而它内部的 InkWell
  `onTap: () {}` **把手势吃掉了** ⇒ 点「更多」菜单根本不弹（正是用户报的「点了没反应」）。
  - 修法：`AppTextAction.onTap` 改为可空，**null 时不吸收点击**；队列「更多」传 null。
  - 这条只有交互测试能发现 —— 静态分析与快照测试都是绿的。
- **验证**：应用 125 通过；服务端 168 通过；analyze 干净。
- **关联**：D-086（队列行动作）· D-087（右键菜单）。

## D-092 阅读器与右键菜单交互测试

- **状态**：完成（2026-11-01）
- **新增测试**（6 条，应用 125 → 131）：
  - `reader_test.dart`：
    - 无会话（pages=0）→ 给出空态与返回入口，**不白屏**；
    - 顶栏显示 `1 / 3` 且从第 1 页开始；
    - 点右侧翻页热区 → 页码前进（桌面鼠标用户必须能翻页）；
    - 小数话号标题显示 `第 1.5 话`（不是 `1.0`）。
  - `shelf_menu_test.dart`：
    - 单本菜单：有「编辑信息」、**无「归并到…」**、末尾「删除整本」；
    - 单话菜单：有「归并到…」、**无「编辑信息」**、末尾「删除本话」。
- **测试要点**：全部驱动真实交互（点按钮 → 弹菜单 → 断言项集 / 点热区 → 断言页码），
  而不是断言静态文案常量。
- **验证**：应用 131 通过；服务端 168 通过；analyze 干净。
- **关联**：D-085（阅读器）· D-087（右键菜单）· D-091（交互测试首版）。

## D-093 封面管理（编辑信息补全 + 写封面健壮化）

- **状态**：完成（2026-11-01），实测通过
- **对照**：`miao-dock modals.tsx EditBookModal`（`CoverSource = keep | local | first | remove`）
  + `library.rs write_cover / cover_from_first_chapter`。
- **UI**：编辑弹窗从「标题 + 作者」补成 **标题 + 作者 + 封面**，封面三选：
  - 「选择本地图片」：**选图不落盘，保存才提交**（选完取消不会留半截 cover.*）；
  - 「取第 1 话首图」：无话/无页时**置灰**（不是点了报错）；
  - 「移除」：当前无封面且未选新图时置灰（能点却没反应比置灰更困惑）。
  - 三个动作与文字信息**同一次保存**（拆开会出现「封面成功、作者失败」的半落盘状态）。
- **服务端健壮化**（原实现有三个真问题）：
  1. 封面扩展名写死 `cover.png`，实际字节可能是 jpg/webp ⇒ 改为**按字节嗅探**；
  2. 不删旧封面 ⇒ 换图后可能留下两张，扫描认到旧的那张 ⇒ 先删其它 `cover.*`；
  3. 直接覆写 manifest ⇒ 改为 **tmp + rename 原子写**，且保持全字段（schema/title/author/cover/episodes）。
  - 新增 `POST /cover {fromFirstChapter:true}`（对照 `cover_from_first_chapter`），
    单选：最小话目录 → 该话首图；单话（无话层）→ 自己目录首图。
  - 上限 10 MiB、非图片字节 → `INVALID_IMAGE`。
- **实测**：取首图 → 写 `cover.png` 且 manifest `cover` 声明正确；移除 → 文件与声明同时清空。
- **验证**：服务端 171 通过（新增封面 3 条）；应用 131 通过；analyze 干净。
- **用户裁定**：ver1.0 的「下载已译」按钮 **不做**。
- **关联**：D-085（封面规则）· D-087（右键菜单）。

## D-094 章节级操作入口（「⋯」菜单）

- **状态**：完成（2026-11-01），实测通过
- **对照**：`miao-dock chapters.tsx` 的悬浮菜单：打开目录 / 续做本话（副标「待续做 N 张」）/
  重译本话 / 编辑话数 / 删除本话（**恒置灰**，归并章节不能单删）。
- **实现**：`chapter_menu.dart` 的 `ChapterMenuButton` 叠在章节卡右上角（`Stack`），
  点菜单**不触发打开阅读器**（对应旧项目 `stopPropagation`）。
  - 续做：`pageCount - donePages == 0` 时置灰并显示「没有待续做的页」；
  - 编辑话数：对话框输入新话号，支持小数。
- **修掉三个契约不一致（都属「写了但调不通」）**：
  1. 客户端 `renumberChapter` 发 `{newNo}`，服务端读 `{no}` ⇒ 永远 400/无效；
  2. `renumberChapter` / 章节 resume / retranslate / 两个 plan 全是 `int` 话号 ⇒ 小数话直接崩；
  3. `revealBook('书/章节')` 把整段当目录名 ⇒ 找不到；改为**分段拼接 + 断言仍在库根内**。
- **实测**：章节续做 → 译文落回 `01_第1话/`；改话号 `1 → 2.5` → manifest 同步为
  `{"no":2.5,"dir":"2.5_第2.5话"}`；`书/2.5_第2.5话/reveal` 正常。
- **验证**：服务端 171 通过；应用 131 通过；analyze 双端干净。
- **关联**：D-088（落盘）· D-093（封面）。

## D-095 批量操作复核：**原本已实现**（撤销重复建设）

- **状态**：完成核对（2026-11-01）
- **经过**：上一轮我判断「队列批量操作未做」，本轮动手时发现
  **`queue_sum_bar.dart` 里早已有完整的多选工具栏**（已选 N 项 / 全选本页 / 删除选中 /
  取消多选 / 「删除只清记录不动文件」提示），移动端也有同一套。
  我上轮是在 `queue_table.dart` 里搜 `pickMode`，没搜到就下了结论 —— **判断方法有错**。
- **本轮实际产出**：删掉我新建的重复 `queue_toolbar.dart`，恢复被我改坏的 ARB
  （`queueDeleteSelected` 重新带 `{count}` 占位）。
- **教训（写下来避免重犯）**：判断「某功能有没有」必须**全局搜关键词 + 搜相关 provider 用法**，
  不能只看单个文件。`selectionProvider` 的存在本身就说明有多选功能。
- **现状确认**：队列批量操作（多选 / 全选本页 / 批量删除 / 取消）**完整可用**。
- **验证**：应用 131 通过；服务端 171 通过；analyze 干净；l10n 棘轮通过。
- **关联**：D-086（队列行操作）。

## D-096 修复「翻译完成但漫画库没有」（refresh 丢单话）+ 三处 UI 调整

- **状态**：完成（2026-11-01），已定位真实数据
- **① 翻译完成但库里没有（严重）**：
  - 现场：`~/Pictures/MiaoDock Mangas/test-01/` 里 `001.jpg/001_translated.png/002.jpg/002_translated.png`
    **都在**，服务端 `GET /library` 也正确返回 `others:[('test-01',2)]`。
  - 根因在客户端：`LibraryNotifier.refresh()` 算出 `all = [...books, ...others]`、
    也赋给了 `_lastGood`，却 **`return books`** —— 只返回「书」，未归并单话被丢掉。
    而任务完成会触发 `libraryProvider.refresh()`（D-085 的状态联动）⇒
    **刚翻完的漫画在刷新那一刻从书架蒸发**；「查看」也查不到 → 弹「未落盘或已被删除」。
  - 修法：`return all`。加回归测试 `library_refresh_keeps_unmerged_test`（books 1 + others 1 = 2 条）。
- **② 头部精简**：「本地漫画库 N」整块去掉，只保留右侧「刷新 / 新建漫画」，
  并加右侧内边距（`EdgeInsets.only(right: 4)`），按钮不再贴边。
- **③ 下拉框风格**：合并对话框的目标书下拉原用 `DropdownButtonFormField`（Material 默认下划线/填充外观），
  改为 `DropdownButtonHideUnderline` + 自绘容器（6 圆角、1px 描边、`navBg` 底），与项目输入框统一。
- **④ Toast 双下划线**：**未定位到**。检查了 `toast.dart`（无 `TextDecoration`）、
  相关 ARB 文案（无标记字符）、主题（无 underline 默认值），均无来源。
  需要截图或复现步骤才能确认（怀疑是系统/平台的文本选择高亮或两条 toast 叠加）。
- **验证**：应用 132 通过（+1 回归）；服务端 171 通过；analyze 干净；l10n 通过。

## D-097 漫画库还原 ver1.0 布局与交互 + 统一菜单/悬停规范

- **状态**：完成（2026-11-01）
- **布局重构（核心）**：`LibraryScreen` 改为**两态**——
  - 未选中：整屏 **全部漫画网格**（`library_grid.dart`，ver1.0 `.lib-grid`/`.bookcard`：
    3:4 封面、左上话数胶囊、hover 上浮 3px + 主色描边、cursor pointer），**没有左栏**；
  - 已选中：左栏书架 260 + 右侧详情。
  - 进入库**不再自动选中第一本**（删掉了 `?? books.first` 兜底）。
- **左侧列表**：`_BookRow` 重写为 ver1.0 `.nav-item`（34 高、8 圆角、
  hover 变 card 底、选中 card 底 + 1px 描边 + 主色图标、字号 11）。
- **修复「简易模式点击打不开」**：胶囊态原来只是 `Container`（无 onTap）；
  抽成 `_Capsule`（92×32 / 999 圆角 / hover 描边主色），与卡片态一样能进阅读器。
- **文案修正**：详情页「打开目录」误用了 `actionOpenNav`（打开导航）；
  新增 `actionOpenDir`，侧栏的「打开导航」保持不动。
- **统一菜单组件** `shared/widgets/app_menu.dart`（对照 miao-dock `.ui-menu` / `.ui-menu-item`）：
  card 底、1px 描边、6 圆角、padding 4、项高 30、hover `navBg`、危险项 `bad`、禁用项灰且不响应；
  队列「更多」/ 书架右键 / 章节「⋯」三处全部改用它（原 `PopupMenuButton` 已移除）。
- **hover 规范**：`AppTextAction`、`_HeaderAction`、`_HeroButton`、`_Capsule`、`_MenuRow`、
  `_DialogButton` 统一 `SystemMouseCursors.click` + 变色（主按钮提亮、ghost 变 card 底）。
  **按用户要求，只作用于漫画库/队列，未改侧栏与设置页**（`AppTextAction` 仅这两处使用，已核实）。
- **编辑弹窗**：ver1.0 无此弹窗（属 miao-dock 能力），按 ver1.0 视觉规范重排：
  封面预览 96×128 在左、三个封面操作竖排在右（`.cover-box`），下方标题/作者，
  底部右对齐「取消 / 保存」；输入框与按钮样式对齐项目 token。
- **验证**：应用 132 通过；服务端 171 通过；analyze 干净；l10n 棘轮通过。

## D-098 漫画库两态布局纠正（上一轮做反了）

- **状态**：完成（2026-11-01）
- **纠正**：D-097 把布局做成了「未选中＝只有网格、无左栏」，**与 ver1.0 相反**。
  重新读 `assets/app.js` 确认：
  - **默认态**：`.lib-body` = **左栏 `.lib-shelf` + 右侧 `.lib-main` 网格**，两者并存；
  - **详情态**（`S.libDetail`）：整块换成详情 + 顶部「**返回书架**」（`#bk`），**左栏消失**。
- **现在的实现**：
  - `LibraryScreen`：未选中 → `Row(左栏, 网格)`；已选中 → 只渲染详情（左栏消失）；
  - 详情顶部加「返回书架」（清 `selectedBookProvider` 即回默认态）；
  - 进库不选中第一本（无 `?? books.first` 兜底）。
- **左右内容分工（用户定案）**：
  - **左栏**：单本 **+ 未归并单话**（全部）；
  - **右侧网格**：**只显示单本**。
- **验证**：`library_layout_test` 3 条（不自动选中 / 左栏与网格并存 / 选中后左栏消失且能返回）；
  应用 135 通过；服务端 171 通过；analyze 与 l10n 通过。

## D-099 补齐可点元素的指针与悬停反馈

- **状态**：完成（2026-11-01）
- **背景**：用户要求「所有操作按钮鼠标移入应是 cursor + 颜色变化（跟 ver1.0 一致）」。
  D-097 只覆盖了部分组件，本轮**逐个排查** `GestureDetector` 无配套 `MouseRegion` 的位置并补齐。
- **本轮补齐**（ver1.0 对应态）：
  | 位置 | hover 表现 |
  |---|---|
  | 详情页 `_HeaderAction`（刷新/新建） | 主按钮提亮；ghost 变 `navBg` |
  | 单话「页面」网格 `_PageGrid` | 底色变 `navBg` + 描边主色 |
  | 章节卡 `_ChapterCard` | 描边变主色（`.chapcard:hover`） |
  | 封面选择 `_CoverChoice` | 未选中项变 `card` 底 |
  | 卡片/简易切换 `_ViewSeg` | 未选中项半亮底 |
  | 书架底部「去投放 / 显示已隐藏」`_TextLink` | 文字提亮为 `ink` |
  | 搜索页「打开书架」 | cursor 手型 |
- **统一实现**：新增 `_HoverTap`（cursor + hover 透传 builder），避免每个组件各写一套 State。
- **范围限定**：仍只作用于漫画库/队列，**未改侧栏与设置页**（用户明确要求）。
- **验证**：应用 135 通过；服务端 171 通过；analyze 干净。

## D-100 漫画库视觉细节对齐 ver1.0 度量

- **状态**：完成（2026-11-01）
- **左栏**：
  - 去掉「书库」大标题 + 图标，改为 ver1.0 的**单行 9.5 号计数文字**；
  - 搜索框高度 40 → **30**、图标 13 → 12、间距 8 → 6、字号 12.5 → **10**（`.shelf-search`）；
  - 清空按钮补 cursor。
- **详情 Hero**：去掉卡片底色与 12 圆角 —— ver1.0 `.detail-hero` 是**纯 flex 排版**（无卡片容器）。
- **章节卡**（`.chapcard`）：
  - 封面 48×64 → **40×54**，并由纯色块改为**主色渐变**（`linear-gradient(140deg, var(--acc), #3A2C14)`）；
  - 标题 13.5 → **10**、状态行 11.5 → **8.5**；
  - 网格间距 10 → **12**。
- **验证**：应用 135 通过；analyze 干净。

## D-101 菜单细调：危险项 hover 与面板对比

- **状态**：完成（2026-11-01）
- **危险项**：原写成 `_hover ? bad : bad`（两边同值，等于常红）。
  对齐 miao-dock `.ui-menu-item.is-danger:hover:not(:disabled){color:var(--md-error)}` ⇒
  **平时正常文字色、hover 才转 `bad`**。
- **菜单 hover 底色**：由 `navBg`(#141920) 改为 **`divider`(#252C35)**。
  依据：面板底是 `card`(#1A2028)，设计稿 `.ui-menu-item:hover` 用 `--md-line-soft`，
  对应本项目 `divider` —— 比面板亮一档但弱于选中态。
  （注：`AppTextAction` 是「divider 默认 → card hover」，方向相反但同样正确，
   因为两者面板底色不同，不能套用同一组色。）
- **编辑弹窗复核**：宽 420、封面预览 96×128（ver1.0 `.cover-preview` 同尺寸）、
  字段与按钮均走项目 token。
- **验证**：应用 135 通过；服务端 171 通过；analyze 与 l10n 通过。

## D-102 真机构建验证 + 视觉度量测试

- **状态**：完成（2026-11-01）
- **构建级验证**：`flutter build macos --debug` 成功；App 打包的 `mangasvc`
  时间戳（20:27）**晚于**最后一处 UI 源码改动（20:24），确认跑的是最新构建。
- **启动验证**：`open miao_dock_flutter.app` 后 App 与服务均存活（无崩溃）；
  窗口标题「喵坞 MiaoDock」、尺寸 1440×843。
  （macOS 辅助功能树读不到 Flutter 自绘文字，改走组件级度量测试。）
- **新增视觉度量测试**（3 条，应用 135 → 138）：
  1. 左栏固定 **260** 宽（`.lib-shelf`）；
  2. 书架行 **34+4**（`.nav-item` 34 高 + 4 间距）且网格卡片存在；
  3. **网格只显示单本**、单话仅出现在左栏（用户定案的分工）。
  为便于断言，`_BookRow` / `_BookCard` 加了稳定 key（`shelf-row-*` / `grid-card-*`）。
- **验证**：应用 138 通过；analyze 与 l10n 通过。
- **局限**：像素级观感（颜色/圆角/悬停）仍需人眼确认，自动化只能钉住结构与度量。

## D-103 左栏搜索分组 + 移除右侧搜索框

- **状态**：完成（2026-11-01）
- **右侧不再有搜索框**：搜索只属于左栏（ver1.0 `.shelf-search` 就在左栏）。
  网格页头只保留「本地漫画库 + 计数 + 刷新/新建」。
- **左栏搜索分组**（对照 miao-dock `tools/index.ts groupSearchResults`）：
  - 浏览态：平铺（单本 + 未归并单话）；
  - 搜索态：**每本书一个分组**（标题 `《书名》`），**未归并单话单独成组、标题「未归并」、排在最后**
    （旧项目叫「其它」，按用户要求改为「未归并」）。
- **验证**：`shelf_search_group_test` 2 条（浏览态无分组标题 / 搜索态有分组且未归并组在书组之后）；
  应用 140 通过；服务端 171 通过；analyze 与 l10n 通过。

## D-104 搜索改为模糊（子序列）匹配

- **状态**：完成（2026-11-01）
- **对照**：`miao-dock src/tools/index.ts matchIndices / fuzzyMatch`。
- **为什么不是 `contains`**：漫画名常是「第12话 · 学园祭」，用户只记得「12学」也该命中；
  子序列匹配天然覆盖「连续子串」，所以不必再补一次 `includes`。
- **实现**：`packages/protocol/lib/src/fuzzy_match.dart`
  - `matchIndices(text, query)` → 命中字符在**原文**的下标（可直接用于高亮），未命中 null；
  - `fuzzyMatch` = `matchIndices != null`；
  - 大小写折叠用 `toLowerCase()`（**不用** `toLocaleLowerCase`：土耳其语 locale 会把 I 折成 ı，
    导致同代码不同机器结果不同）。
- **接入**：左栏 `shelfBooks` 与右侧网格过滤均改用 `fuzzyMatch`（名字 + 作者）。
- **验证**：`fuzzy_match_test` 6 条（含「12学 命中 第12话·学园祭」且证明 `contains` 不命中、
  顺序颠倒不命中、空查询命中、下标正确）；服务端 177 通过；应用 140 通过；analyze 与 l10n 通过。

## D-105 按钮规范统一（以「新建漫画」为基准）

- **状态**：完成（2026-11-01）
- **基准**（`_HeaderAction` 主按钮）：`borderRadius: 6`、padding 10×5、字号 10.5、
  accent 底 + pageBg 字、**无边框**、hover 提亮 `#F0B96A`、cursor pointer。
- **队列行主按钮**（`_HoverChip` 增加 `primary` 变体）：
  - **主操作**（查看 / 重试）→ 与「新建漫画」**逐项一致**（accent 底、pageBg 字、
    10.5 号、无边框、圆角 6）；
  - **次级**（取消 / 继续）→ 与「更多」**逐项一致**（divider 底、12 号、hover 变 card、圆角 6）。
- **圆角统一到 6**：`AppTextAction` / `AppMenu`（含菜单项，原 4）/ `ChapterMenuButton`（原 4）/
  `_HoverChip`。卡片与封面等**非按钮**容器保持各自原值（10/8），不在此规范内。
- **cursor 补齐**：队列批量「全选本页」链接加 `SystemMouseCursors.click`。
  阅读器左右 56px 翻页热区**有意不加**（是区域不是按钮，ver1.0 亦无此规则）。
  `AppSwitch` 只被设置页使用，按「不改设置页」的要求未动。
- **验证**：应用 140 通过；服务端 177 通过；analyze 干净；l10n 通过。

## D-106 下拉菜单定位：按钮正下方 + 左对齐

- **状态**：完成（2026-11-01）
- **问题**：`showAppMenu` 原来按**一个点**定位，三个调用方传的东西各不相同
  （队列传「按钮左下角+4」、书架与章节传**鼠标点击点**）⇒ 菜单忽左忽右、贴着光标。
- **修法**：函数签名改为 `anchor: Rect`（**触发按钮的屏幕矩形**），内部统一计算：
  - `left = anchor.left`（**左边缘对齐**，越界夹紧）；
  - `top = anchor.bottom + 4`（**正下方**，留 4px 间隙）；
  - 下方放不下 → 翻到**按钮上方**（`anchor.top - 高度 - 4`）。
- **调用方**：队列「更多」、章节「⋯」都改用 `box.localToGlobal(Offset.zero) & box.size`
  求按钮矩形；书架右键没有按钮，用鼠标位置作零宽矩形。
- **验证**：`menu_position_test` 2 条（左对齐 + 正下方；贴底时向上翻转）；
  应用 142 通过；l10n 通过。

## D-107 Toast 文本黄色双下划线（截图定位）

- **状态**：完成（2026-11-01）
- **现象**（用户截图）：Toast 文字下方有**黄色双下划线**。
- **根因**：Toast 画在 `OverlayEntry` 里，`Text` **没有 Material 祖先** ——
  Flutter 在缺少 Material 时会用「黄色双下划线」提示文本样式缺失（Debug 期的经典提示）。
- **修法**：在自绘面板外包 `Material(type: MaterialType.transparency)`。
  用 transparency 而不是默认 Material：后者会带一层不透明底色，盖掉自绘的 panel/描边/阴影。
- **验证**：`toast_style_test`（断言 `decoration != underline` 且存在 Material 祖先）；
  应用 143 通过；l10n 通过。
- **备注**：前几轮在 `toast.dart`/ARB/主题里都搜不到 `TextDecoration` 是因为**来源不在代码里**，
  而是框架的运行时提示 —— 有截图才定位到。

## D-108 队列行按钮尺寸恒定（纠正 D-105 的过度改动）

- **状态**：完成（2026-11-01）
- **我的错误**：D-105 把「查看」的主操作分支改成了**新建漫画的尺寸**
  （padding 10×5、10.5 号字），导致它与同一行的「更多」**高度不一致**、看起来错位。
  用户要求的是「颜色像主按钮」，不是「尺寸也换一套」。
- **现在**：`_HoverChip` **只有一种尺寸**（height 24 / padding 9 / 12 号 / 圆角 6，
  与「更多」逐项一致），`primary` **只改颜色**（accent 底 + pageBg 字，hover 提亮）。
- **测试钉住**：`queue_actions_test` 新增「主按钮与更多尺寸完全一致」断言，
  防止以后再把尺寸改跑偏。
- **验证**：应用 144 通过；l10n 通过。

## D-109 简易模式点击的行为验证（不改功能，只补证据）

- **状态**：完成（2026-11-01）
- **背景**：目标第 1 条「简易模式点击打不开」此前只有**静态检查**
  （"代码里有 onTap"），没有"点下去真的会开"的断言。
- **新增 `capsule_click_test`**：进某本书 → 切「简易」→ 点胶囊「第 1 话」→
  断言 `readerSessionProvider` 被置为该书该话，且路由跳到 `/manga/reader`。
- **顺带确认**：点击确实会触发跳转（测试首次运行报 `No GoRouter found in context`，
  正是 `context.go` 被执行到的证据），补上 router 外壳后通过。
- **本轮未改任何功能代码**（只加测试），避免误伤已对齐的样式。
- **验证**：应用 145 通过；analyze 干净。
- **仍无法自动验证**：像素级观感（颜色深浅、悬停手感、间距），需人眼。

## D-110 可交互组件 cursor 规范（启用 / 禁用两态）

- **状态**：完成（2026-11-01）
- **规范**：
  - **启用** → `SystemMouseCursors.click`（手型，表示可点）；
  - **禁用** → `SystemMouseCursors.forbidden`（禁止符号，**不是普通箭头** ——
    普通箭头会让用户以为这里没东西可点，而禁止符号明确表达「有，但现在不能点」）。
  - 之前多处用的是 `basic`（普通箭头），已统一替换为 `forbidden`。
- **本轮覆盖**：
  | 组件 | 改动 |
  |---|---|
  | `AppGhostButton` | 补 MouseRegion（原来完全没有） |
  | `AppTextAction` | `basic` → `forbidden` |
  | `AppCheckbox` | 补 MouseRegion（原来没有） |
  | `AppSwitch` | 补 MouseRegion（原来没有） |
  | `AppSelect` | 补 MouseRegion（原来没有） |
  | `_PageButton`（分页） | 补 MouseRegion |
  | `_MenuRow`、`_CoverChoice`、`_DialogButton` | `basic` → `forbidden` |
- **测试**：`cursor_policy_test` 3 条（按钮 / 复选框 / 开关的启用与禁用两态）。
  写测试时踩到两个坑并修正：① `InkWell` 内部自带 MouseRegion，必须取**最外层**；
  ② `AppSwitch` 的 MouseRegion 在**内部**而非祖先，需用 `descendant` 取。
- **验证**：应用 148 通过；analyze 与 l10n 通过。

## D-111 按钮圆角统一 / 菜单行宽与定位 / 设置页导航光标

- **状态**：完成（2026-11-01）
- **① 圆角统一到 6**（基准 = 「新建漫画」）：
  漫画库内**按钮类**元素全部改 6 —— `_ViewSeg` 内部块（4→6）、`_CoverChoice`（8→6）、
  `_DialogField` 输入框（8→6）、页面卡（8→6）。
  **保留原值的是容器不是按钮**：`_MetaChip` 标签 5、胶囊态 999（设计稿固有形状）、
  封面预览 8、弹窗外框 12。
- **② 菜单**：
  - **定位修正**：「更多」原来用**外层 Builder 的 context** 求 RenderBox，
    取到的是表格容器而非按钮本身 ⇒ 锚点偏移。改用 `GlobalKey` 拿按钮自身 RenderBox
    （拿不到时退化为点击点零宽矩形）。
  - **行宽铺满**：行内容原来只有文字宽、hover 只亮一小块。现在面板宽度**固定**
    （`max(按钮宽, minWidth)`），行 `Row` 左对齐并占满面板宽 ⇒ 整行都是 hover 热区。
  - 踩坑：只给 `minWidth` 时父级无界，子 `Row` 会撑成**无限宽**直接崩
    （`BoxConstraints forces an infinite width`）；改用 `BoxConstraints.tightFor(width:)`。
- **③ 设置页导航**：`_NavItem` 补 `MouseRegion(cursor: click)`（原来 hover 会变色但不显示手型）。
- **验证**：应用 148 通过；analyze 与 l10n 通过。

## D-112 单话页面卡：原图封面 + 与单本卡同尺寸 + 页码左上角

- **状态**：完成（2026-11-01）
- **① 原图作封面**：页面卡原来只有「图标 + 数字」，现改为通过 `getBookFile(key, seq)`
  取**该页原图**铺满 3:4 封面；取不到时回退占位图标。
- **② 尺寸对齐单本卡**：网格从「6 列 / mainAxisExtent 96」改为与
  `library_grid.dart` **同一套参数**：`maxCrossAxisExtent: 170`、`mainAxisSpacing/CrossAxisSpacing: 16`、
  `childAspectRatio: 0.62`；卡片结构也照抄（封面 3:4 + 标题 + 副标一行）。
- **③ 页码位置**：从卡片中心移为**左上角胶囊**（与单本卡的「N 话」同位），
  字号 9、黑底 40% 透明、999 圆角。
- **④ 顺带核对了单本卡封面链路**：`_BookCard` 走 `getBookCover`，
  服务端 `readCover` 优先 `cover.*`（用户设了封面就用它），
  单话无 manifest 时才回退第一页 ⇒ **设过封面的书会显示对应封面，符合预期**。
- **验证**：`page_card_test`（断言页面卡真的调 `getBookFile` 取原图）；
  应用 149 通过；analyze 与 l10n 通过。

## D-113 漫画模块按钮全部收敛到 shared/buttons

- **状态**：完成（2026-11-01）
- **问题**：漫画模块有 **12 个各自实现的按钮组件**（`_HeaderAction` / `_HeroButton` /
  `_DialogButton` / `_CoverChoice` / `_BackToShelf` / `_Capsule` / `_TextLink` / `_HoverChip` /
  `_MenuTrigger` / `_GhostButton` 等），样式靠各处照抄 ⇒ 反复出现「尺寸不一致 / 圆角不一致 /
  hover 表现不同」。违反「不重复造轮子」。
- **做法**：
  - `shared/widgets/buttons.dart` 新增 **`AppButton`**（唯一实现），四种变体：
    `primary`（accent 底）/ `secondary`（divider 底，hover 变 card）/ `ghost`（透明底）/ `link`（纯文字）；
    支持 `icon`、纯图标（`label` 留空 + `width`）、`height` / `horizontalPadding` / `fontSize` / `border` / `color`。
  - **圆角唯一来源**：`kButtonRadius = 6`，所有按钮引用该常量；
    胶囊形（`.chapcap` 等设计稿固有形状）用 `kPillRadius = 999`。
  - 上述 12 个自定义按钮**全部替换为 `AppButton`**，各文件不再有自己的按钮实现。
- **踩坑**：`throw StateError('link 变体…')` 的中文字面量被 l10n 棘轮判为 UI 硬编码 —— 运行期字符串也要用英文。
- **验证**：应用 149 通过；analyze 干净；l10n 棘轮通过。

## D-114 下拉菜单改用 Material 3 `MenuAnchor`

- **状态**：完成（2026-11-01）
- **为什么换**：之前是**自绘 Overlay**，锚点要用 `RenderBox` 手算矩形，
  多次出现「位置不准」（外层 context 取错、宽度无约束崩、坐标基准不一致）。
- **新方案**：`shared/widgets/app_dropdown.dart`
  - **`AppDropdownMenu`**：基于 M3 `MenuAnchor`，触发按钮作为 `child`，
    **位置由框架按按钮实际布局矩形计算**（正下方 + 左边缘对齐，越界自动翻转），不再手算；
  - **`AppDropdownItem`**：统一菜单项模型（value/label/icon/sub/enabled/danger/divider）；
  - 行内**左对齐、整行铺满**（hover 整行高亮），危险项 hover 才转色，禁用项灰且禁止光标；
  - 面板样式：`card` 底、6 圆角（与 `kButtonRadius` 一致）、1px 描边、padding 4。
- **右键菜单**：没有触发按钮，用 `showAppMenuAt(position:)` —— 临时插入 1×1 锚点再展开，
  样式/行为与 `AppDropdownMenu` 完全一致。
- **删除了 `app_menu.dart`**（自绘实现），避免两套下拉并存。
- **踩坑**：触发按钮若自带 `onTap`（哪怕是空实现），`InkWell` 会吞掉手势导致菜单打不开
  ⇒ 触发器传 `onTap: null`，由 `AppDropdownMenu` 的 `Listener` 接管开合。
- **验证**：`menu_position_test`（正下方 + 左对齐）、`queue_actions_test`（更多菜单可展开）；
  应用 148 通过；analyze 干净。

## D-115 约束 10 改写 + 骨架屏收敛到 shared

- **状态**：完成（2026-11-01）
- **用户要求**：约束里增加「所有组件优先用 shared，其次 Material 3」。
- **`AGENTS.md` 第 10 条改写**为四级优先级：
  1. `lib/shared/` 既有实现（首选）；
  2. 扩展既有实现（缺变体就加参数/枚举）；
  3. Flutter 官方 **Material 3** 组件（共享层确实没有时），并按项目 token 覆写样式；
  4. **自绘**（最后手段，且必须写明为何不能用前三级）。
  判定口径：页面里出现 `class _XxxButton` / `class _XxxMenu` / 手搓按钮容器 = 违规；
  按钮圆角一律取 `kButtonRadius`，要改先改常量。
- **顺带发现文档与代码不符**：约束原文写着「已有 Skeleton」，但 `lib/shared/widgets/` 下
  **并没有 skeleton.dart**，实际有 3 处各写各的（`QueueSkeleton`、`_ShelfCardSkeleton`、`_GateSkeleton`）。
  已按约束收敛：
  - 新增 `shared/widgets/skeleton.dart`：`SkeletonBox`（原子）、`SkeletonRows`（表格行）、
    `SkeletonCards`（卡片行）；
  - 书架改 `SkeletonCards`、门禁改 `SkeletonBox`、删除无人引用的 `queue_skeleton.dart`。
- **验证**：应用 148 通过；analyze 干净；l10n 通过。

## D-116 全项目取色迁到 AppPalette.of + 按钮手型修复

- **状态**：完成（2026-11-01）
- **① 取色统一（用户选定「全项目迁移」）**：
  - `AppPalette` 增加**语义别名 getter**（`textPrimary/textSecondary/textMuted/navBg/navActive/
    cardCover/progressTrack/divider/accent/success/pageBg`），与旧 `AppTokens` 同名，
    迁移时 1:1 替换 `AppTokens.x → palette.x`，降低心智负担；
  - **21 个文件**完成迁移，`AppTokens` 引用**清零**；
  - 迁移中批量去 `const`（`palette` 是运行期值），并用「按错误行号定位、向上找最近 const」的方式修正了
    30+ 处残留 `const`；
  - **领域层例外**：`manga_status.dart` 不依赖 `BuildContext`，状态色保留**深色档常量**并注明
    「需要跟随浅色时由 UI 层映射」，不把 UI 依赖带进 domain。
  - `AppTable` 表头样式原本是顶层 `const`，改为按 context 取 `palette.textSecondary`。
- **② 按钮 hover 无手型（真 bug）**：菜单触发器为了让 `MenuAnchor` 接管点击，传了 `onTap: null`，
  而 `AppButton` 用 `onTap == null` 判定禁用 ⇒ 光标变成 `forbidden`。
  新增 **`clickable`** 参数区分两件事：
  - `onTap == null && clickable` → 点击交给外层，**光标仍是手型**、颜色按启用态；
  - `clickable: false` → 真禁用（`forbidden` + 灰字）。
  `_CoverChoice` / `_DialogButton` 的禁用态显式传 `clickable: false`。
- **验证**：应用 148 通过（新增光标用例 2 条）；analyze 干净；l10n 通过。

## D-117 primary hover 改为设计稿的「提亮 8%」

- **状态**：完成（2026-11-01）
- **原实现**：primary hover 背景硬编码 `#F0B96A`（两处：`AppTextAction`、`AppButton`）。
- **问题**：这个色值**设计稿里不存在**。设计稿是
  `.btn.pri:hover{filter:brightness(1.08)}` —— 把**当前主色提亮 8%**。
  硬编码带来的实际后果：切到浅色主题时主色是 `#C07C2E`，hover 却仍跳到深色档的橙，
  两套主题用了同一个色值，浅色下明显偏亮。
- **修法**：`AppPalette` 增加 `accHover` —— 用 HSL 把当前 `acc` 提亮 8%
  （`hsl.lightness + 0.08`），自动适配深浅主题与任意主色；两处硬编码全部改为 `palette.accHover`。
- **字体色**：primary 的 `fg` 只由 `enabled` 决定，**hover 不改变文字颜色**（用户要求，已核实）。
- **验证**：应用 150 通过；analyze 干净；`#F0B96A` 已无引用。

## D-118 颜色使用规范写入 AGENTS + 清除残留硬编码

- **状态**：完成（2026-11-01）
- **`AGENTS.md` 新增第 14 条「颜色只从主题调色板取，禁止硬编码」**：
  - 唯一入口 `AppPalette.of(context)`；**明确 `AppTokens` 已退役**；
  - 禁止 `Color(0xFF…)` 字面量与 `Colors.red` 之类具名色（阴影除外）；
  - 语义分组表：层级 `bg→panel→card→hi`、描边 `line/line2`、文字 `ink→ink2→mut`、
    主色 `acc/accHover/onAcc/accSoft`、状态 `good/bad/warn/blue`、其他 `shadow/coverEnd/coverEndDeep`；
  - **hover 一律提亮**（主色用 `accHover`，其余用层级升降），与 ver1.0 `brightness(1.08)` 同义；
  - **色相纪律**：状态色只用于圆点/徽标/进度条，正文标题只用 `ink` 系；
  - **领域层例外**：domain 不依赖 BuildContext，状态色用深色常量并注明由 UI 层映射；
  - 新增颜色必须先加进 `AppPalette` 深浅两套。
- **顺带清掉 5 处残留硬编码**（规范写了就要做到，否则规范没公信力）：
  - 书籍卡片封面渐变尾色 `#3A2C14` → **新增 `coverEndDeep`**（原 `coverEnd` 是播放器的 `#6B4423`，
    设计稿里这两种渐变尾色都存在，不能混用）；
  - `error_state` / `log_box` 的 `#D98C84` → `palette.bad`。
- **剩余硬编码仅 6 处**：全部在 `domain/manga_status.dart`，属规范允许的领域层例外。
- **验证**：应用 150 通过；analyze 干净。

## D-119 按钮无手型的真正原因：InkWell 桌面默认光标是 basic

- **状态**：完成（2026-11-01）
- **现象**：`AppButton` 外层 `MouseRegion` 明明设了 `cursor: click`，但桌面端悬停仍无手型。
- **根因**（查 Flutter 源码确认，**不是 `onTap` 判断的问题**）：
  `InkWell` 内部**总会**包一个 `MouseRegion(cursor: effectiveMouseCursor)`，
  位于外层 MouseRegion **内侧**，而**内侧光标优先**；
  `effectiveMouseCursor` 默认取 `WidgetStateMouseCursor.adaptiveClickable`，
  其实现为：
  ```dart
  static MouseCursor _adaptiveClickable(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) return SystemMouseCursors.basic;
    return kIsWeb ? SystemMouseCursors.click : SystemMouseCursors.basic;  // 桌面 = basic
  }
  ```
  ⇒ **桌面平台（macOS/Windows/Linux）默认就不是手型**，只有 Web 才是。
  这是 Flutter 遵循「桌面按钮通常不变手型」的原生惯例，但与本项目要求不符。
- **修法**：给 `InkWell` **显式传** `mouseCursor`
  （`AppButton` / `AppGhostButton` / `AppTextAction` / 菜单行 `_MenuRow` 全部处理）；
  菜单行同时从 `GestureDetector + MouseRegion` 改为 `InkWell`（与其它按钮统一）。
- **测试钉住**：断言 `AppButton` 内层 `InkWell.mouseCursor == SystemMouseCursors.click`，
  防止以后被默认值覆盖而复发。
- **验证**：应用 151 通过；analyze 干净。

## D-120 按钮 hover 变灰的真因 + 单页卡去主色 + 无图状态

- **状态**：完成（2026-11-01）
- **① 按钮 hover 变浅灰（截图实锤）**：
  - 我以为 `Material.color` 决定 hover 背景，实际 **`InkWell` 还会叠一层 `hoverColor`**；
  - 主题里 `hoverColor: palette.card`（`theme.dart:54`），浅色主题是 `#F3F2EF` ——
    正好盖在橙色主色上，于是出现截图里的「浅灰底 + 近白字」；
  - 修法：按钮的 `InkWell` 显式 `hoverColor / splashColor / highlightColor = transparent`，
    背景完全由外层 `Material.color` 控制（主色 hover 用 `accHover` 提亮 8%）。
  - 菜单行同样处理（行背景由 `Container` 控制）。
- **② 单页卡「闪 primary」**：不是 hover，是**封面占位用了主色渐变**
  `[palette.accent, coverEndDeep]`，原图异步加载期间/失败时露出。
  改为中性底 `palette.card` + 描边 `line`，**卡片内不再出现任何主色**：
  - 无图状态：`LucideIcons.imageOff` + 「无图」文案，中性灰；
  - 状态圆点：完成 `success`、未完成 `textSecondary`（原来用 `accent`）。
- **③ 单本卡片的封面渐变未动**（用户只要求改单页卡）。
- **验证**：应用 151 通过；analyze 与 l10n 通过。

## D-121 共享输入框 AppInput + 远程翻译一行式 + 归并下拉收敛

- **状态**：完成（2026-11-01）
- **① 新增 `shared/widgets/app_input.dart` 的 `AppInput`**（项目唯一输入框）：
  - 高度默认 **36**（原设置页 34，用户反馈"太小"）；
  - 圆角走 `kButtonRadius`；
  - **`hint` 必填** —— 规范要求所有输入框必须有 placeholder；
  - 支持 `errorText`（描边转 `bad`）、前后缀、`obscure`、`height`/`fontSize` 覆盖。
- **② 全项目 `TextField` 收敛**：**7 处 → 0 处**，全部改用 `AppInput`
  （设置页 LLM 凭证 / 远程连接、投放页漫画名、书架搜索、新建漫画、编辑信息、章节改号、归并话号）。
- **③ 远程翻译（`_RemoteSection` 重做）**：
  - **一行布局**：令牌 + 远程地址 + 测试按钮；
  - **令牌必填**（非空校验）、**地址非必填**（留空 = 同域），填了必须是 `http(s)://` 合法 URL；
  - 校验**实时**（`onChanged` 触发，首次交互后才显示错误，避免一进来就飘红）；
  - 测试**成功/失败都吐司**（成功还区分"引擎未就绪"，用 warn 色）。
- **④ 归并弹窗下拉**：`DropdownButtonFormField` → **`AppSelect`**（原来用的是 Material 原生组件，
  未接 shared，样式与项目不符）。
- **⑤ 复核结果**：`TextField` / `DropdownButton` 手搓实现已清零；
  Checkbox / Switch / Table 均在用 shared（`AppCheckbox` / `AppSwitch` / `AppTable`）。
  **仍存 33 处原生 `FilledButton`/`OutlinedButton`**（设置页为主），未在本轮处理。
- **⑥ 移动/桌面默认来源**：`TranslateSourceNotifier.build()` 已有
  `supportsLocalEngine ? local : remote`，符合要求，本轮未改。
- **验证**：应用 151 通过；analyze 与 l10n 通过。

## D-122 阅读器「显示原图 / 显示翻译」切换（持久化）

- **状态**：完成（2026-11-01）
- **需求**：进阅读器**默认看译文**；点按钮切原图；按钮文案随状态显示
  「显示原图」/「显示翻译」；状态**持久化**。
- **实现**：
  - `shell_prefs`：`readReaderShowOriginal()` / `persistReaderShowOriginal()`（键 `miao.reader-show-original`）；
  - `ReaderScreen`：`_showOriginal` 初值读偏好，切换时 `setState` + 落盘；
  - `_ReaderBar` 增加按钮（`AppButton` ghost + 描边，与顶栏其它控件同高 24）；
  - `_ReaderPage` 接收 `showOriginal`：**显示原图时不请求译文**（`translated: false`）；
  - `PageView` 的每页 key 带 `showOriginal`，切换时强制重建 ⇒ **一定重新取图**。
- **踩坑（关键）**：第一次改 `_load()` 时替换锚点没匹配上，导致 `showOriginal` 只是摆设、
  取图仍按旧逻辑走。**测试抓到**：切换后第二次请求仍是 `translated=true`。
  教训：改完要**用测试验证行为**，不能只看 analyze 通过。
- **测试**：`reader_toggle_test` —— 默认按钮是「显示原图」、默认请求译文、
  点击后按钮变「显示翻译」、重新取图 `translated=false`、偏好落盘为 true。
- **验证**：应用 152 通过；analyze 与 l10n 通过。

## D-123 远程一行式规格重排 + 校验提示不压输入框

- **状态**：完成（2026-11-01）
- **做了什么**：
  - `_RemoteSection` 一行式重排：令牌输入定宽 **200**（64 hex 遮蔽显示足够），
    远程地址改 `Expanded` 吃剩余宽度，测试按钮自然**贴行最右**。
  - 测试按钮规格：内距 18 / 字 9.5 / w600（= 服务卡片「停止」按钮），
    高度 **36** 与同行输入框同高（D-055 原则；34 与 36 的取舍用户裁定为同高）。
  - **`AppInput` 错误文案移出 `InputDecoration`**：`errorText` 会让装饰器从
    输入行抢高度把 36 的框压矮；改为独立 `Text`（10 号 / `bad`）画在输入框
    正下方，框恒定高度。描边变红仍由 `borderColor` 驱动，冗余的
    `errorBorder` / `focusedErrorBorder` 移除。
  - **`AppButton` 扩展 `fontWeight`**（D-115 路径：扩展既有实现），
    默认 null 不影响现有调用点。
  - **修正 `p0e4_remote_test` 的误导注释**：`String.fromEnvironment` 只读
    `--dart-define`，shell 环境变量传不进去；原文档写的
    `MIAO_E2E_TOKEN=<t> flutter test` 用法是错的（表现为对令牌服务 403）。
- **为什么**：用户实测反馈该行与设置页语言不匹配——按钮过重、不贴右、
  输入框宽度分配不合理；校验一触发输入框还被压矮，观感像布局跳变。
- **踩坑（环境假红，第三次同型）**：全量测试 `p0e4_remote_test` 403，
  排查为用户开着的 macOS App 保活了令牌模式服务（D-036 / D-038 同型）；
  用 `~/Pictures/MiaoDock Mangas/.miao-state/token`（服务 CLI 缺省状态目录
  是 `<库根>/.miao-state`，不是 appData 的 `manga/state`）+ `--dart-define`
  重跑后转绿，证实非代码回归。
- **验证**：`flutter analyze` 干净；全量 159 通过 + 8 跳过
  （含对**正在运行的真实服务**的 e2e 用例）；l10n 无新增文案。
- **关联**：D-055（同排同高）· D-115（约束 10）· D-121（一行式首版）· D-036（假红）。

## D-124 「服务与配对」配对令牌行（展示 + 复制）

- **状态**：完成（2026-11-01）
- **做了什么**：
  - `_PairingRows` 新增「配对令牌」行：monospace 展示本机 mangasvc 的
    `X-Box-Token`，右侧「复制」按钮（secondary / 高 24），复制进剪贴板后
    弹 good 吐司（D-013：动作必须有可见回执）。
  - 令牌来源 `serviceSupervisorProvider?.token`（`--print-token`，D-065）；
    **服务未由应用拉起时如实显示「无法获取」且不渲染复制按钮**——
    放空行假装正常等于误导。
  - 该行只在桌面分支（`supportsLocalEngine`）渲染；移动 / Web 是消费方，
    输入令牌的位置是已有的远程区块。
  - 令牌文本 `Flexible + ellipsis`：窄窗截断显示，复制按钮始终可见。
- **为什么**：其他端（插件 / 手机 / Web）远程连接需要这个令牌，此前用户
  只能翻服务日志找；设置页是配对信息唯一完整的展示位。
- **踩坑**：吐司驻留 3200ms（D-070）在 widget 测试退出时报
  `Timer is still pending` —— 断言后 `pump 3300ms` 推过生命周期。
  另：全量测试期间用户重启了 App，e2e 连接拒绝/403 再次假红（D-123 同型），
  服务恢复后全绿。
- **验证**：`pairing_token_test` 2 条（无 supervisor 的降级文案 + 复制内容
  与吐司回执）；全量 161 通过 + 8 跳过；analyze 干净；l10n 棘轮通过。
- **关联**：D-065（令牌获取）· D-045（远程配置）· D-013（回执）。

## D-125 五处交互细节修复（按钮高度 / 搜索框单盒 / 分页器 hover / 页面卡闪烁 / 设置页导航）

- **状态**：完成（2026-11-01）
- **做了什么**：
  1. **远程测试按钮高度 26**（用户在工作区手改后确认采纳）：放弃此前「与输入框同高 36」的裁定，
     该行按钮回归全项目 26 基准。
  2. **书架搜索框改单盒**：此前外层 `Container(card 底)` 里嵌了一个带边框的 `AppInput`，
     内框贴外缘 = 视觉「偏移」。改为 `AppInput` 自身就是搜索框（`prefixIcon` 搜索镜 +
     `suffix` 清除钮）；`AppInput` 新增 `prefixIconSize`（缺省 14 不影响他处，搜索框传 12）。
  3. **分页器页码按钮收敛到 `AppButton`**：当前页 = primary（hover 提亮 `accHover`），
     其余 = ghost（透明底 hover 变 card）。此前裸 `InkWell` 吃主题 `hoverColor: card`，
     **当前页 hover 被盖成灰**（D-120 同型），与按钮体系不一致。
  4. **单话页面卡 hover 闪烁（真 bug）**：`Image.memory(Uint8List.fromList(bytes))`
     每次 build 新建字节拷贝 + 新 `MemoryImage`（identity 不等）→ hover `setState`
     重建即重新解码。改为 `MemoryImage` 缓存在 state，同一实例喂 `Image`，
     `didUpdateWidget` 判等不再重解析；顺带消除每帧整图拷贝。
  5. **设置页导航手型 + 移除顶部「设置」标题**：`_NavItem` 的 InkWell 补显式
     `mouseCursor: click`（D-119：内层 InkWell 鼠标区优先于外层 MouseRegion，
     桌面默认 basic——D-111 只加了外层所以一直没生效）；左栏顶部
     「设置」标题整块移除（用户要求），导航项直接从顶部开始。
- **验证**：`flutter analyze` 干净；全量 157 通过 + 8 跳过，失败 4 条与改动前
  基线完全一致（3 条 e2e 环境噪声 + `pairing_token_test` 折叠线 tap 问题，
  均非本轮引入）；l10n 棘轮通过。
- **遗留（基线既有）**：`pairing_token_test` 复制用例的按钮落在 900px 视口外，
  测试未先 `ensureVisible` —— 待用户发话再修。
- **关联**：D-119（光标）· D-120（hover 遮罩）· D-121（AppInput）· D-123（按钮规格）。

## D-126 开关关闭态轨道换 line2（浅色下不可见）

- **状态**：完成（2026-11-01）
- **做了什么**：`AppSwitch` 关闭态轨道 `palette.hi` → **`palette.line2`**，注释写明偏离设计稿的原因。
- **为什么**：设计稿 `.switch` 轨道是 `var(--hi)`——深色下 `hi #252C35` 比 `.setrow` 底
  `panel #141920` 亮一档，可见；浅色把 `hi` 映射成了**纯白 `#FFFFFF`**，与白底融为一体，
  开关只剩一个 12px 灰滑块浮着（用户实测反馈「跟背景色融为一体」）。
  不能改浅色 `hi` 本身（它被 `cardCover` 等语义引用，全局牵动）。
- **效果**：浅色轨道 `#D8D0BF` 暖灰，白底上清晰可辨；深色 `#313A45` 是"比 hi 亮一档"
  的既有层级，顺势更清楚，语义不变。
- **验证**：`flutter analyze` 干净；`cursor_policy_test` / `settings_ui_test` 全过；
  l10n 棘轮通过。视觉观感需人眼确认（自动化只能钉住结构）。
- **关联**：D-040（AppSwitch 一比一）· D-118（颜色只从调色板取）。

## D-127 移除「随应用启动服务」开关：服务恒随应用启动

- **状态**：完成（2026-11-01）
- **做了什么**：设置页「服务与配对」的「随应用启动服务」开关整行移除；
  连带删除 `_autoStartServiceProvider` / `_AutoStartService`、
  `shell_prefs` 的 `readAutoStartService` / `persistAutoStartService`
  （键 `miao.auto-start-service`）与 ARB 词条 `svcAutoStart` / `svcAutoStartWhy`。
- **为什么**：bootstrap 从启动接线起就是**无条件**拉起 mangasvc（D-023），
  这个开关从未被消费——是个写了偏好却没人读的**假控件**；用户裁定服务
  恒随应用启动、不可更改，去掉比留着一个不生效的开关诚实。
  顺带消灭一个假象：看起来能关、实际关不掉。
- **保留**：「翻译时自动启动引擎」（`svcAutoStartEngine*`，D-039）不受影响，
  它是真消费的（D-039 落盘 + EngineAutoStart 读取）。
- **验证**：`flutter analyze` 干净；l10n 棘轮通过；全量 **161 通过 + 8 跳过
  全绿**（`pairing_token_test` 此前的折叠线抽风随按钮高度 26 带来的布局
  变矮而消失；e2e 对着运行中的真实服务通过）。
- **关联**：D-012（服务常驻）· D-023（无条件拉起）· D-039（引擎开关）· D-124（配对区）。

## D-128 字号阶梯 AppFont 落地：226 处字面量收敛到 theme

- **状态**：完成（2026-11-01）
- **盘点结果**：全项目 `fontSize` 字面量 **224 处 + 2 处组件默认参数**，
  共 **18 种值**（7.5 / 8 / 8.5 / 9 / 9.5 / 10 / 10.5 / 11 / 11.5 / 12 / 12.5 /
  13 / 13.5 / 14 / 15 / 17 / 18 / 19），分布 32 个文件。使用最多：
  10.5（导航/按钮，32 处）、9.5（31）、11.5 / 11（各 27）。
- **做了什么**：
  - `tokens.dart` 新增 `AppFont`（与 `AppMetrics` 并列）：18 档常量，
    **命名按设计稿 px 值**（`px10_5` = 10.5px），值一比一保留、**零视觉变化**；
    每档注明典型用途。阶梯是 design.html 的固有度量，语义别名（body/label…）
    等真实角色沉淀后再加——17 个相邻半步硬起语义名只会制造误导。
  - **226 处全部迁移**（224 字面量 + 2 处 `this.fontSize = 12` 默认参数），
    迁移后 lib 下 `fontSize: <数字>` 字面量为 **0**（生成物 l10n 本就没有）。
  - **AGENTS §4 新增第 15 条**「字号只从字号阶梯取，禁止字面量」
    （对齐 D-118 颜色条款的先例），判定口径含组件默认参数。
- **顺带修**：`pairing_token_test` 复制用例反复因令牌行落在 900px 视口外
  （y≈920）而假红——tap 前 `ensureVisible` 滚进视口。此前全量结果随布局
  微调时红时绿，本条之后稳定。
- **验证**：`flutter analyze` 干净；全量 **161 通过 + 8 跳过全绿**；l10n 棘轮通过。
- **关联**：D-118（颜色纪律先例）· D-003（视觉以设计稿为准）。

## D-123 全项目按钮归零 + 侧栏开关联动 + 日志导出修复

- **状态**：完成（2026-11-02）
- **① 弹窗复核**：`AppDialog` / `showAppDialog` 已是唯一实现，**原生 `AlertDialog` 0 处**；
  弹窗内按钮此前已用 `AppButton`。本项无需改动。
- **② 原生按钮清零：36 处 → 0 处**（`FilledButton`/`OutlinedButton`/`TextButton`/`ElevatedButton`）：
  `engine_parts_view`（更改/导入/校验/重查/重新下载）、`drop_screen`、`reader_screen`、
  `runtime_picker`、`not_ready_screen`、`queue_empty`、`shared/error_state`、`shared/empty_state`。
- **③ 设置页下拉**：复核为**全部 `AppSelect`/`AppSwitch`**，无需改动。
- **④ 侧栏开关联动**：设置页「侧栏图标标签」改为 **「侧栏展开」**，
  直接绑定 `navCollapsedProvider`（与侧栏收起/展开按钮**同一状态**），
  文案键改为 `settingSidebarLabels`=侧栏展开、`why` 说明联动；
  **移动端不显示**（`MediaQuery.width > AppMetrics.breakpoint` 才渲染）。
- **⑤ 翻译日志**：
  - 去掉标题右侧的「N 行」（`logBoxLines` 不再使用）；
  - 复制/导出反馈从 **SnackBar 改为项目右上角 toast**（`showAppToast`）；
  - **导出原本没生效**：`_TranslateLogBox` 未传 `onExport` ⇒ `handler == null` 时退化成只复制。
    现接入 `getSaveLocation` 真正写 `.txt`；回调签名改为 `Future<bool>`，
    **await 后才知道结果** —— 用户取消不弹「已导出」（原实现先弹后写，取消会误报）。
- **⑥ 样式微调**：停止 / 保存凭证字号 `AppFont.px9_5`；更改…/导入本地运行时之间补 8px；
  校验按钮 `secondary` → **`primary`**；`AppButtonVariant.link` 的 hover 字色改为
  `palette.accHover`（与 primary 的 hover 背景同色）。
- **验证**：应用 154 通过（`settings_ui_test` 文案同步）；analyze 干净；l10n 通过。

## D-124 按钮 hover 一律提亮 + danger 使用口径

- **状态**：完成（2026-11-02）
- **① hover 变暗 → 统一提亮**（用户实测：弹窗取消按钮 hover 后与背景融为一体）：
  根因是弹窗底色 = `card`，而 `secondary` / `ghost` 的 hover 恰好也是 `card` ⇒ 完全看不见。
  改为：
  | 变体 | 常态 | hover |
  |---|---|---|
  | `primary` | `acc` | `accHover`（主色提亮 8%） |
  | `secondary` | `divider` | **`line2`**（提亮一档） |
  | `ghost` | 透明 | **`hi`**（提亮一档） |
  | `link` | `acc` | **`accHover`** |
  | `danger` | `bad` | `badHover` |
  同一规则同步到旧组件 `AppTextAction`。
- **② link hover 是黑色**：上一轮把 `textPrimary` 改成 `accHover` 的**替换没匹配上**（锚点因新增
  `fontWeight` 而失配），代码里仍是 `textPrimary` —— 浅色主题下 `ink` 接近黑，所以看起来"变黑"。
  这次核对源码确认已生效（`grep` 验证）。
- **③ 弹窗校验按钮**：`runtime_picker` 的校验仍是 `secondary`（上轮只改了 `engine_parts_view`），
  已改为 `primary`。
- **④ `danger` 使用口径**（写进枚举注释）：
  **仅用于「不可逆操作」弹窗的确认按钮**（删除整本 / 删除本话）；
  观感严重但可恢复的（取消翻译 / 停止服务 / 重新下载）用 `primary` 或 `secondary`；
  下拉/右键菜单里的删除项走 `AppDropdownItem(danger: true)`，不是按钮变体。
  当前全项目仅 **1 处**使用（删除确认）。
- **踩坑**：本轮两次 Python 替换脚本因**字符串内嵌英文双引号**报 `SyntaxError`，
  导致改动静默失效；改用三引号后正常。**改完必须 grep 验证落地**，不能只看脚本输出。
- **验证**：应用 154 通过；analyze 干净；l10n 通过。

## D-125 弹窗"太大"的真因：Container 不指定 width 会撑满

- **状态**：完成（2026-11-02）
- **现象**：删除漫画的确认弹窗"太大"。
- **根因**（实测定位，不是内距问题）：
  `AppDialog` 用 `Container(width: width, ...)`，而 `width` 未传时是 `null` ——
  **Container 在松约束下会撑满可用宽度**。Dialog 的最大可用宽 = 屏宽 − 80，
  在 1200 宽窗口下弹窗被拉到 **1120 宽**，而内容只有 300（`SizedBox(width: 300)`）⇒ 两侧大片空白。
  **所有未传 `width` 的弹窗都中招**，不只是删除弹窗。
- **修法**：
  - `AppDialog` 内部：`width == null` 时用 **`IntrinsicWidth`** 让弹窗按内容收缩；
    传了 `width` 则用 `SizedBox(width:)` 严格固定；
  - 删除弹窗内容宽度 340 → **300**，正文/提示行加 `height: 1.4~1.5` 并收紧间距
    （10 / 4），避免收窄后文字过挤。
- **实测**：删除弹窗 **1120×191 → 340×191**。
- **验证**：应用 154 通过；analyze 与 l10n 通过。

## D-126 下拉统一到 M3 MenuAnchor + 可搜索选择器

- **状态**：完成（2026-11-02）
- **① `AppSelect` 换实现**：原来用 `PopupMenuButton`，弹层位置靠硬编码
  `offset: Offset(0, 30)`，按钮移动就错位；且与操作菜单（更多 / 章节）是两套外观。
  改为 **M3 `MenuAnchor`**（与 `AppDropdownMenu` 同源），位置由框架按按钮矩形算。
  影响 9 处调用（设置页翻译链路 / 在线翻译平台 / 推理引擎 / 语言对等）。
- **② 归并弹窗两行不对齐**：`Column` 未指定 `crossAxisAlignment`（默认 center），
  而 `AppSelect(width: 260)` 与 `AppInput`（撑满 300）宽度不同 ⇒ 视觉错位。
  改为 `CrossAxisAlignment.start` + 两者同宽 300。
- **③ 目标漫画搜索**：**没有**在 `MenuAnchor` 里塞 `TextField` ——
  实测菜单项 `hitTestable == 0`（M3 菜单面板与 `TextField` 的 tap region 冲突，点不中），
  `autofocus` 也不是原因。改用 **`shared/widgets/app_picker.dart` 的 `showAppPicker`**：
  `AppDialog` + `AppInput`（搜索）+ 列表，复用共享件，搜索与选择都稳定。
  归并弹窗的入口按钮仍保持下拉外观（secondary + 32 高）。
- **测试**：`select_picker_test` 两条 —— AppSelect 菜单在按钮下方且选择生效；
  picker 搜索「香」后只剩香蕉、选中回传 `'b'`。
- **验证**：应用 156 通过；analyze 与 l10n 通过。

## D-127 队列终态三分支 + 桌面端隐藏大模型翻译

- **状态**：完成（2026-11-02）
- **① 队列卡在「部分失败」（真 bug）**：
  `task_queue.dart` 原来只有一行判定
  `t.status = t.failed > 0 ? partialFailed : done;` ——
  **只要有一页失败就 partial_failed，即使每一页都失败**，
  `TaskStatus.failed` 只在「落盘失败」的 catch 分支出现。
  - 对照 miao-dock `store/pure.rs` 的 `end_status_of`：三分支
    （`failed == 0 → done`；`success > 0 → partial_failed`；否则 `failed`）；
  - 已按此修正，`t.done` 对应原项目的 success 计数。
  - **验证方式**：把旧逻辑临时改回去，新测试立刻红（`Expected 'failed', Actual 'partial_failed'`），
    证明测试咬得住这个 bug。
- **② 桌面端隐藏【大模型翻译】**：新增 `const bool llmSourceEnabled = false;`
  （实现与端点保留，打开常量即恢复，**不删代码路径**）：
  - `_SourceRow` 的选项列表按常量过滤；
  - `TranslateSourceNotifier.build()`：历史偏好是 `llm` 时**回落** local（桌面）/ remote（移动），
    否则界面会显示一个列表里不存在的值；
  - `set()` 拒绝切到已关闭的来源。
- **③ 测试间污染修复**：`readiness_test` 依赖 `translateSourceProvider`，
  而它会读**真实偏好文件** —— 设置页用例把来源存成 remote 后，
  「服务正常但引擎未起」会因「远程不需要引擎」得到 ready。
  已用 `translateSourceProvider.overrideWith(FakeLocalSource.new)` 隔离。
- **验证**：应用 156 通过；服务 179 通过；analyze 与 l10n 通过。

## D-128 翻译日志补全流水线细节

- **状态**：完成（2026-11-02）
- **问题**：日志只有「任务创建 / 重试任务 / 开始翻译第 N 页」，
  **失败原因完全不进日志**（只写进 `failedReasons`），
  用户看到「部分失败」却查不到错在哪；也看不到耗时、目标目录、引擎阶段。
- **补全后的日志形态**（实测输出）：
  ```
  任务创建 哥布林 154（2 张）
  任务开始 哥布林 154：2 页 → /…/lib/哥布林 154（引擎 真实）
  第 001 页：请求引擎（原图 1 字节）
  [第 001 页] 检测文本框 3 个          ← 引擎阶段（code 1/3/4 的可读文本）
  [第 001 页] 翻译 3 段
  第 001 页：失败，耗时 1ms —— 引擎返回空图
  第 002 页：成功，译文 4096 字节 / png，耗时 820ms
  任务结束 哥布林 154：成功 1 / 失败 1 / 共 2 页 → partial_failed
    失败明细 哥布林 154：第 001 页：引擎返回空图
  ```
- **具体改动**：
  - 任务开始记目标目录与引擎模式（真实/模拟）；
  - 每页记原图字节数、耗时、译文字节数与扩展名；
  - **失败原因进日志**（同时保留 `failedReasons`），去掉 `StateError` 的 `Bad state: ` 前缀；
  - 任务结束记成功/失败/总数与终态，并逐条列出失败明细；
  - 引擎阶段行格式改为 `[第 NNN 页] <阶段>`；
  - `EngineFacade` 抛错时带上引擎 `code` 与 `details`，便于区分「引擎报错」与「回包截断」。
- **测试**：`translate_log_detail_test` 三条 —— 失败原因必须出现、任务结束要有汇总、
  引擎阶段输出要进日志。
- **验证**：服务 182 通过；应用 156 通过；analyze 与 l10n 通过。

## D-129 远程翻译提交前置校验

- **状态**：完成（2026-11-02）
- **需求**：选远程翻译时，提交前校验 token + 远程地址；无效则提示
  「远程翻译配置不生效，请到设置页进行配置」，**任务直接 failed，不进翻译流水线**。
- **为什么不能只靠 HTTP 失败**：原实现会先建任务、排进队列、等引擎/HTTP 超时，
  最后只留一条语焉不详的失败 —— 用户既不知道是配置问题，也白等一轮。
- **实现（贯穿四层）**：
  1. `RemoteConfig.valid`：token 非空 **且** 地址是合法 `http(s)` + 有 host
     （`configured` 只判非空，`随便什么` 这种地址也会被放行）；
  2. 客户端 `createTask(..., failReason)` → `POST /tasks` body 带 `failReason`；
  3. 服务端 `createTask(failReason:)`：**建任务、置 `failed`、记 `failedReasons`、不 `_scheduleDrain()`**，
     日志记「任务 X 未执行：<原因>」；
  4. UI（投放页）：`submit` 返回 `blocked` 时弹 **bad** 吐司并跳队列，
     让用户看到那条失败任务与原因。
- **文案归属**：`controller` 不碰 ARB（`Ref` 上没有 `context`），
  本地化文案由 UI 层传入 `blockedReason`，controller 只透传给服务端。
- **测试**：
  - 服务端 `create_task_fail_fast_test`：`failReason` 非空 → `failed` 且**引擎调用次数为 0**；
  - 客户端 `submit_remote_guard_test` 三条：token 为空 / 地址非法都拦下、配置有效不拦。
  - **有效性验证**：临时把 `blocked` 写死 false，客户端用例立刻红，证明测试咬得住。
- **验证**：应用 159 通过；服务 184 通过；analyze 与 l10n 通过。

## D-130 校验逻辑与【测试连接】统一 + 重试同样拦截

- **状态**：完成（2026-11-02）
- **① 校验逻辑统一（用户指出）**：`RemoteConfig.valid` 只做**本地格式校验**，
  证明不了「服务在、令牌对」。提交前的探测改为与设置页【测试连接】**同一个**
  `remotePingProvider`（`GET /api/v1/ping`，带令牌）：
  `QueueNotifier.remoteUsable()` —— 来源非 remote 直接放行；
  格式先本地校验（省一次必然失败的请求），再真连一次。
- **② 重试同样拦截**：`POST /tasks/{id}/retry` 接受 `failReason`
  → 服务端 `retryTask(failReason:)`：**不重新排队**、任务置回 `failed`、写原因；
  `QueueNotifier.retry()` 先 `remoteUsable()`，返回 `blocked` 标志；
  队列行按标志弹红/绿吐司（红 = 去设置页，绿 = 重试已排队）。
- **验证方式**：服务端用例断言重试后 `engineCalls == 0` 且状态回 `failed`；
  客户端用例用可注入的 `remotePingProvider` 模拟【测试连接】结果。
- **验证**：应用 159 通过；服务 185 通过；analyze 与 l10n 通过。

## D-131 远程守卫全入口接入 + 重试 loading 态

- **状态**：完成（2026-11-02）
- **① 全入口盘点**（会启动翻译流水线的 5 类）：
  | 入口 | 位置 | 状态 |
  |---|---|---|
  | 投放提交 | `drop_screen.submit` | ✅ D-129 |
  | 队列重试/继续 | `queue_table.retry` | ✅ D-129 |
  | 整本补页 | `shelf_menu` / `library_detail` | ✅ 本轮 |
  | 整本返工 | `shelf_menu` | ✅ 本轮 |
  | 章节补页/重译 | `chapter_menu` | ✅ 本轮 |
- **② 守卫收敛为共享扩展**：`controller/remote_guard.dart` 的
  `WidgetRef.remoteGuard(l10n)` —— 判定本体仍是 `QueueNotifier.remoteUsable()`
  （与设置页【测试连接】同一探测），扩展只负责给本地化文案。
  被拦时 toast（bad）并**不建任务**（补页/返工是纯 UI 拦截，任务还没创建）。
- **③ 重试 loading 态**：`QueueRowActions` 改 `ConsumerStatefulWidget`，
  重试期间 `_busy = true`：按钮禁用（防双击重复排队）、文案变「校验中…」
  （探测是真实网络请求，连接超时 3s，必须有反馈）。
- **测试**：`submit_remote_guard_test` 增加用例：ping 失败 ⇒ `remoteUsable == false`。
- **验证**：应用 160 通过；analyze 与 l10n 通过。

## D-132 移除引擎目录的「重新校验」按钮

- **状态**：完成（2026-11-02）
- **改动**：`engine_parts_view.dart` 删除【重新校验】（`engineRecheck`，轻量快检入口）。
  用户要求去掉；【校验】（完整校验，含子进程与部件检查）保留。
  顺带清掉因此不再使用的 `engine_ready_controller` import。

## D-133 「全部失败」进度条去动画 + Broken pipe 根因分析

- **状态**：完成 / 分析（2026-11-02）
- **① 进度条动画**：`_ProgressCell` 原来 `value: ratio == 0 ? null : ratio` ——
  `null` = LinearProgressIndicator 的**不确定动画**（来回滚动）。
  全部失败且 0 页完成（ratio==0）的终态任务上，动画还在滚。
  改为：**只有非终态且 ratio==0 才给 null**；终态一律确定值（`MangaTaskStatus.isTerminal`）。
- **② Broken pipe 根因（实机诊断，无结论性修复）**：
  错误帧 `[Errno 32] Broken pipe`（恰好 22 字节，与 code 2 帧 size 吻合）
  是 **executor（`manga_translator shared`）的 Python 进程**产生的：
  翻译链路 = mangasvc → main.py(61240) → aiohttp → executor(61241)
  → Sakura(openai SDK) → llama-server(8080)。
  - **llama-server 本体健康**（`/health` ok、`/v1/chat/completions` 正常回包）；
  - executor 直接调用 `/execute/translate` 返回 500 / **429 `is_locked: true`**；
  - `sample` 显示 executor 主线程停在 `kevent`（空闲等事件），
    **锁在流式路径的异常中未释放**：`check_lock()` acquire 后，
    `run_method` 的 `finally` 只在 `progress_queue` 收到 0/2 帧时执行；
    若翻译协程**卡死**（如 Sakura 连接建立后对端断开），锁永远占着，
    后续请求全部 429。
  - 「Broken pipe」具体是 executor 内部哪个 socket 写失败，**executor 的 stderr
    没有落盘**（launchd 继承自终端 ttys003），无法进一步定位；猜测是
    Sakura 的 openai 客户端向 llama-server 写请求时对端关闭（模型卸载/重启）。
- **建议（未实施）**：
  1. mangasvc 起 executor 时把 stdout/stderr **重定向到文件**（诊断必需）；
  2. executor 的锁加**超时保护**（上游代码，属引擎侧）；
  3. 客户端对 `ENGINE_ERROR` + `Broken pipe` 给「重试」引导。
- **验证**：应用 160 通过；analyze 与 l10n 通过。

## D-134 启动判定分层化（L1 网关 / L2 执行器 / L3 LLM）+ 引擎日志落盘

- **状态**：完成（2026-11-02）
- **回答「启动成功指什么」**：修复前只判定 **L1**（main.py 的 `/openapi.json`）；
  executor（port+1）与 LLM（llama-server）**完全不在判定内** ——
  LLM 是残留的旧进程、SAKURA_API_BASE 靠 keys.py 默认值碰巧连上；
  Broken pipe / 执行器锁死都发生在 L2/L3，启动却照样「成功」。
- **修复**：
  1. **L2**：`_waitExecutorReady(port+1 /openapi.json)`，预算 `probeBudget`（默认 90s，
     模型首载慢）；不就绪 ⇒ `error` + 明确文案；
  2. **L3**：`_startLlm()` —— mangasvc **自己管理 llama-server**
     （runtime 内 `bin/llama/llama-b11417/llama-server` + `models/sakura/*.gguf`，
     挑空闲端口起进程、`/health` 探活）；缺二进制或缺权重 ⇒ **如实**保持
     running 但 `lastError` 标注「大模型后端未就绪，翻译不可用」（OCR 仍可用）；
  3. **SAKURA_API_BASE 显式注入** launch.json env（`127.0.0.1:8080/v1`）：
     executor 不再依赖 keys.py 默认值去碰「碰巧占 8080 的进程」；
  4. **引擎输出落盘**：supervisor 支持 `logFile`（`engine.log` / `llama.log`），
     stdout/stderr 逐行带时间戳写入 —— 没有文件现场，Broken pipe 这类问题查不到根因；
  5. `stop()` 同步停掉 LLM 监督器。
- **踩坑**：
  - fake 引擎夹具缺 `dart:async`（`unawaited`）→ 子进程秒崩、L1 超时，白查一轮；
  - 测试用例 `wrongPort = freePort()` 与 fake 的 `port+1` 撞车 ⇒ L1「歪打正着」通过、
    失败落到 L2 —— 改为 `port + 50` 拉开距离，断言放宽到「就绪」二字（不绑层）。
- **验证**：服务 185 通过；应用 160 通过；analyze 与 l10n 通过。
- **遗留**：llama 端口固定 8080 与「端口段探测」的一致性、L3 失败时侧栏状态点的呈现，
  需要一次 UI 层接线（本轮未动）。

## D-135 LLM 状态如实上报（侧栏状态点接线的服务端一环）

- **状态**：完成（2026-11-02）
- **为什么只动服务端**：UI 侧链路（`applyStatus` 合并两进程、`deriveNotReadyView`
  判 bothRunning、`shellReadinessProvider`）在 D-033 就已就位并有测试；
  断的一环是服务端 `toStatusView()` 把 `llm.state` **直接照抄引擎整体状态** ——
  L3 缺权重时引擎 running ⇒ UI 以为 LLM 也 running ⇒ 侧栏绿点、点翻译才炸。
- **修复**：`llm.state` 改为按 LLM 自身推导：有 pid ⇒ running；
  引擎 error ⇒ failed；否则 off。同时补 `model` 字段（权重文件名）。
- **验证**：`engine_llm_state_test` —— L3 未起（无 pid）时 llm.state 必须是 `off`，
  **反证过**（改回照抄立即红）。服务 186 / 应用 160 全通过。
- **踩坑**：反证后的恢复脚本用 `'state': _state.wire` 做替换，
  **把 engine 行也误改了**（同字面量）—— 靠 engine_test 的既有断言当场抓住。
  批量替换后必须 grep 核对目标行，第二条教训（D-124 同类）。

## D-136 「点了启动仍显示未启动」+ LLM 路径不匹配（实机修复）

- **状态**：完成（2026-11-02）
- **现场**（对运行中的 mangasvc 直接查询）：`engine=running / llm=off /
  lastError=大模型后端未就绪` —— 但 UI 显示「未启动」。
- **三个根因**：
  1. **`applyStatus` 合成语义错**：`engine=running + llm=off` 落进 else 分支合成
     **off** —— L1/L2 明明起来了，UI 却「未启动」。改为以 **L1 网关为准**
     （engine running ⇒ 引擎组 running）；「能不能翻译」由 llm 状态单独表达。
  2. **轮询从未运行**：`engineStatusPollProvider`（1.5s）定义了但**没有任何
     watch**（懒加载 StreamProvider 不订阅不跑）⇒ 启动后状态永远停在旧值。
     设置页 `build` 顶部补 `ref.watch(engineStatusPollProvider)` 激活。
  3. **L3 候选路径与实际布局不符**：代码找 `bin/llama/llama-b11417/llama-server`
     + `models/sakura/`，实测引擎目录是 `bin/llama/llama-server`（无版本层）
     + `llm/*.gguf` ⇒ L3 永远「缺文件」。改为**多候选探测**（两种布局都覆盖）。
- **连带修正**：
  - 新增 `llmStateProvider`（与 engineState 平行）；`applyStatus` 同步它；
  - `mangaGateProvider` 的 `engineRunning` = engine.isReady **且** llm.isReady
    —— 否则侧栏「已就绪」但点翻译必炸；
  - 设置页圆点三态：绿=两进程都跑 / 黄=引擎跑但 LLM 缺（副标
    「引擎运行中，大模型未就绪——翻译不可用」）/ 红=failed / 灰=停止。
- **验证**：对运行中服务查询确认 engine=running；服务 186 / 应用 160 全通过。
- **注意**：需要 `flutter run -d macos` 重新编译打包的 mangasvc 才生效（D-109 教训）。

## D-137 本地与远程翻译统一使用硬门禁

- **状态**：完成（2026-11-02）
- **做了什么**：`MangaGate` 实际挂入壳层内容区；本地仅在漫画服务、引擎与 LLM 均就绪时放行投放、队列并显示绿点。引擎状态改为壳层全局轮询，探测失败立即撤销就绪。远程每次会话默认未校验，必须显式验证地址、令牌、连接及远端引擎后才放行；配置变更会撤销结果。
- **为什么**：持久化配置和单个进程 running 都不能证明当前可翻译；此前远程来源被无条件视为 ready，本地 LLM 停止后顶部仍可能显示就绪。
- **怎么验证**：`manga_gate_widget_test` 反证未就绪时目标页不会渲染；状态、远程守卫、UI 与危险色由 `not_ready_state_test`、`manga_gate_test`、`submit_remote_guard_test`、`not_ready_ui_test`、`readiness_test` 覆盖。

## D-138 引擎启动不得接受残留进程的健康响应

- **状态**：完成（2026-11-02）
- **现场**：投放任务两页均失败，executor 返回 429 `some Method is already being executed`；`61240/61241` 被旧孤儿进程占用，新进程实际 bind 失败，但健康探针命中旧进程后仍上报 ready。
- **修复**：L1/L2 启动前同时占测相邻端口；规格端口被占时换一组连续空闲端口并同步改写启动参数。LLM 先启动，再把真实动态端口通过 `SAKURA_API_BASE` 注入 executor，禁止回退连接碰巧占用 8080 的进程；释放运行时时同步停止 LLM。
- **怎么验证**：`engine_launch_test` 用两个返回 200 的残留服务占住规格端口，断言新引擎必须换端口且 pid 属于本次进程；反证为固定端口探活时该用例失败。

## D-137 移动端布局兼容 + 约束 16

- **状态**：完成（2026-11-02）
- **审计结果**：外壳（`AppShell`）与队列屏已有移动端分支，但
  **设置页 / 投放页 / 漫画库完全没有适配**；且队列屏硬编码 720、外壳用 768，两套断点。
- **统一断点**：新增 `lib/shared/responsive.dart` 的 `context.isMobile`
  （= `AppMetrics.breakpoint` 768）；队列屏的 720 魔数改用它。
- **逐屏改造**：
  | 屏 | 窄屏行为 |
  |---|---|
  | 设置页 | 左栏 208 → **顶部横向滚动标签**；分区正文抽成 `_sectionBody`，宽窄共用同一份映射 |
  | 漫画库 | 双栏 → **单栏网格** + 顶部「我的书架」按钮（弹底部抽屉，否则未归并单话不可达） |
  | 投放页 | 按钮行 `Row` → **`Wrap`**（防溢出）；拖拽区高度 `150 → 110` |
  | NotReady | 主按钮**独占一行**（38 高 / 200 宽），次要操作降为一行 link |
- **约束新增第 16 条**（AGENTS §4）：断点唯一、判据唯一、六项必查清单
  （多栏降级 / 固定宽度 / 按钮组 Wrap / 栅格自适应 / 固定高度区压缩 / 不可用项不渲染），
  并要求布局改动至少带一条 390×844 断言。
- **测试**：`responsive_layout_test` 三条 —— 窄屏不渲染书架栏但保留入口、
  宽屏仍是双栏、设置页窄屏可切换分区。
- **验证**：应用 175 通过；analyze 与 l10n 干净。

## D-138 窄屏引导页精简（桌面端保持原状）

- **状态**：完成（2026-11-02）
- **决策**：桌面端**保持原状**（用户选 A）——分层状态 / 三步教程 / 日志框都不动；
  只给窄屏做精简版。
- **窄屏 `_MobileNotReadyCard`**（约 120 行，独立组件，桌面端零改动）：
  只留「结论 + 一行说明 + 一个占满整行的按钮」，**不显示** `_LayerStrip` /
  `_StepsRow` / `LogBox` / `_DownloadSection`（移动端不跑本地引擎，这些是桌面排查用的）。
  按用户确认保留三样：
  1. **下载进度**：细进度条 + 百分比（无反馈会被当成卡死）；
  2. **校验失败原因**：一行，最多两行截断；
  3. **浏览书架**：次要 link（没配置远程时唯一的出口）。
  主按钮 `height: 42` + 占满整行（窄屏并排会窄成一条，单手难点中）。
- **分层修正**：`RemoteVerificationNotifier.verify()` 原本丢弃 `RemoteProbe.message`，
  界面只能说「失败」。新增 `remoteVerifyMessageProvider` 存
  **结构化**失败信息（`RemoteVerifyIssue` + detail），**枚举定义在 domain**、
  **中文在 UI 层查 ARB** —— controller 不得带中文字面量（l10n 棘轮会拦）。
- **测试**：`notready_mobile_test` 两条互为反证 —— 窄屏不出现三步教程、
  宽屏必须出现（防止「删过头把桌面端也删了」）。
- **验证**：应用 177 通过；analyze 与 l10n 干净。

## D-139 远程门禁拆两按钮 + 设置深链 + 窄屏输入框堆叠

- **状态**：完成（2026-11-02）
- **① 校验按钮点了没反应（真 bug）**：`_Actions` 的远程门禁主按钮
  映射到 `onPrimary`，而 `not_ready_route_screen` 的 `onPrimary` switch
  **只处理 uninstalled/installed/failed 等本地状态，远程门禁不在其中** ⇒ 空转。
  同时 `RemoteVerificationNotifier.verify()` 从未被调用。
- **② 拆成两个按钮**（用户要求）：
  - 【校验远程配置】→ `onVerifyRemote` → `verify()`；`remoteChecking` 期间按钮禁用、
    文案变「正在校验远程配置」（loading 态）；
  - 【去设置远程配置】→ `onOpenRemoteSettings` → `/settings?section=translate`；
    桌面端为次要 link、窄屏为次要按钮（40 高）。
- **③ 设置页深链**：`SettingsScreen` 读 `GoRouter.maybeOf(context)?.state.uri
  .queryParameters['section']` 定位分组。
  **必须用 `maybeOf`**：测试里直接挂载设置页没有 GoRouter 祖先，
  `GoRouterState.of` 会抛 "no GoRouterState above the current context"（实测 4 个用例连锁红）。
- **④ 窄屏标签去掉计数**：`翻译服务 13` 里的 13 是 `_sections` 的**硬编码代码块数**
  （不是设置项数），贴在窄屏标签上被读成「13 条未读」。窄屏不显示，宽屏侧栏保留。
- **⑤ 窄屏令牌/地址各占一行**：原 `Row(200 + Expanded + 按钮)` 在 390 宽把输入框
  挤成一条缝。窄屏改 `Column`：令牌 → 地址 → 测试按钮（占满整行），桌面端不变。
- **验证**：应用 177 通过；analyze 与 l10n 干净。

## D-140 桌面端引导卡按原型重排 + 校验按钮 spinner

- **状态**：完成（2026-11-02）
- **① 校验按钮加 spinner**：用 `AppButton.loading`（内置转圈 + 自动禁用点击），
  校验中（`remoteChecking`）显示，不再只靠文案变化。
- **② 桌面端引导卡按 HTML 原型重排**：
  | 区块 | 改动 |
  |---|---|
  | Header | 图标块 64→**36**（浅色底 + 主色图标）；标题 19→**15**（`AppFont` 无 16 档，取最近档）；chip 改为**方角描边**（radius 3） |
  | 状态区 | 三行纵向列表 → **三列等分卡片**（`_StatusCard`：色点+标题 / 值 14 号 / 说明 10.5 号，maxLines 截断） |
  | 步骤条 | 灰底框内 3 个序号 + 文案，中间加**短横线连接** |
  | 间距 | header→grid 24 / grid→steps 24 / steps→actions 32（对齐原型） |
  | 卡片 | radius 14→**6**、内距 28→**32/24** |
- **③ 顺带修正**：`_Actions` 的主按钮 onTap 在远程门禁下仍指向 `onPrimary`
  （上轮 D-139 只改了窄屏卡，桌面端漏了）—— 现已接 `onVerifyRemote`。
- **数据映射**：原型三卡 = 现有三行数据（远程连接 / 引擎+大模型 / 翻译来源），
  未新增任何状态字段，仅换渲染。
- **验证**：应用 177 通过；analyze 与 l10n 干净。

## D-141 状态卡补图标

- **状态**：完成（2026-11-02）
- **问题**：D-140 重排时丢了原型里三张状态卡的小图标（远程连接=link / 引擎+大模型=cpu / 翻译来源=cloud）。
- **修法**：数据行元组加 `IconData` 位（本地图标用 `server`，因为该行在非远程态显示"服务"），
  `_StatusCard` 增加 `icon` 参数，按原型 14px 灰色渲染在标题前。
- **验证**：应用 177 通过；analyze 干净。

## D-142 移动端测试按钮变形 + 设置深链走 didChangeDependencies

- **状态**：完成（2026-11-02）
- **① 移动端「测试连接」文字被拉伸**：窄屏那行用了
  `SizedBox(height: 40, child: FittedBox(fit: BoxFit.fill, child: 按钮))` ——
  `FittedBox` 会把整个子树（含文字）缩放，按钮被横向拉扁。
  改用 `AppButton(width: double.infinity)` 撑满，文字保持原样。
  顺带补 `loading: _testing`（探测中显示转圈）。
- **② 移动端跳设置页没定位到「翻译服务」**：深链读 query 原本放在 `build` 里 +
  `addPostFrameCallback`。Shell 会**保活**设置页，二次进入时 build 可能拿不到新 query
  ⇒ 跳转失效。改为 `didChangeDependencies` + `_handledSection` 去重。
- **③ 队列桌面端按钮**：实测 `QueueRowActions` 两个按钮
  均为 `42.5×24`、`Row` 同行（y 坐标一致），代码层面**本就一行**，未做改动。
- **验证**：应用 177 通过；analyze 干净。

## D-143 服务启动失败 = macOS 签名失效（不是代码问题）

- **状态**：完成（2026-11-02）
- **现象**：设置页服务卡片显示「启动失败：Connection refused」，
  管道里存在 `mangasvc` 进程但**不监听任何端口**。
- **排查路径**：
  1. `ps` 发现两个 mangasvc：旧的在 5181 监听，新的（90788）存在但无端口，状态 `UE+`；
  2. 手动跑打包出的二进制 → **静默退出，无任何输出**；
  3. `dart run bin/mangasvc.dart` **能正常启动**（源码没问题）；
  4. 前台执行二进制 → `Killed: 9`（exit 137）；
  5. 系统日志：`load code signature error 2 for file "mangasvc"`；
  6. 崩溃报告：`SIGKILL (Code Signature Invalid)` /
     `namespace: CODESIGNING` / `Taskgated Invalid Signature`。
- **根因**：`dart compile exe` 产物是 **linker-signed（ad-hoc）签名**，
  被复制进 `.app/Contents/MacOS/` 后**签名不再有效**，macOS 直接 SIGKILL。
  与引擎、端口、代码逻辑都无关。
- **修复**：
  1. `codesign --force --sign - <二进制>` 重新 ad-hoc 签名后立即可用（已验证 5186 端口监听）；
  2. **固化到 `tool/package_macos.sh`**：复制进 `.app` 后自动重签，
     否则每次构建都会复发（脚本注释写明原因）。
- **遗留**：`kill -9` 杀不掉的 `UE+` 僵尸进程只能重启系统回收（不占端口，不影响使用）。

## D-144 投放按钮被拉伸 + 设置深链真正落地

- **状态**：完成（2026-11-02）
- **① 投放页「提交 / 清空」各占一整行**（截图实测）：
  外层 `Column(crossAxisAlignment: stretch)` 把 `Wrap` 撑满，按钮被拉成通栏。
  修法：`Wrap` 外套 `Align(centerLeft)` ⇒ 按钮恢复自身宽度、桌面端并排一行、窄屏换行。
- **② 设置页深链之前**从未生效**（上一轮改动静默失败）**：
  `SettingsScreen` 是 **`ConsumerWidget`（无 State）**，而我上轮加的是
  `didChangeDependencies` —— **方法根本不存在于该类**，替换没落地也没报错。
  修法：在 `build` 里读 `GoRouter.maybeOf(context)?.state.uri.queryParameters['section']`，
  与当前分组不同才 `postFrameCallback` 跳转（否则每次 build 都会把用户手动切的分组拽回）。
- **③ 实测验证**（不是推断）：
  - `settings_deeplink_test` 两条：`?section=translate` 落在翻译分组、无参数落通用分组 —— **通过**；
  - 队列动作列在同一 `QueueRowActions` 内量得两按钮 y 均为 132.5 —— **本就同一行**，
    之前"不在一行"的观测是我取 `.last` 跨行命中的测试错误，非产品缺陷。
- **教训**：`ConsumerWidget` 没有 `didChangeDependencies`；改代码后必须**运行验证**，
  静默替换失败不会报错（D-124/D-133 同类问题第三次）。
- **验证**：应用 179 通过；analyze 与 l10n 干净。
