# AGENTS.md — 喵坞 MiaoDock Flutter 协作规范

> 本文件是 AI 编程工具进入仓库后的唯一入口，只保留项目概况、不可违反的规则和常用工作流。
> 详细设计与历史决策以仓库文档和当前代码为准；不要把本文件扩写成第二份设计文档。

## 1. 信息源与语言

- **工作语言：中文**；代码标识符除外。
- 事实源：`README.md`、`docs/internal/dev-plan.md`、`docs/internal/spec-notes.md` 与当前代码。
- 决策记录发生冲突时，优先参考 `docs/internal/spec-notes.md`，核对实际代码后再更新文档。
- 决策台账：`docs/internal/spec-notes.md`，编号从 **D-001** 起全局递增、不得重复。
- 落案只写**最关键的信息**（做了什么 / 为什么 / 怎么验证），并标注状态（已完成 / 开发中 / 挂起 / 已废弃）；不写背景复述与推导过程。

## 2. 项目概况

喵坞 MiaoDock 是基于 Flutter 的应用：桌面端（macOS / Windows / Linux）全功能，移动端（iOS / Android）与 Web 端不跑本地服务；包含漫画翻译、音乐、番剧功能与桌面歌词。

| 层 | 技术 / 职责 | 主要位置 |
|---|---|---|
| UI 壳 | Flutter（Dart）、Material 3 定制主题、go_router、Riverpod | `lib/`（仓库根即 Flutter 工程根） |
| 漫画服务 | Dart 可执行文件 `mangasvc`（本地 HTTP，127.0.0.1:5180–5190） | `services/mangasvc/` |
| 番剧服务 | 独立 Dart 可执行文件 `animesvc` | `services/animesvc/` |
| 协议契约 | App 与服务共享的 DTO 与 API 契约 | `packages/protocol/` |
| UI 域模块 | feature-first：data / domain / controller / ui 四层 | `lib/features/<域>/` |
| 测试 | 单元、widget 与集成测试 | `test/`、`integration_test/` |
| 移动端 / Web | iOS / Android / 浏览器：不跑本地服务，漫画翻译调用桌面端 | 地址在设置域手动配置 |

关键架构裁定（变更须先过台账）：

- 两个服务均为 **Dart 独立进程**：开发期 `dart run`，发布用 `dart compile exe` 编成自包含可执行文件。与 UI 同语言、不同进程，互不拖累。
- 服务包只允许**纯 Dart 依赖**（不得引入 Flutter SDK），保证脱离 Flutter 工具链也能编译运行。
- UI ↔ `mangasvc` 走 HTTP（dio）：桌面端经端口段探测（5180–5190 服务发现）连本机服务，移动端连**手动配置的桌面端地址**；桌面端服务子进程生命周期由 Flutter 侧管理。
- **服务子进程只在桌面端运行**；移动端与 Web 端不启动任何本地服务，也不装配翻译引擎。
- 移动端与 Web 端漫画翻译直接调用桌面端 `mangasvc`（Web 场景 `mangasvc` 须开启 CORS）。跨设备调用是暴露面，鉴权（令牌）方案必须在服务设计期确定并记台账。
- 番剧播放用 **media_kit（内嵌 libmpv）** 进程内播放；落地前以 spike 验证，失败则改走外挂播放进程。
- 桌面歌词是**第二 Flutter 入口**（`lib/lyrics_main.dart` 独立窗，桌面专属），不是第二 WebView。
- 音乐播放走 just_audio 播代理 URL；增益 / EQ / 可视化等音频处理能力在桌面端的缺口须先 spike 再定方案。

## 3. 架构约束

### Flutter（lib/）

