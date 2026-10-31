# 迁移优先级（miao-dock → miao-dock-flutter）

> 依据：`miao-dock` 当前代码实测（文件行数、端点清单、模块依赖）+ `ver1.0/design.html` 设计稿 + 本仓库已落地进度。
> 排序原则：**先打通"能被端到端跑一次"的最短链路，再按用户价值补宽度**。不按代码行数排，按「阻塞关系」排。
> 状态基准日：**2026-10-31（D-019 提交后，P0-F5 落地）**。

## 〇、P0 状态总览（2026-10-31 23:10）

| 阶段 | 完成度 | 说明 |
|---|---|---|
| P0-A 协议与传输 | ✅ 100% | 契约 + HTTP + 端口探测 + 服务定位 |
| P0-B 服务端 | ✅ 97% | B1–B8 完成；B10 已由 C1–C5 顺带完成；B9 待做 |
| P0-C 引擎接入 | 🟡 95% | C1–C5 + **C6a–C6d 完成**；C6e 需真实模型与硬件 |
| P0-D 桌面端进程管理 | ⬜ 0% | **尚未开始**（见下方「已知缺口」） |
| P0-E 端到端验收 | ✅ 100% | E1–E4 全部完成 |
| P0-F 服务分层与引导 | ✅ 90% | F1 部分、F2–F5 完成、F6a–c 完成、F6d 记账 |

**已知缺口（诚实记录）**：

1. **P0-D 完全未做** —— `lib/core/process/` 不存在，`lib/` 内零处 `Process.start`。
   当前 `mangasvc` 需**手工启动**才能被应用连上；应用自己不会拉起它。
   这不阻塞 C6（C6 的进程监督是引擎侧，P0-D 是服务侧），但**是发布前的硬门槛**。
2. **P0-B9 翻译端点未做** —— `/translate/*` 五条未实现，但翻译来源三选一（D-012）后，
   该组端点语义需重新设计（本地/大模型/远程三条链路的分发），不宜照搬原项目。
3. **C4 下载与 C6 真下载的差距** —— C4 是状态机骨架，无真实模型源；
   C6 需补真实的 `Range` 续传 + sha256 校验。

## 一、当前已落地（作为优先级的起点）

| 层 | 已完成 | 证据 |
|---|---|---|
| 壳层 | 侧栏 208/68、工具条 56、断点 768、深浅双主题、页面切换动效 | D-003 / `test/app_shell*.dart` 15 条 |
| 漫画 | 投放 / 队列 / 漫画库三视图（A 级 Fake 驱动） | `lib/features/manga/ui/` |
| 音乐 | 四个视图路由 + 侧栏视图组 + MiniPlayer 槽位（**无数据**） | D-004 |
| 番剧 | 侧栏入口 + 路由占位 | `anime_screen.dart` |
| 服务 | `mangasvc` / `animesvc` 仅 15 / 7 行骨架 | `services/*/bin/` |

**关键事实：整个应用目前跑在 A 级 Fake 上，没有任何真实服务端。** 这决定了第一优先级不是"再做一个屏"，而是"让一个屏真起来"。

## 二、优先级总表

### P0 · 打通真实链路（不做完，后面全是假绿）

> **规模事实**：原项目 `mangasvc` 为 Rust 实现，`src-tauri/src/mangasvc/` 共 **24,616 行**
> （engine 11,476 / store 3,663 / translate 2,538 / handlers 与队列等其余），
> 路由表声明 **50+ 端点**（`handlers.rs` 的 `route()`）。上一版把 P0 估成「4 个端点」是错的，本版已纠正。
>
> **拆解原则**：按「能独立验收的最小闭环」切，而不是按模块切。每个子项都要能单独跑出一条可观察结果。

#### P0-A 协议契约与传输层（✅ 已完成 2026-10-31）

