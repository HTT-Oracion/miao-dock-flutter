# 贡献指南

开发环境、测试与提交流程。仓库的架构约束与工程纪律以 [`AGENTS.md`](AGENTS.md) 为准，本文只讲**怎么动手**。

## 一、搭建开发环境

### 依赖

| 用途 | 依赖 |
|---|---|
| 构建 UI / 服务 | Flutter SDK（用 [fvm](https://fvm.app) 锁定，见 `.fvmrc`）+ Dart 3.6+（pub workspace） |
| Git 钩子 | Dart 版 [husky](https://pub.dev/packages/husky)（`dart pub global activate husky`，一次性全局激活） |
| macOS 构建 | Xcode + CocoaPods |
| Windows 构建 | Visual Studio 2022 生成工具（「使用 C++ 的桌面开发」） |
| Linux 构建 | clang / cmake / GTK 开发库 |
| 真翻译引擎（可选） | Python 3.11 + manga-image-translator + 模型权重 —— **日常开发不需要**，见 §测试与替身 |

### 步骤

```bash
git clone <本仓库>
cd miao-dock-flutter

fvm install                                          # 安装锁定的 Flutter 版本
fvm flutter pub get                                  # workspace 依赖一次拉齐
fvm dart run build_runner build --delete-conflicting-outputs   # 生成代码
```

自检：`fvm flutter --version` 能出版本号、`fvm dart analyze` 无报错。

### 跑起来

```bash
fvm flutter run -d macos                              # 只跑 UI（默认连 A 级 Fake，无需服务进程）
fvm dart run services/mangasvc/bin/mangasvc.dart --engine mock   # 漫画服务（mock 引擎，无需 Python）
fvm dart run services/animesvc/bin/animesvc.dart      # 番剧服务
```

## 二、运行测试

| 层 | 命令 | 什么时候跑 |
|---|---|---|
| 服务与纯逻辑 | `fvm dart test`（在 `services/*`、`packages/*` 内，可加 `--watch`） | 改服务 / domain 层逻辑时 |
| 单元与 widget | `fvm flutter test` | 改 UI / controller 时 |
| 静态检查 | `fvm dart analyze` && `fvm dart format --set-exit-if-changed --output=none .` | 提交前必跑 |
| 端到端 | `fvm flutter test integration_test` | 涉及多进程 / 真实引擎的改动 |

**替身分级**：日常开发与绝大多数测试不依赖 Python——UI 用 `packages/protocol/` 的 Fake 客户端（A 级），服务自测用 `mangasvc --engine mock`（B 级）；真引擎（C 级）只用于联调与验收，不在常规测试里。

**断言纪律**（详见 `AGENTS.md` §4）：断言必须可反证——新增或修改断言时，说明「破坏什么会导致哪条断言失败」；禁止假绿与静默跳过。

## 三、提交规范

提交会过 **husky（Dart 版）的 pre-commit**：克隆后执行一次 `dart pub global activate husky && dart pub global run husky:husky install` 激活；之后每次提交前全仓 `dart format --set-exit-if-changed` + `dart analyze`（优先走 fvm 工具链；工程骨架建立前无 pubspec.yaml 时自动放行，允许纯文档提交）。

提交信息格式（**硬性**）：

```
refactor|chore|style|docs|fix: 中文标题

- 功能点描述
- 功能点描述
```

- 类型只用五个：`refactor`（行为不变）、`chore`（工具链 / 非代码）、`style`（纯格式化）、`docs`（文档）、`fix`（修缺陷）。
- 标题只能为中文；正文分点描述本次开发的功能，**每条不超过 50 字符**；不加 emoji、句号或文件清单。
- **改动了自测脚本必须在正文同步声明**（如「- 自测脚本：新增 xx 反证用例」）。
- 关键节点独立提交，不把多个不相关改动塞进一个提交。
- **未经确认不引入依赖**：确需引入时，在提交信息与决策台账中说明包数、体积及是否属于运行时依赖。

示例：

```
fix: 投放队列卡死在轮询中

- 端口探测失败后未设置重试上限
- 队列恢复后重复提交同一任务
- 自测脚本：补端口段反证用例
```

## 四、提交流程（PR）

1. **开工前**：从最新 `main` 拉出分支；确认改动所属层（`lib/` 各层 / `services/` / `packages/protocol/` / 测试），复用现有组件、状态与 IPC 边界；阅读相关实现与 `docs/internal/spec-notes.md` 的既有决策。
2. **开发中**：遵守 `AGENTS.md` §3 分层判据——`core/`、`shared/` 不 import `features/`，UI 不直接碰 dio / Process，DTO 统一从 `packages/protocol/` 导入，平台差异只在 `bootstrap.dart` 收口。
3. **提交前自查**：
   - [ ] `fvm dart analyze` 与 `dart format` 干净；生成代码（`*.g.dart` / `*.freezed.dart`）不入库，build_runner 后无 diff
   - [ ] 与改动范围匹配的测试通过；新增 / 修改的断言做过正反证
   - [ ] 新增 / 搬迁目录已同步 README 目录说明与 `AGENTS.md`
   - [ ] 非平凡决策已写入 `docs/internal/spec-notes.md`（D-001 起连续编号）
   - [ ] 提交信息符合第三节规范
4. **PR 描述**：写清做了什么、为什么、怎么验证的；未执行的真机验证要明确标注。
5. **评审**：评审者按 `AGENTS.md` §4 的纪律核对（覆盖实际依赖层、不重复造轮子、遵循既有命名与分层）；通过后 squash 或按提交规范合并。

## 五、行为准则

参与本项目即表示接受 [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)。
