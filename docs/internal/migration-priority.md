# 迁移优先级（miao-dock → miao-dock-flutter）

> 依据：`miao-dock` 当前代码实测（文件行数、端点清单、模块依赖）+ `ver1.0/design.html` 设计稿 + 本仓库已落地进度。
> 排序原则：**先打通"能被端到端跑一次"的最短链路，再按用户价值补宽度**。不按代码行数排，按「阻塞关系」排。
> 状态基准日：2026-10-31（D-003 提交后）。

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

#### P0-B `mangasvc` 服务端实现（按端点组，逐组可验收）

| # | 任务 | 端点组 | 验收判据 | 规模参考 |
|---|---|---|---|---|
| P0-B1 | HTTP 骨架 + `/health` | `GET /health`、`GET /api/v1/health` | 进程起得来，健康检查返回就绪 | 最小可跑 |
| P0-B2 | 任务列表与创建 | `GET/POST /api/v1/tasks`、`GET /api/v1/tasks/{id}` | 投放能进队列，列表能读回 | handlers |
| P0-B3 | 任务变更 | `POST /tasks/delete`、`POST /tasks/{id}/cancel`、`POST /tasks/{id}/retry`、`POST /tasks/{id}/batches` | 取消保留已落盘；重试不重复提交 | handlers |
| P0-B4 | 队列串行执行 | `GET /api/v1/queue` + `queue/drain.rs` 等价物 | **同一时刻只跑 1 个**（这是原项目硬约束） | `drain.rs` |
| P0-B5 | 落盘存储层 | `store/` 等价物：书本 / 话 / 页三级 | 译文按「本 → 话 → 页」写入，重名不覆盖 | **3,663 行** |
| P0-B6 | 漫画库读接口 | `GET /api/v1/library`、`/library/{name}/meta`、`/files/{seq}`、`/cover` | 书架能列出真实目录 | store |
| P0-B7 | 漫画库写接口 | `POST /library/create`、`/meta`、`/cover`、`/delete`、`/unhide`、`/merge` | 新建 / 改名 / 删除生效 | store |
| P0-B8 | 章节级操作 | `/chapters/{no}/resume`、`/retranslate`、`/renumber`、`/files/{seq}` | 补页与重译整话可用 | store |
| P0-B9 | SSE 进度推送 | `GET /api/v1/tasks/{id}/events` | 队列进度实时推送，断线可重连 | `events.rs` |

#### P0-C 引擎接入（P0 里最重的一块，可独立迭代）

| # | 任务 | 说明 | 验收判据 |
|---|---|---|---|
| P0-C1 | 引擎状态机 | `GET /api/v1/engine/status`、`/runtime` | 五态机（stopped/starting/running/stopping/error）可观测 |
| P0-C2 | 引擎选项与设置 | `GET/POST /api/v1/engine/options`、`/settings` | 设置页能读能写 |
| P0-C3 | 模型校验 | `POST /api/v1/engine/models/verify` | 缺件能列出缺哪个 |
| P0-C4 | 模型下载（含暂停 / 续传） | `POST /engine/models/download`、`/download/pause` | 进度真实、暂停可续 |
| P0-C5 | 引擎空闲卸载 | `POST /api/v1/engine/unload` | 超时自动卸载权重 |
| P0-C6 | 翻译引擎接入 | 对接 manga-image-translator + LLM | 一张图能出译文 |

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

| # | 任务 | 验收判据 |
|---|---|---|
| P0-E1 | 投放 → 队列 → 落盘 全链路 | 拖入 3 张图，任务进队列，译文按「本 → 话 → 页」写入真实目录 |
| P0-E2 | 漫画库读回 | 重启应用后书架仍能看到刚才的书 |
| P0-E3 | 故障注入 | 服务中途停止时，UI 显示失败态且**不清空已成功数据**（设计稿 §07） |
| P0-E4 | 移动端远程模式 | Android 连桌面端地址，能拉到同一个书架 |

#### P0 内部建议顺序

```
P0-A1（契约）→ P0-A2/A3/A4（传输）
      ↓
P0-B1（骨架）→ P0-B2/B3（任务）→ P0-B4（串行队列）→ P0-B5（落盘）
      ↓                                        ↓
P0-D1/D2（子进程）                      P0-B6/B7/B8（库读写）
      ↓                                        ↓
P0-E1（端到端）← 先跑通「投放一张图」
      ↓
P0-C1..C5（引擎）→ P0-C6（真翻译）→ P0-E2/E3/E4
```

> **关键判断**：P0-E1 应该在 **P0-C 之前**跑通 —— 用一个 mock 引擎先把「投放→落盘→读回」的管道打通，
> 再接真引擎。否则引擎出问题时无法区分是管道错还是引擎错。

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