| # | 任务 | 交付物 | 验收判据 | 状态 |
|---|---|---|---|---|
| P0-A1 | 对齐 `packages/protocol` 的 HTTP 契约 | `MangaSvcClient` 接口按 `/api/v1` 真实路由重写，**50 个端点一一对应**；DTO 补齐 `TaskRow`/`TaskListResponse`/`LibraryResponse`/`EngineStatus`/`ModelDownloadView`/`ApiError` | 方法数 = 路由表端点数；契约词表原样往返 | ✅ |
| P0-A2 | 引入 `dio` 并建 `core/net` 客户端 | `MangaSvcHttpClient`：baseUrl/超时/令牌注入 + 错误信封解析 + JSON 字符串兜底 | 错误信封还原 `code`/`message`/`details`；401 归 `unauthorized` | ✅ |
| P0-A3 | 端口段探测（5180–5190） | `PortProbe`：TCP 可达 + `/health` 200 + `service` 字段匹配 | 非 mangasvc 服务占用端口时不误判 | ✅ |
| P0-A4 | 令牌鉴权 | `ServiceLocator`（桌面 Local / 移动 Remote）+ `Authorization: Bearer` | 令牌可热切换；空地址给明确错误 | ✅ |

**落地位置**：

| 层 | 文件 |
|---|---|
| 契约 | `packages/protocol/lib/src/manga_svc_client.dart`（50 端点） |
| DTO | `packages/protocol/lib/src/dto/{task_status,task_row,library,engine,api_error}.dart` |
| 传输 | `lib/core/net/manga_svc_http.dart`、`port_probe.dart`、`service_locator.dart` |
| 实现 | `lib/features/manga/data/http_manga_svc_client.dart` |
| 转换 | `lib/features/manga/data/contract_map.dart`（DTO → domain） |
| 装配 | `lib/app/bootstrap.dart`（平台分支注入） |

**踩坑记录（写进代码注释）**：
1. `flutter_test` 的 `TestWidgetsFlutterBinding` **拦截所有 HttpClient 并强制返回 400** —— 传输层与 widget 层测试必须**分文件**，同文件出现 `testWidgets` 会掐断整份 suite 的真实网络。
2. dio 在部分 Content-Type 下返回 **String 而非 Map** —— 响应解析必须两种都能吃，否则正常响应被误判成协议错误。
3. 契约状态词表是**下划线**（`partial_failed`/`canceled`），不是驼峰；未知状态**抛错不降级**。

#### P0-B `mangasvc` 服务端实现（B1–B6 已完成骨架与主链路）

| # | 任务 | 端点组 | 验收判据 | 状态 |
|---|---|---|---|---|
| P0-B1 | HTTP 骨架 + `/health` | `GET /health`、`GET /api/v1/health` | 进程起得来，健康检查返回就绪 | ✅ |
| P0-B2 | 任务列表与创建 | `GET/POST /api/v1/tasks`、`GET /api/v1/tasks/{id}` | 投放能进队列，列表能读回 | ✅ |
| P0-B3 | 任务变更 | `POST /tasks/delete`、`/cancel`、`/retry`、`/batches` | 取消保留已落盘；重试不重复提交 | ✅ |
| P0-B4 | 队列串行执行 | `GET /api/v1/queue` | **同一时刻只跑 1 个** | ✅ |
| P0-B5 | 落盘存储层 | 本 / 话 / 页三级 + manifest | 按「本 → 话 → 页」读写 | ✅ 基础版 |
| P0-B6 | 漫画库读写 | `/library`、`/create`、`/meta`、`/cover`、`/files`、`/delete`、`/unhide` | 书架能列出真实目录 | ✅ 基础版 |
| P0-B7 | 章节级操作 | `/chapters/{no}/resume`、`/retranslate`、`/renumber` | 补页与重译整话可用 | ✅ |
| P0-B8 | 返工计划 | `/library/{name}/resume`、`/retranslate` | 返工范围与覆盖数准确 | ✅ 基础版 |
| P0-B9 | 翻译端点 | `/translate/*` 五条 | 文本翻译与设置可读写 | ⬜ 待做（语义需按 D-012 重新设计） |
| P0-B10 | 引擎端点 | `/engine/*` | 状态 / 下载 / 校验 | ✅ 由 P0-C1~C5 完成（10 条，含 start/stop） |

