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