- `lib/` 根只保留入口（`main.dart`、`lyrics_main.dart`），其余按层分目录：
  - `lib/app/`：装配层（App、主题挂载、ProviderScope、路由表；`bootstrap.dart` 收口平台分支与 Fake/真客户端注入）。
  - `lib/core/`：无业务基础设施（theme / net / process / window / storage / utils）。
  - `lib/features/<域>/`：业务域（manga / music / anime / lyrics / settings），域内分 `data/`（api 客户端 + DTO + repository）、`domain/`（模型与纯逻辑）、`controller/`（Riverpod Notifier）、`ui/`（屏 + 屏内件）。
  - `lib/shared/`：跨域 UI 单元与纯函数。
- **分层判据（硬约束）**：`core/`、`shared/` 不得 import `features/`；`ui/` 不直接使用 dio / Process，只经 controller 与 repository；feature 之间不横向 import，跨域跳转走路由、跨域状态在 `lib/app/` 层协调；DTO 不直接上 UI，经 domain 模型转换。
- 平台差异只在 `bootstrap.dart` 收口：桌面端注入本地进程管理与端口探测，移动端与 Web 端注入远程客户端（地址来自设置域的手动配置）；业务层不感知平台差异。
- 跨组件共享状态使用 Riverpod（`Notifier` / `AsyncNotifier`），不引入其他状态库；异步数据一律 `AsyncValue`，loading / empty / error 三态使用 `shared/widgets/` 的 Skeleton / Empty / ErrorState 呈现。
- `lib/app/router/` 是屏级路由事实源（go_router + StatefulShellRoute）。新增屏时同步更新路由表。
- `lib/` 内引用一律使用 package 导入（`package:miao_dock_flutter/...`）；包名变更时全局同步。
- 设计令牌位于 `lib/core/theme/`（落成 `ThemeExtension` + `ThemeData`）；修改令牌前检查相关断言。
- 通用 UI 优先复用 `lib/shared/widgets/`；仅服务单屏的组件留在该屏内。
- **组件库约束**：首选 Material 3（内置基座，经 `ThemeExtension` / 主题定制融入设计令牌）；内置无法满足的组件，次选以 `shadcn_ui` 为底自行封装进 `lib/shared/widgets/`，库类型不得泄漏到业务层。不引入其他整体组件库。
- **图标约束**：所有图标统一使用 **lucide**（`lucide_icons_flutter`）或与其一致的线性风格；不混用其他图标体系（Material Icons、CupertinoIcons 等仅作兜底占位，不允许进入正式 UI）。
- **国际化约束（D-006，强制）**：
  - 实现方案为 Flutter 官方 `gen_l10n`：`flutter_localizations` + `l10n.yaml` + `lib/l10n/app_*.arb`，生成物 `lib/l10n/app_localizations*.dart` **不入库**（已在 `.gitignore`）。不引入 `easy_localization`、`slang`、`gettext` 等第三方 i18n 库。
  - **当前阶段只出中文、不做任何语言切换**：`supportedLocales` 只允许含 `zh`；不得在 UI 上放语言选择器。新增语言是**独立提案**，须先过台账，且不得以「预留」为名提前铺 `en` 词条。
  - **所有面向用户的中文文案必须走 ARB**：禁止在 `lib/` 的 Widget 里写死中文字面量（含按钮、提示、空态、错误、吐司、无障碍 `semanticsLabel` 与 `tooltip`）。`lib/l10n/` 与测试除外。
  - ARB 词条 key 用**小驼峰语义名**（`viewDrop`、`actionCollapseSidebar`），不用中文、不用序号；每条必须有 `@key` 的 `description`。
  - 需要拼接的文案用 ARB 占位符（`{count}` 等），不在 Dart 里做字符串相加 —— 否则后续加语言必然拆不开。
  - 新增/修改文案后必须跑 `flutter gen-l10n`，并同步更新 `test/l10n_test.dart` 的断言基准。
  - 后端契约里的**错误码**（如 `INVALID_IMAGE`）不进 ARB；界面按错误码映射到 ARB 词条，不直接展示服务端 `message` 原文。
- 新增窗口入口（如未来托盘设置窗）时，在本文 §2 与 README 同步登记入口文件。

### 服务（services/，Dart）