**P0-B 已完成部分的落地位置**：

| 层 | 文件 |
|---|---|
| 路由表 | `services/mangasvc/lib/src/server/routes.dart`（**48 条** = 45 客户端方法 + `/health` 双路径 + `engine/start`、`engine/stop`） |
| HTTP / 信封 | `services/mangasvc/lib/src/server/http.dart` |
| 分发 | `services/mangasvc/lib/src/server/handlers.dart` |
| 服务本体 | `services/mangasvc/lib/src/server/server.dart`（端口段绑定 + 就绪行协议） |
| 串行队列 | `services/mangasvc/lib/src/queue/task_queue.dart`（并发上限 1） |
| 落盘 | `services/mangasvc/lib/src/store/library_store.dart`（目录即索引） |

**实测发现的两个真实 bug**（写进代码注释）：
1. `_hidden` 是 `Set`，`jsonEncode` 编码失败 → 首次 `/library` 请求直接 500。扫描真实目录时暴露。
2. `matchRoute` 对已解码的 `uri.path` 又做了一次 `Uri.decodeComponent` → 双重解码。

#### P0-C 引擎接入（P0 里最重的一块，可独立迭代）

| # | 任务 | 说明 | 验收判据 |
|---|---|---|---|
| P0-C1 | 引擎状态机 | `GET /api/v1/engine/status`、`/runtime` | 五态机可观测 | ✅ |
| P0-C2 | 引擎选项与设置 | `GET/POST /api/v1/engine/options`、`/settings` | 设置页能读能写 | ✅ |
| P0-C3 | 模型校验 | `POST /api/v1/engine/models/verify` | 缺件能列出缺哪个 | ✅ 基础版 |
| P0-C4 | 模型下载（含暂停 / 续传） | `POST /engine/models/download`、`/download/pause` | 进度真实、暂停可续 | ✅ 骨架（真实源待 C6） |
| P0-C5 | 引擎空闲卸载 | `POST /api/v1/engine/unload` | 超时自动卸载权重 | ✅ |
| P0-C6 | 翻译引擎接入 | 对接 manga-image-translator + LLM | 一张图能出译文 |

**C6 拆解（2026-10-31 细分，按「可独立验收」切）**：

| # | 任务 | 交付物 | 验收判据 | 状态 |
|---|---|---|---|---|
| P0-C6a | 运行时装配 | `runtime_setup.dart`：解包 tar.gz/zip、**保留可执行位** | 解开一个含可执行文件的包，权限位不丢 | ✅ |
| P0-C6b | 模型下载 | `model_download.dart`：真实 HTTP + `Range` 续传 + sha256 | 断点续传后文件与一次性下载**逐字节相同** | ✅ |
| P0-C6c | 进程监督 | `supervisor.dart`：spawn + 健康探针 + 崩溃退避重启 | 杀掉子进程后能自动拉起，且退避时长递增 | ✅ |
| P0-C6d | 翻译客户端 | `engine_client.dart`：调引擎 HTTP API | 对 stub 引擎能跑通一次翻译请求 | ✅ |
| P0-C6e | 真引擎对接 | manga-image-translator 真实调用 | 一张图能出译文 | ⬜ 需真实模型与硬件 |

> **C6a–C6d 可在无模型、无 GPU 的环境下完整验证**（用构造的包 / 本地 HTTP 桩 / 假引擎脚本）。
> **只有 C6e 需要真实模型文件与硬件** —— 这也是为什么把它单独列为最后一项，
> 避免「验证不了的部分」拖住「能验证的部分」。
>
> **P0-C 建议单独立项**：原项目 `engine/` 有 **11,476 行**（含 supervisor 1,106、wheels 563、tier_downgrade 347），
> 是整个迁移里最重的一块，不应和 P0-A/B 捆在同一迭代承诺里。

