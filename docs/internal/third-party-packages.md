# 第三方库规划留档

> 本文是第三方依赖的**规划清单与引入纪律**留档。本文所列候选包**均未写入任何 `pubspec.yaml`**；
> 实际引入时按 §纪律 执行，并把决定记入 `spec-notes.md`。
> 引入即受 `AGENTS.md` §4 第 7 条约束：**未经确认不引入**，提交信息与台账必须写清代价（包数 / 体积 / 运行时还是开发期）。

## 一、已引入

| 包 | 版本 | 用途 | 引入位置 |
|---|---|---|---|
| `flutter_riverpod` | 3.4.3 | 状态管理（唯一状态方案，见 AGENTS §3） | 根（App） |
| `go_router` | 16.3.0 | 屏级路由事实源 | 根（App） |
| `flutter_lints` | 6.0.0 | 静态检查基线 | 根（dev） |

## 二、候选清单（按引入时机分组）

### protocol 包：模型与契约

| 包 | 用途 | 引入时机 |
|---|---|---|
| `freezed` + `json_serializable` + `build_runner`（dev） | DTO 不可变建模与 JSON 编解码 | 写第一个 DTO 时 |
| `meta` | 契约注解（`@immutable` 等，低依赖） | 需要时 |

### App：状态与网络

| 包 | 用途 | 引入时机 |
|---|---|---|
| `riverpod_lint` + `custom_lint`（dev） | Riverpod 专属 lint | 第一个业务 Notifier 落地时 |
| `dio` | mangasvc HTTP 客户端（拦截器承载端口探测、取消） | manga/data 接真服务时 |
| `web_socket_channel`（或 http 流式 + SSE 自解析） | 队列阶段进度推送 | 队列屏需要实时进度时 |
| `collection` / `path` / `path_provider` / `uuid` / `intl` / `crypto` | 基础工具（官方或高引用低风险） | 各域按需 |
| `envied`（dev） | 编译期读 `.env` | 需要环境变量时 |

### App：存储

| 包 | 用途 | 引入时机 |
|---|---|---|
| `shared_preferences` | 偏好与设置持久化（对应 zustand persist 的落点） | settings 域落地时 |
| `flutter_secure_storage` | 敏感项（移动端 / Web 配对令牌） | 鉴权方案落地时 |
| `drift` | 本地结构化缓存（**备选**：音乐库 / 番剧库本地索引） | 明确需要本地索引再评估 |

### App：音视频

| 包 | 用途 | 引入时机 |
|---|---|---|
| `media_kit` + `media_kit_video` + `media_kit_libs_video` | 番剧播放（libmpv 内核） | 番剧域；**spike 前置**（见 §四） |
| `just_audio` + `just_audio_media_kit` | 音乐播放（桌面后端同为 libmpv） | 音乐域 |
| `audio_session` | 音频焦点 / 中断处理 | 音乐域 |

### App：桌面集成（core/window）

| 包 | 用途 | 引入时机 |
|---|---|---|
| `window_manager` | 窗口尺寸 / 无边框标题栏 / 置顶 | core/window 接入时，**必备** |
| `desktop_multi_window` | 桌面歌词第二窗 | 歌词窗落地；**spike 前置**（见 §四） |
| `tray_manager` / `hotkey_manager` / `launch_at_startup` | 托盘 / 全局快捷键 / 开机自启 | 按产品需求逐个评估 |

### App：manga 交互

| 包 | 用途 | 引入时机 |
|---|---|---|
| `desktop_drop` | 投放屏拖拽 | manga/submit 屏 |
| `file_selector`（官方） | 文件选择 | manga/submit 屏 |
| `qr_flutter` | 扫码投放（若保留该功能） | 产品确认后 |

### App：UI 单元

| 包 | 用途 | 引入时机 |
|---|---|---|
| `shadcn_ui` | 组件封装底座（**次选**，约束见 AGENTS §3：内置 Material 3 不够时才用，且只进 `shared/widgets/`） | 出现内置无法满足的组件时 |
| `lucide_icons_flutter` | 图标 | 第一个屏用图标时 |
| `flutter_svg` | SVG 图标 / 插画 | 设计资产有 SVG 时 |
| `flutter_animate` | 轻量动效（队列进度、屏过渡） | 动效需要时 |

### services：纯 Dart 侧

| 包 | 用途 | 引入时机 |
|---|---|---|
| `shelf`（或 `dart:io` 裸写） | mangasvc / animesvc 的本地 HTTP 服务 | server/ 实现时定 |
| `archive` | 引擎装配解包（tar.gz，注意保留可执行位） | runtime_setup 实现时 |
| `args` | 服务 CLI 参数解析 | 参数超过 3 个时再引入 |

### 测试与发布

| 包 | 用途 | 引入时机 |
|---|---|---|
| `mocktail` + `faker`（dev） | 单测替身与假数据 | 第一个业务单测时 |
| `logger` 或 `talker` | 统一日志分级 | core 层搭错误 / 日志时 |
| `flutter_launcher_icons`（dev） | 三平台图标生成 | 出第一个安装包前 |

## 三、纪律

1. **本文 ≠ 引入许可**：候选包进入 `pubspec.yaml` 前，须在提交信息与 `spec-notes.md` 台账写清包数 / 体积 / 是否运行时依赖。
2. **引入前查维护状态**：看最近提交时间与 issue 响应，比看 likes 更重要；Flutter 大版本跟进迟缓的库不引入。
3. **一次一个目的**：不为"可能用得上"预装；同一用途已有实现时先复用（AGENTS §4 第 10 条）。
4. **库类型不泄漏**：第三方 UI 组件一律经 `shared/widgets/` 薄封装进入业务层（AGENTS §3 组件库约束）。

## 四、已知风险点

- **`media_kit`**：维护节奏放缓，引入前必须 spike 验证（AGENTS §2 已裁定，失败则改走外挂播放进程）。
- **`desktop_multi_window`**：半维护状态，歌词窗的透明 + 置顶在 macOS 有平台限制，落地前实测。
- **明确不引入**：`flutter_markdown`（官方已停维护，需要 Markdown 渲染时选 `markdown_widget` 或 `gpt_markdown` 并另行评估）、`getx`（引用多但工程化口碑两极，与 Riverpod 决策冲突）、`isar`（维护状态存疑）。
