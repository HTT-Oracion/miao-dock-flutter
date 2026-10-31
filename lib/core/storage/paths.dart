/// 目录约定 —— 对齐原项目 `src-tauri/src/platform/paths.rs`（D-015）。
///
/// ## 两棵树，不能合并
/// ```
/// 用户成果（可备份、可当相册浏览、卸载不删）
///   ~/Pictures/MiaoDock Mangas/            漫画库根
///
/// 产品数据（卸载可清、不进用户视野）
///   <appData>/MiaoDock/
///     manga/
///       state/                             应用自产：令牌 / 队列 / 幂等表
///       engine/                            ★ 引擎目录：应用下载的一切都在这里
///         python/                            自带解释器 + site-packages（pip 依赖）
///         bin/llama/                         llama-server（按后端换内容）
///         src/                               引擎源码
///           models/                          引擎的模型根（结构遵从上游）
///             detection/ inpainting/ ocr/ fonts/
///             translators/nllb/              按需
///         llm/                               llama-server 加载的权重（Sakura）
///         .engine.json                       安装清单
///     anime/engine/
/// ```
///
/// 🔴 **engine/ 与 state/ 的边界**：engine/ 里全是「下载来的、可搬走、可分享」的资产；
/// state/ 里是「运行期自产」的状态。两者混放会让「导入别人的引擎目录」变成
/// 「顺便把别人的令牌也导进来」。
///
/// 🔴 原项目 `paths.rs` 有一条断言：「库是用户成果，不得藏进 appData」。
/// 把两者混成一个 `rootDir` 会导致：卸载器不知道哪些该删、备份时无法区分、
/// 用户想换库位置会连带把引擎搬走。
///
/// ## 环境变量覆盖（与原项目同名）
/// | 变量 | 作用 |
/// |---|---|
/// | `MIAO_ROOT` | 数据根（默认 `<appData>/MiaoDock`） |
/// | `MIAO_MANGA_LIBRARY_DIR` | 漫画库根（默认 `~/Pictures/MiaoDock Mangas`） |
/// | `MIAO_MANGA_RUNTIME_ROOT` | 引擎运行时根（默认 `<数据根>/manga/runtimes`） |
/// | `MIAO_MANGA_STATE_DIR` | 漫画服务状态目录（默认 `<数据根>/manga/state`） |
library;

import 'dart:io';

import 'package:protocol/protocol.dart';

/// 平台应用数据目录。
///
/// - macOS: `~/Library/Application Support`
/// - Windows: `%LOCALAPPDATA%`
/// - Linux: `~/.local/share`
String appDataDir() {
  final env = Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
  if (Platform.isMacOS) return '$home/Library/Application Support';
  if (Platform.isWindows) {
    final base = env['LOCALAPPDATA'];
    if (base != null && base.isNotEmpty) return base;
    return '$home\\AppData\\Local';
  }
  return '$home/.local/share';
}

String _home() {
  final env = Platform.environment;
  return env['HOME'] ?? env['USERPROFILE'] ?? '.';
}

String? _env(String key) {
  final v = Platform.environment[key];
  return (v == null || v.isEmpty) ? null : v;
}

/// 数据根：`<appData>/MiaoDock`（`MIAO_ROOT` 覆盖）。
///
/// 这是**产品数据树的家**，不是任何单个域的落点。
String dataRoot() => _env('MIAO_ROOT') ?? '${appDataDir()}${_sep()}MiaoDock';

/// 漫画域：状态目录（`<数据根>/manga/state`）。
///
/// 令牌与队列同居于此 —— 手工搬迁时要**整目录搬**：令牌一变，
/// 浏览器插件存的旧令牌全部 401。
String mangaStateDir() => _env('MIAO_MANGA_STATE_DIR') ?? '${dataRoot()}${_sep()}manga${_sep()}state';

/// 漫画域：**引擎目录**（`<数据根>/manga/engine`）。
///
/// 这是「应用下载的一切」的唯一根，**整体可搬移 / 可导入 / 可导出**。
/// 下载时默认定位到这里，但用户可改选别处（D-015 / D-027）。
String mangaEngineDir() => _env('MIAO_MANGA_ENGINE_DIR') ?? '${dataRoot()}${_sep()}manga${_sep()}engine';