#### P0-D 桌面端进程管理

| # | 任务 | 交付物 | 验收判据 |
|---|---|---|---|
| P0-D1 | 子进程启动与就绪等待 | `core/process/`：拉起 `mangasvc`，等待就绪行协议 | 应用启动能带起服务 |
| P0-D2 | 生命周期与退出清理 | 应用退出时终止子进程，不留僵尸 | 退出后端口释放 |
| P0-D3 | 服务状态对 UI 的可观测性 | `ServiceStatus` provider，五态映射 | 侧栏设置脚的状态点跟随真实状态 |
| P0-D4 | 打包形态 | `dart compile exe` 产物随应用分发 | 打包后能自启动服务 |

#### P0-E 端到端验收（P0 的出口条件）

| # | 任务 | 验收判据 | 状态 |
|---|---|---|---|
| P0-E1 | 投放 → 队列 → 落盘 全链路 | 投放 3 张图，任务进队列，译文按「本 → 话 → 页」写入真实目录 | ✅ |
| P0-E2 | 漫画库读回 | 重启应用后书架仍能看到刚才的书 | ✅（落盘即持久，重启只重扫目录） |
| P0-E3 | 故障注入 | 服务中途停止时 UI 显示失败态且**不清空已成功数据** | ✅ |
| P0-E4 | 移动端远程模式 | Android 连桌面端地址，能拉到同一个书架 | ✅ |

**E1 实测记录（2026-10-31）**：

```
投放 3 张 /tmp/e1-src/{01,02,03}.png
  → 落盘 /tmp/e1-lib/E1验证本/01_第1话/
      001.png  001_translated.png
      002.png  002_translated.png
      003.png  003_translated.png
  → 书架读回：books=1, totalImages=3, 已译 [1,2,3], 缺页 []
  → 单话续做计划：pendingCount=0
```

**关键约束**：落盘时必须同时写 `manifest.json`，否则该目录会被扫描归类为「未归并单话」而不是「本」，书架读不回（反证已验证）。

**E3 实测记录（2026-10-31）**：

| 场景 | 期望 | 实测 |
|---|---|---|
| 在线读到 1 本 → 杀服务 → 再读 | 报 `unreachable` | ✅ `kind=unreachable` |
| 首次就失败（无旧数据） | 整块错误态 | ✅ 显示「连不上本地服务」+ 重试 |
| 有旧数据后失败 | 横幅 + 旧数据并存 | ✅ 横幅出现，任务仍在 |
| 鉴权失败 | 对应文案（不是笼统「加载失败」） | ✅ 显示「配对令牌无效」 |

**E3 修复的三个真实缺陷**：
1. **队列 `build()` 吞异常**：`catch` 后 `return _lastGood`（空），provider 变成 `AsyncData([])`，UI 把失败画成**空态**「还没有翻译任务」—— 用户以为没任务，实际是服务挂了。改成让异常抛出成为 `AsyncError`。
2. **`hasError` 与 `isLoading` 同时为真时判序错误**：Riverpod 重试期状态是 `AsyncLoading.copyWithPrevious(error)`，先判 loading 会让失败态被骨架屏永久盖住。改为**先判 hasError**。
3. **书架完全没有 `lastGood`**：只有队列做了保留，服务一挂书架整片变空。已补 `lastGood` + `refresh()`，并在 `shelfBooks` 里回落。

**e2e 与默认测试的分工**（避免假绿）：e2e 需要真实服务，未起服务时**显式 skip 并打印原因**，不静默通过。`flutter test` 实测：有服务 42 通过 + 8 跳过；无服务 42 通过 + 8 跳过（跳过项随场景互换）。

**E4 实测记录（2026-10-31）**：

