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
