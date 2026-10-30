# 喵坞 · MiaoDock Flutter

**漫画翻译、音乐、番剧与桌面歌词的跨平台应用** —— 桌面端（macOS / Windows / Linux）全功能，移动端（iOS / Android）与 Web 端不跑本地服务。

- 漫画翻译服务端使用 [manga-image-translator](https://github.com/zyddnys/manga-image-translator) 作为翻译引擎，随应用装配到用户数据目录。
- **AI 协作上下文入口：`AGENTS.md`**（任何 AI 工具进入本仓库先读它）。
- **贡献**：先读 [`CONTRIBUTING.md`](CONTRIBUTING.md)（环境搭建 / 测试 / 提交规范 / PR 流程）。
- **许可**：[GPL-3.0](LICENSE) —— 见下方 §许可。

## 功能模块

### 1. 漫画翻译

- **服务**：桌面端实现 `mangasvc` + engine（manga-image-translator）+ LLM（本地 Sakura-GalTransl-7B-v3.7 或 LLM API），支持**单独部署、启动漫画图片翻译流水线**；移动端采用量化版引擎、模型，或通过局域网访问桌面端服务。
- **功能**：队列、投放、书架。

### 2. 音乐

- **支持平台**：网易云、酷狗、QQ音乐、咪咕 + 本地。
- **功能**：通用播放功能、播放历史、歌词等。

### 3. 番剧（待定）

- 追番周表、排行榜等。

## 目录

```
miao-dock-flutter/
├── pubspec.yaml                        # Flutter 工程根 + pub workspace 根（Dart 3.6+）
├── analysis_options.yaml               # 全 workspace 共用的静态检查与格式化配置
├── justfile                            # 开发命令入口：dev-app / dev-services / test
├── AGENTS.md
├── README.md
│
├── lib/                                # ── Flutter UI 壳 ──────────────────────────
│   ├── main.dart                       # 主窗入口
│   ├── lyrics_main.dart                # 桌面歌词独立窗入口（第二入口）
│   ├── app/                            # 装配层
│   │   ├── app.dart                    #   App 根组件、主题挂载、ProviderScope
│   │   ├── bootstrap.dart              #   启动装配：按平台与 --dart-define 注入 Fake/真客户端
│   │   └── router/
│   │       └── routes.dart             #   go_router 路由表（StatefulShellRoute）
│   ├── core/                           # 无业务基础设施（🔴 不得 import features/）
│   │   ├── theme/                      # 设计令牌 → ThemeExtension + ThemeData
│   │   ├── net/                        # dio 实例、端口段探测（仅桌面端）、统一错误
│   │   ├── process/                    # 服务子进程生命周期（仅桌面端）
│   │   ├── window/                     # 多窗、置顶、单实例锁（仅桌面端）
│   │   ├── storage/                    # shared_preferences 封装
│   │   └── utils/                      # 通用纯函数
│   ├── features/
│   │   ├── manga/                      # 漫画翻译
│   │   │   ├── data/                   #   mangasvc 客户端装配（真/Fake 切换在这层收口）
│   │   │   ├── domain/                 #   任务/批次/进度的领域模型与纯逻辑
│   │   │   ├── controller/             #   投放/队列/库三个 Riverpod Notifier
│   │   │   └── ui/
│   │   │       ├── submit/             #   投放屏（拖拽、批量选择）
│   │   │       ├── queue/              #   队列屏（阶段进度、批次）
│   │   │       └── library/            #   漫画库屏
│   │   ├── music/
│   │   │   ├── data/  domain/  controller/
│   │   │   └── ui/                     #   四平台、播放、歌词
│   │   ├── anime/
│   │   │   ├── data/  domain/  controller/
│   │   │   └── ui/                     #   番剧库、播放（media_kit）
│   │   ├── lyrics/
│   │   │   └── ui/                     #   桌面歌词窗 UI（lyrics_main.dart 挂载）
│   │   └── settings/
│   │       └── ...                     #   设置（引擎装配进度、移动端桌面端地址配置）
│   └── shared/                         # 跨域 UI 单元与纯函数（🔴 不得 import features/）
│       └── widgets/                    #   Skeleton / Empty / ErrorState / Modal / …
│
├── packages/
│   └── protocol/                       # ── App 与服务共享的契约（纯 Dart 包）──────
│       └── lib/
│           ├── protocol.dart           #   唯一出口（barrel）
│           └── src/
│               ├── dto/                #   任务、批次、进度事件、引擎状态的 DTO
│               ├── mangasvc_client.dart #  客户端接口（App 依赖接口，不依赖实现）
│               ├── animesvc_client.dart
│               ├── http_mangasvc.dart  #   真实现（dio/http）
│               └── fake_mangasvc.dart  #   ★ A 级替身：假队列 + 可推进的阶段进度
│
├── services/
│   ├── mangasvc/                       # ── 漫画服务（纯 Dart 包，独立进程）────────
│   │   ├── bin/
│   │   │   └── mangasvc.dart           #   入口：参数解析、--engine mock 开关
│   │   ├── lib/src/
│   │   │   ├── server/                 #   本地 HTTP 服务：路由表、handlers、端口绑定
│   │   │   ├── queue/                  #   串行队列、落盘恢复、20 张/批上限
│   │   │   ├── engine/
│   │   │   │   ├── client.dart         #   引擎 HTTP 客户端（base64 图进、流式阶段出、
│   │   │   │   │                       #     空闲超时、超时保留 partial bytes）
│   │   │   │   ├── supervisor.dart     #   llama-server 监督（状态机、空闲卸载、日志排空）
│   │   │   │   ├── runtime_setup.dart  #   装配：下载(sha256/断点续传/镜像)→解包→装依赖
│   │   │   │   ├── manifest.dart       #   版本锁与清单加载（URL/sha256/许可元数据）
│   │   │   │   └── mock/
│   │   │   │       └── mock_engine.dart #  ★ B 级替身：假引擎端点，服务自测不需要 Python
│   │   │   └── store/                  #   任务与库的落盘（启动即恢复、幂等）
│   │   └── pubspec.yaml
│   └── animesvc/                       # ── 番剧服务（纯 Dart 包，独立进程）────────
│       ├── bin/animesvc.dart
│       ├── lib/src/                    #   库扫描、元数据、播放记忆
│       └── pubspec.yaml
│
├── assets/
│   ├── fonts/                          # 本地打包字体（Inter / Noto Sans SC / Zen Maru Gothic）
│   └── icons/
│
├── test/                               # 单元与 widget 测试（镜像 lib/）
├── integration_test/                   # 端到端（C 级：连真实引擎，手动/CI 夜间跑）
├── docs/
│   └── internal/                       # dev-plan / spec-notes（D-001 起）/ test-policy / third-party-packages
└── .github/workflows/                  # CI：检查 + 测试 + 发布期按平台编译两个服务 exe
```

## 目录约定

1. **产品 / 测试分家**：测试只进 `test/` 与 `integration_test/`，不在产品目录混写；目录结构镜像 `lib/`。
2. **单一契约**：DTO 与 API 客户端接口只定义在 `packages/protocol/`，App 与服务不得各自另写一套。
3. **平台分支只收口在 `bootstrap.dart`**：桌面端注入本地进程管理与端口探测，移动端与 Web 端注入远程客户端（地址来自设置域的手动配置）；业务层不感知平台差异。
4. **临时产物**：构建产物统一在 `build/`，临时文件统一写 `.tmp/<用途>/`（两者都不入库），不在仓库根另建其他产物或临时目录。
5. **新增 / 搬迁目录必须同步更新本节与 `AGENTS.md` §3**，并检查断言中写死的路径。

## 平台策略

- **桌面端（macOS / Windows / Linux）全功能**：本地运行 `mangasvc` / `animesvc`，翻译引擎（manga-image-translator + 模型）在用户数据目录装配；桌面歌词、托盘等桌面特性可用。
- **移动端（iOS / Android）与 Web 端不启动任何本地服务**：漫画翻译通过设置中手动配置的桌面端地址调用桌面端 `mangasvc`（Web 场景 `mangasvc` 需开启 CORS）。
- 引擎替身三级：Fake 客户端（UI 开发）→ `mangasvc` 内置 mock 引擎（服务自测）→ 真引擎（联调与验收）。

## 快速开始（装环境 → 起 App → 连服务）

### 依赖总览

| 用途 | 依赖 | 说明 |
|---|---|---|
| 构建 UI / 服务 | **Flutter SDK**（用 [fvm](https://fvm.app) 锁定版本）+ Dart 3.6+（pub workspace） | 单一工具链，无原生语言依赖 |
| macOS 构建 | Xcode + CocoaPods | `flutter build macos` 需要 |
| Windows 构建 | Visual Studio 2022 生成工具（C++ 桌面开发） | `flutter build windows` 需要 |
| Linux 构建 | clang / cmake / GTK 开发库 | `flutter build linux` 需要 |
| 真翻译引擎（可选） | Python 3.11 运行时 + manga-image-translator + 模型权重 | 运行时由 `mangasvc` 装配到用户数据目录，**不入库**；日常开发用 mock，不需要装 |

### 一、装依赖

```bash
fvm install          # 按 .fvmrc 安装锁定的 Flutter 版本
fvm flutter pub get  # workspace：App + services + packages 一次拉齐
fvm dart run build_runner build --delete-conflicting-outputs
```

### 二、启动

```bash
# 只跑 UI（默认连 A 级 Fake，不需要任何服务进程）
fvm flutter run -d macos

# 桌面端整条链路：两个服务 + UI（服务用 mock 引擎，仍不需要 Python）
fvm dart run services/mangasvc/bin/mangasvc.dart --engine mock
fvm dart run services/animesvc/bin/animesvc.dart
fvm flutter run -d macos

# 移动端（漫画翻译经设置中手动配置的桌面端地址调用）
fvm flutter run -d ios    # 或 -d android

# Web 端（同移动端连桌面端服务；mangasvc 需为该场景开启 CORS）
fvm flutter run -d chrome
```

## 开发（随改随测）

反馈环分四层，从快到慢：

| 层 | 命令 | 覆盖 |
|---|---|---|
| 服务 / 纯逻辑测试 | `fvm dart test --watch`（在各包内） | 队列、装配、监督等业务逻辑，秒级红绿 |
| widget 测试 | `fvm flutter test --watch` | 屏与组件的渲染与交互 |
| 热重载跑 App | `fvm flutter run`（连 Fake 服务） | 真实观感、全链路 UI 走查，亚秒级 |
| 联调 | `dart run` 起真实服务 + App 连真服务 | 进程管理、协议对接、真数据 |

引擎替身分三级，真引擎只出现在最后一环：

- **A 级**：`packages/protocol/` 内的 Fake 客户端 —— UI 日常开发用，热重载不需要任何服务进程。
- **B 级**：`mangasvc` 内置 mock 引擎（`--engine mock`）—— 服务自测不需要 Python 存在。
- **C 级**：真引擎（manga-image-translator + 模型）—— 只用于联调与验收。

## 构建 / 发布

```bash
# 两个服务的可执行文件（不支持交叉编译，每个目标平台各自编译）
fvm dart compile exe services/mangasvc/bin/mangasvc.dart -o build/mangasvc
fvm dart compile exe services/animesvc/bin/animesvc.dart -o build/animesvc

# 应用本体（按平台）
fvm flutter build macos    # windows / linux / apk / ipa 同理
```

发布期由 CI（`.github/workflows/`）按平台矩阵编译服务可执行并打进应用产物。版本号以 `pubspec.yaml` 为事实源。

## 项目状态

项目处于**工程骨架与规范建立期**：目录设计与协作规范已定，代码尚未落盘。

## 许可

本项目代码以 [GPL-3.0](LICENSE) 分发。

随应用装配的第三方组件各有其许可，分发时必须一并满足：

- **manga-image-translator**：GPL-3.0-only —— 分发时必须提供对应版本的完整源码与许可声明（版本锁中的 engine commit 即对应关系）。
- **Python 运行时**（python-build-standalone）：MIT + PSF，附带许可文本随归档分发。

## 贡献

先读 [`CONTRIBUTING.md`](CONTRIBUTING.md)。提交信息遵循仓库规范（类型 + 中文标题 + 分点描述，每条 ≤ 50 字符）；改动自测脚本必须在提交正文中声明。行为准则见 [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)。