| 场景 | 期望 | 实测 |
|---|---|---|
| 远程地址 + 正确令牌 | 200 读到书架 | ✅ |
| 无令牌 | 403 + `unauthorized` | ✅ |
| 错误令牌 | 403 + `unauthorized` | ✅ |
| `GET /health` 免令牌 | 200 | ✅ |
| `OPTIONS` 预检 | 204 + 4 个 CORS 头 | ✅ |
| 合法 Origin（chrome-extension） | 200 + 回显 allow-origin | ✅ |
| 非法 Origin（https://evil…） | 403，**不回** allow-origin | ✅ |
| `X-Box-Client: extension` | 任务 source = extension | ✅ |

**E4 修正的契约错误与缺陷**：
1. **鉴权头名写错**：P0-A 用了 `Authorization: Bearer`，原项目实际是 **`X-Box-Token`**。头名不对会得到 403 且完全看不出原因。
2. **服务端完全没有 CORS / Origin 白名单 / 令牌校验**：跨设备访问是暴露面，不设防等于把本地服务开放给同网段任何人。
3. **`state/` 目录被当成漫画扫描出来**：存 token 的目录出现在书架里。
4. **`X-Box-Client` 未读取**：来源恒为 `desktop`，插件提交的任务归因错误。

#### P0 内部建议顺序

```
已完成 ────────────────────────────────────────
  P0-A1                契约
  P0-A2/A3/A4          传输 / 端口探测 / 服务定位
  P0-B1..B8            服务端主体（骨架→队列→落盘→库读写）
  P0-E1..E4            端到端验收
  P0-C1..C5            引擎端点
  P0-C6a..C6d          运行时装配 / 模型下载 / 进程监督 / 翻译客户端
  P0-F1..F6（除 F6d）   分层 / 引导页 / 来源 / 标识 / 设置 / 路径

待做 ──────────────────────────────────────────
  P0-C6e              真引擎对接（需真实模型与硬件）
  P0-D1..D4           服务进程管理（发布硬门槛）
  P0-B9               翻译端点（语义待三选一定稿）
  P0-F6d              运行时完整性校验（已记账）
```

> **剩余路线**：`C6e`（需硬件）与 `P0-D`（发布硬门槛）可并行。
> `B9` 放在最后，因为它的语义依赖三选一来源最终怎么分发。

> **关键判断**：P0-E1 应该在 **P0-C 之前**跑通 —— 用一个 mock 引擎先把「投放→落盘→读回」的管道打通，
> 再接真引擎。否则引擎出问题时无法区分是管道错还是引擎错。

#### P0-F 服务分层与启动引导页（2026-10-31 定案，见 D-012）

| # | 任务 | 说明 | 状态 |
|---|---|---|---|
| P0-F1 | 服务分层改造 | 服务常驻；引擎 / LLM 合并为一个开关，可手动或按设置自动唤起 | 🟡 引擎侧完成（共用开关 + start/stop）；**服务常驻需 P0-D** |
| P0-F2 | 启动引导页（合并 guide + download） | 六态：未装配/下载中/已装未启动/启动中/失败/服务异常 | ✅ UI 完成（数据已接 C1–C5） |
| P0-F3 | 翻译来源三选一 | `本地翻译` / `大模型翻译` / `远程翻译`；移动端仅远程 | ✅ 模型 + 持久化 + 设置页分段控件 |
| P0-F4 | 状态标识重构 | 移除「服务已启动」徽标；侧栏点改「能否翻译」四色；工具条显示来源 + 引擎就绪度 | ✅ |
| P0-F5 | 设置页「翻译服务」组 | 服务卡片 + 来源三选一 + 推理引擎行 | ✅（D-019） |

#### P0-F6 引擎运行时目录选择与导入（2026-10-31 新增）