- `services/` 下每个服务是独立的 Dart 包：入口在各自 `bin/`，业务实现按域分 `lib/src/`；仓库内没有原生（Rust / C++）工程。
- `packages/protocol/` 是 App 与服务共享的 DTO 与 API 契约的**唯一事实源**；`lib/` 与两个服务都从这里 import，不得各自另写一套。
- `mangasvc` 内部分 `server/`（HTTP 服务）、`queue/`（串行队列与落盘）、`engine/`（引擎客户端、llama-server 监督、运行时装配、内置 mock 引擎）、`store/`（落盘）。
- 引擎替身分三级：A 级 Fake 客户端在 `packages/protocol/`（UI 日常开发用）；B 级内置 mock 引擎在 `mangasvc` 的 `engine/mock/`（服务自测，不需要 Python）；C 级真引擎只用于联调与验收。
- 服务进程只在桌面端运行；移动端 / Web 端经手动配置的桌面端地址访问（Web 需 CORS），该暴露面的鉴权方案在服务设计期确定。
- 新增漫画服务端点时，同时更新 `mangasvc` 的路由表与 handlers。
- 服务与 UI 之间只通过 HTTP / 进程管理接缝交互；UI 不直接读写服务的数据文件。

### 目录与产物

- 测试与产品代码分开：测试放 `test/`（单元与 widget）与 `integration_test/`（端到端），目录结构镜像 `lib/`；不在产品目录内混写测试。
- 构建产物统一在 `build/`（不入库）；临时文件统一写 `.tmp/<用途>/`（不入库）；不要在仓库根另建其他产物或临时目录。
- 新增或搬迁目录后，检查并同步 `README.md` 目录说明、本文与断言中写死的路径。
- 版本号以 `pubspec.yaml` 为事实源，不得在脚本中写死。

## 4. 必须遵守的工程纪律

1. **以当前代码为准。** 记忆和旧文档不能代替检查；发现台账与实现不一致时，核实后更新台账。
2. **断言必须可反证。** 修改或新增断言时，说明「破坏什么会导致哪条断言失败」，并实际运行反证轮。反证锚点未命中不能算通过。
3. **禁止假绿与静默跳过。** 断言数量应有明确基准；跳过项必须显式报告，必要时以非零退出码结束。
4. **覆盖实际依赖层。** 用户可见行为依赖多个层时，不能只验证最上层；逐层确认故障能否触发失败。
5. **关键节点独立提交。** 提交信息格式：

   ```
   refactor|chore|style|docs|fix: 中文标题

   - 功能点描述
   - 功能点描述
   ```

   - 类型只用五个：`refactor`（结构 / 命名 / 抽离，行为不变）、`chore`（工具链与非代码结构调整）、`style`（纯格式化，无逻辑变化）、`docs`（文档 / 台账）、`fix`（修缺陷）。
   - 标题**只能为中文**；正文用分点描述本次开发的功能，**每条不超过 50 字符**；不加 emoji、句号或文件清单。
   - **改动了自测脚本必须在正文同步声明**（如「- 自测脚本：新增 xx 反证用例」）。

   示例：

   ```
   fix: 投放队列卡死在轮询中

   - 端口探测失败后未设置重试上限
   - 队列恢复后重复提交同一任务
   - 自测脚本：补端口段反证用例
   ```