/// 自带解释器目录（`<engine>/python`）。
///
/// 🔴 **不用 venv**：venv 的 `pyvenv.cfg` 记录绝对路径，目录一移动 `bin/python` 就断
/// （实测：`bad interpreter: No such file or directory`）；而自带 Python 移动后
/// `sys.prefix` 自动跟随、pip 与已装依赖照常可用（实测 numpy 2.4.6 导入正常）。
/// 「一个目录可搬」与 venv 互斥。
String enginePythonDir([String? engineDir]) => '${engineDir ?? mangaEngineDir()}${_sep()}python';

/// 引擎源码目录（`<engine>/src`）。
String engineSrcDir([String? engineDir]) => '${engineDir ?? mangaEngineDir()}${_sep()}src';

/// llama-server 目录（`<engine>/bin/llama`）。
///
/// 路径固定，换后端 = 替换该目录内容（后端记在 `.engine.json`）。
String engineLlamaDir([String? engineDir]) => '${engineDir ?? mangaEngineDir()}${_sep()}bin${_sep()}llama';

/// 引擎模型目录（`<engine>/src/models`，D-031）。
///
/// 🔴 **不能放 `<engine>/models`**：引擎的模型根是 `BASE_PATH/models`，
/// 而 `BASE_PATH = os.path.dirname(MODULE_PATH)` 就是 `src/`
/// （`utils/generic.py:25` + `utils/inference.py:94`）。
/// 命令行也**无法**指定 —— `--model-dir` 只加在顶层 `g_parser`，
/// 子命令 `ws` / `shared` 没继承（`args.py`），启动链路也不传（`server/main.py:244`）。
/// 放错位置的症状是「引擎起来了但去别处找模型」，静默卡住或走联网下载。
///
/// 内部结构仍遵从上游：`detection/` `inpainting/` `ocr/` `fonts/` `translators/nllb/`。
String engineModelsDir([String? engineDir]) => '${engineSrcDir(engineDir)}${_sep()}models';

/// llama-server 加载的权重目录（`<engine>/llm`）。
///
/// 🔴 刻意**不放在 `models/` 下**：`models/` 是 MIT 的领地，结构要能原样对照上游文档；
/// Sakura 是 llama-server 的资产，MIT 一行代码都不读它（`SakuraTranslator` 只是 HTTP 客户端）。
/// 混放会让「升级引擎」与「我们的资产」互相牵制。
String engineLlmDir([String? engineDir]) => '${engineDir ?? mangaEngineDir()}${_sep()}llm';

/// 安装清单（`<engine>/.engine.json`）：版本 / 后端 / 各部件校验 / 时间。
String engineManifestPath([String? engineDir]) => '${engineDir ?? mangaEngineDir()}${_sep()}.engine.json';

/// 引擎解释器可执行文件路径。
///
/// 🔴 两个平台布局不同：python-build-standalone 在 Windows 上是**完整安装**
/// （`python/python.exe`），不是 venv 的 `Scripts/python.exe`。
String enginePythonPath([String? engineDir]) {
  final root = enginePythonDir(engineDir);
  return Platform.isWindows ? '$root${_sep()}python.exe' : '$root${_sep()}bin${_sep()}python3';
}

/// 漫画作品库根（**用户成果**）：`~/Pictures/MiaoDock Mangas`。
///
/// 🔴 刻意**不**挂进数据根：这是用户可见、可备份、可当相册管理的成果目录。
String mangaLibraryDir() {
  final override = _env('MIAO_MANGA_LIBRARY_DIR');
  if (override != null) return override;
  return '${_home()}${_sep()}Pictures${_sep()}MiaoDock Mangas';
}

/// 超长路径前缀（Windows）。
///
/// 🔴 Windows 的 `MAX_PATH` 是 260；nllb 的 HF cache 路径
/// （`models/translators/nllb/models--facebook--nllb-200-distilled-600M/blobs/<64位sha>`）
/// 叠加 `%LOCALAPPDATA%` 后逼近上限。加 `\\?\` 前缀可绕过。
/// 其他平台原样返回 —— 不要到处判断平台，统一走这里。
String longPath(String path) {
  // 逻辑在协议包里（纯字符串、可测），这里只补「绝对化」这一步。
  return longPathOf(File(path).absolute.path, isWindows: Platform.isWindows);
}

String _sep() => Platform.pathSeparator;