| # | 任务 | 说明 | 状态 |
|---|---|---|---|
| P0-F6a | 路径层 | 用户成果与产品数据分树；`runtimes` 默认 `<appData>/MiaoDock/manga/runtimes`；模型在 `state/models-state` | ✅ |
| P0-F6b | 下载时选目录 | 每次下载都弹选择框，默认定位 runtimes；**不记忆上次** | ✅ 对话框完成（接下载流程待 P0-C） |
| P0-F6c | 导入本地 runtimes | 用户指向已有目录，跳过下载直接使用 | ✅ 对话框完成（写入配置待 P0-C） |
| P0-F6d | 运行时完整性校验 | **记账，后做**：校验 `src/` `venv/` `models-store/` 是否齐全、版本是否匹配 | ⬜ 记账 |

> **排序说明**：P0-F2 的 UI 先于 P0-C 落地（设计稿需先核对），但**真实数据依赖 P0-C**。
> 因此 F2 先做「预检态 / 未装配态」两种可独立成立的形态，下载进度等 P0-C 接入后再接真数据。

### P1 · 漫画域补全（已有 UI，补真实能力）

| # | 任务 | 现状差距 | 规模依据 |
|---|---|---|---|
| P1-1 | 引擎装配与模型下载 | 原项目有完整下载面板（`DownloadPanel.tsx` 415 行）+ 校验/续传/暂停；本仓库无 | `/engine/models/download`、`/pause`、`/verify` |
| P1-2 | 引擎状态与设置（`/engine/status`、`/options`、`/settings`） | 设置页仍是占位文字 | 原 `EngineDiag.tsx` 746 行 |
| P1-3 | 漫画阅读器 | 原 `viewer.tsx` 624 行（翻页/缩放/手势）；本仓库无 | 设计稿 G 组阅读器 |
| P1-4 | 单话详情页（页网格） | 原 `chapters.tsx` 276 行；本仓库只有书架与详情两栏 | 设计稿 G 组话内 |
| P1-5 | 补页 / 重译 / 新建漫画弹窗 | 原 `modals.tsx` 653 行 | `/library/create` |

> P1 全部依赖 P0；其中 P1-1 是硬门槛——**没有模型就没有翻译**。

### P2 · 音乐域（当前是空壳，工作量最大的一块）

| # | 任务 | 现状 | 规模依据 |
|---|---|---|---|
| P2-1 | `just_audio` 播放内核 + 四平台音源代理 | 完全未开始 | `MusicKernel.tsx` 352 行 / `platform.ts` 503 行 / `ipc.ts` 494 行 |
| P2-2 | 音乐状态机（队列/随机/循环/音量/静音） | `nowPlayingProvider` 恒为 null | `store.ts` 848 行（最大的单文件） |
| P2-3 | 播放条 + MiniPlayer 接真实数据 | UI 已建好，等 P2-2 | `PlayerBar.tsx` 328 行 |
| P2-4 | 展开播放器（六皮肤 + 歌词 + 光碟 + 评论） | 未开始 | `ExpandedPlayer.tsx` 796 行 |
| P2-5 | 歌词系统（逐字 + 翻译 + 卡拉 OK） | 未开始 | `KaraokeLyrics.tsx` 387 行 + `lyrics/DesktopLyrics.tsx` 1001 行 |

> **建议拆分**：P2-1/2/3 是一组（能播能控），P2-4/5 是另一组（视觉与歌词）。不要把 P2 当一个任务。

### P3 · 桌面专属能力（决定"是不是一个桌面应用"）

| # | 任务 | 说明 | 依赖 |
|---|---|---|---|
| P3-1 | 灵动岛（DynamicIsland） | 原 `DynamicIsland.tsx` 664 行；设计稿 §03 明确 200×30 ⇄ 320×150 形变 | 需 P2 有播放状态 |
| P3-2 | 桌面歌词第二窗 | 原 `DesktopLyrics.tsx` 1001 行；`desktop_multi_window` 需先 spike | `third-party-packages.md` §四 已标风险 |
| P3-3 | 托盘 / 全局快捷键 / 开机自启 | 原 `useMusicHotkeys.ts` 262 行 | 各需单独评估 |

### P4 · 番剧域（原项目入口默认隐藏，优先级最低）