6. **记录非平凡决策。** 将设计选择、兼容约束和真实踩坑写入 `docs/internal/spec-notes.md`，按全局编号续写。
7. **未经确认不引入依赖。** 确需引入时，在提交信息和决策台账中说明包数、体积及是否属于运行时依赖。
8. **注释只写核心信息。** 新增或修改的注释，只写跨文件契约、易踩坑、反直觉处；不写长篇大论，不复述代码。公开 API 用 `///` doc comment。
9. **避免长链内联三元。** 多层条件表达式改为具名变量或早返回函数。
10. **不重复造轮子，且组件选型有明确优先级。** 写新 Widget、新工具、新命令前，按顺序取用：

    1. **`lib/shared/` 的既有实现**（首选）—— 按钮 `AppButton`（`kButtonRadius`）、
       下拉 `AppDropdownMenu`、三态 `SkeletonBox`/`SkeletonRows`/`SkeletonCards` +
       `EmptyState` + `ErrorState`、`AppPager` / `AppCheckbox` / `AppSwitch` / `AppSelect` /
       `AppTable` / `AppTitleBar` / `LogBox` / `Toast` / `NavRail` / `SettingRow`、
       设计令牌 `AppTokens` / `AppPalette`；
    2. **扩展既有实现**（次选）—— 缺变体就往共享件里加参数/枚举，不另起一套；
    3. **Material 3 组件**（再次）—— 共享层确实没有同类能力时用 Flutter 官方 M3
       （如 `MenuAnchor`），并按项目 token 覆写样式（圆角/配色/字号）；
    4. **自绘**（最后手段）—— 前三级都满足不了才自己画，且必须写清为何不能用前三级。

    **判定口径**：页面里出现 `class _XxxButton`、`class _XxxMenu`、`Container` 手搓按钮
    这类"局部轮子"，视为违反本条。按钮圆角一律取 `shared/buttons.dart` 的 `kButtonRadius`，
    如需不同圆角必须先改常量（不是在各调用点覆盖）。
11. **遵循既有命名与分层。** 不恢复已退役实现，不绕过现有模块边界或检查入口。
12. **拆屏判据。** `build()` 超过约 100 行或 Widget 嵌套超过 4 层时，必须拆成独立 Widget 类；拆分方向是横向（`Row` / `Column` 的区块各拆一个），返回 Widget 的私有方法视为拆分未完成。
13. **取数判据。** 状态用 `ref.watch` 在 `build` 顶层取，不在 UI 树里包 Consumer / builder 取数；派生数据（过滤 / 分组 / 排序）在 controller 或 selector 算好，`build` 只画。

## 5. 常用检查命令

工程骨架建立后（`flutter create` 按 §3 分层初始化），以下为日常入口：

```bash
# Dart 格式与静态检查（formatter page_width 120）
dart format --set-exit-if-changed .
flutter analyze

# 依赖与代码生成（freezed / json_serializable / riverpod_generator）
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# 国际化词条生成（gen_l10n，配置见 l10n.yaml；生成物不入库）
flutter gen-l10n

# 单元与 widget 测试
flutter test

# 端到端集成测试
flutter test integration_test

# 运行与构建（桌面全功能；iOS / Android / Web 不含本地服务）
flutter run -d macos
flutter build macos   # windows / linux / ios / android / web 同理

# 服务（Dart，workspace 内直接运行）
dart run services/mangasvc/bin/mangasvc.dart

# 服务发布编译（不支持交叉编译，每个目标平台各自编译）
dart compile exe services/mangasvc/bin/mangasvc.dart -o build/mangasvc
```

- 生成代码（`*.g.dart` / `*.freezed.dart` / `lib/l10n/app_localizations*.dart`）不入库；提交前以 build_runner 后无 diff 为准。
- Flutter SDK 版本用 fvm（或 puro）锁定，不依赖全局版本。
- 测试怎么写、什么改动该不该写测试：`docs/internal/test-policy.md`（建档后生效）。

## 6. 开工与交付清单

开始前：
- [ ] 检查 `git status`、`git log -1`，确认当前分支、工作区和并发改动。
- [ ] 确认改动所属层（`lib/` 的 app / core / features / shared、`services/`、`packages/protocol/`、测试），复用现有组件、状态与 IPC 边界。
- [ ] 阅读相关实现、测试和决策记录，不只依赖本文件摘要。

完成前：
- [ ] 更新受影响的代码、断言、路由表和文档路径。
- [ ] 对新增或修改的断言执行正向与反证验证。
- [ ] 运行与改动范围匹配的检查（至少 format + analyze + test）；未执行的真机验证必须明确标注。
- [ ] 将非平凡决策写入台账，并按约定拆分提交。