原项目 `SHOW_ANIME_ENTRY: boolean = false` 把入口隐藏了，九个视图（explore/collection/cache/history/detail/player/account/source/states）全部存在但用户看不到。

**建议**：等漫画与音乐稳定后再启动，且启动前先确认产品是否仍要做番剧。

### P5 · 设置域与外设

| # | 任务 | 规模 |
|---|---|---|
| P5-1 | 设置五分组（通用/翻译/播放/资源/关于） | `catalog.ts` 538 行 |
| P5-2 | 规格自检（34 项断言） | `SpecCheck.tsx` 354 行 |
| P5-3 | 存储用量与清理 | `StorageBlock.tsx` 292 行 |

## 三、依赖关系图

```
P0-1 mangasvc ──┬─→ P1-1 模型下载 ──→ P1-2 引擎设置
P0-2 dio 客户端 ─┤
P0-3 子进程    ──┴─→ P1-3 阅读器 / P1-4 话详情 / P1-5 弹窗
                              │
                              └─→ P5-1 设置（读真实状态）

P2-1 播放内核 ──→ P2-2 状态机 ──→ P2-3 播放条/MiniPlayer
                              ├─→ P2-4 展开播放器
                              ├─→ P2-5 歌词
                              └─→ P3-1 灵动岛

P2-2 ──→ P3-2 桌面歌词（需 spike desktop_multi_window）

P4 番剧：独立于以上全部，可并行但优先级最低
```

## 四、建议的迭代节奏

| 迭代 | 内容 | 验收判据 |
|---|---|---|
| 迭代 1 | P0-1/2/3 | 真实 `mangasvc` 起得来，投放一张图能进真实队列并落盘 |
| 迭代 2 | P1-1/2 | 模型下载有真实进度，引擎状态在设置页显示真实值 |
| 迭代 3 | P1-3/4/5 | 漫画三视图 + 阅读器全链路可读 |
| 迭代 4 | P2-1/2/3 | 一首歌能播、能暂停、能切歌，播放条反映真实进度 |
| 迭代 5 | P2-4/5 + P3-1 | 展开播放器六皮肤与歌词跟随 |
| 迭代 6 | P3-2 + P5 | 桌面歌词窗 + 设置页真实化 |

## 五、明确的风险与前置 spike

| 项 | 风险 | 处置 |
|---|---|---|
| `media_kit`（番剧播放） | 维护节奏放缓，AGENTS §2 已要求 spike | 番剧启动前先 spike，失败改外挂进程 |
| `desktop_multi_window`（歌词窗） | 半维护；macOS 透明+置顶有平台限制 | P3-2 前 spike，实测通过再排期 |
| `just_audio` 桌面后端 | 原项目用 Web Audio Graph（`audioGraph.ts` 259 行）做增益/EQ；Flutter 侧无等价物 | P2-1 期间必须 spike，缺口先报再定方案 |
| 四平台音源（网易云/酷狗/QQ/咪咕） | 涉及各家接口与鉴权，非纯 UI 工作量 | 单独评估，可能需要砍到 1–2 家先跑通 |
| 移动端 | 不跑本地服务，全部走桌面端 `mangasvc`；鉴权方案未定 | 在 P0 设计期一并定，见 AGENTS §2 |

## 六、几条不可越过的约束

1. **不得为赶进度写死数据**：音乐/番剧在真实链路打通前，只能给空态（D-004 已立此规矩）。
2. **依赖红线**：`just_audio`、`dio`、`media_kit`、`desktop_multi_window` 虽已在 `third-party-packages.md` 登记为候选，但**进入 `pubspec.yaml` 前仍须按 §纪律 1 在提交信息与台账写清包数/体积/运行时属性**。
3. **服务包只允许纯 Dart 依赖**（AGENTS §2），不得引入 Flutter SDK。
4. **先 spike 后排期**：上表标"需 spike"的四项，未出结论前不得并入迭代承诺。
