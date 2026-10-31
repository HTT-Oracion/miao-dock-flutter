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
///       state/                             队列 / 令牌 / 隐藏清单
///       runtimes/                          引擎运行时（src + venv + models-store）
///     anime/runtimes/
/// ```
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

/// 漫画域：引擎运行时根（`<数据根>/manga/runtimes`）。
///
/// **下载时默认定位到这里**，但用户可以改选别处（见 D-015）。
String mangaRuntimeRoot() => _env('MIAO_MANGA_RUNTIME_ROOT') ?? '${dataRoot()}${_sep()}manga${_sep()}runtimes';

/// 引擎源码目录（`<runtimes>/src`）。
String engineSrcDir([String? runtimeRoot]) => '${runtimeRoot ?? mangaRuntimeRoot()}${_sep()}src';

/// 引擎解释器目录（`<runtimes>/venv`）。
String engineVenvDir([String? runtimeRoot]) => '${runtimeRoot ?? mangaRuntimeRoot()}${_sep()}venv';

/// 模型落盘目录：`<数据根>/manga/state/models-state`（D-016）。
///
/// ⚠️ **这是对原项目的刻意偏离**：原项目把 `models-store` 放在运行时根下
/// （`<runtimes>/models-store`，见 `model_status.rs` 的 `tmp.join("models-store")`）。
/// 现改挂到 `state/` 下 —— 模型被视为**状态资产**，与运行时解耦：
/// 换一个 runtimes 目录（导入本地 / 换盘）时，模型不必重下。
///
/// 因此本函数**不接受 runtimeRoot**：模型位置不随运行时走。
String modelsStoreDir() => _env('MIAO_MODELS_STORE_DIR') ?? '${mangaStateDir()}${_sep()}models-state';

/// 引擎解释器可执行文件路径。
String enginePythonPath([String? runtimeRoot]) {
  final venv = engineVenvDir(runtimeRoot);
  return Platform.isWindows ? '$venv${_sep()}Scripts${_sep()}python.exe' : '$venv${_sep()}bin${_sep()}python';
}

/// 漫画作品库根（**用户成果**）：`~/Pictures/MiaoDock Mangas`。
///
/// 🔴 刻意**不**挂进数据根：这是用户可见、可备份、可当相册管理的成果目录。
String mangaLibraryDir() {
  final override = _env('MIAO_MANGA_LIBRARY_DIR');
  if (override != null) return override;
  return '${_home()}${_sep()}Pictures${_sep()}MiaoDock Mangas';
}

/// 运行时目录结构是否像是一个引擎安装。
///
/// ⚠️ **这是浅检查，不是完整性校验**。完整的校验（版本匹配、模型齐全、
/// venv 可用）见 P0-F6d（已记账，后做）。
///
/// 返回缺失项的键（空 = 浅检查通过）。
List<String> inspectRuntimeDir(String runtimeRoot) {
  final dir = Directory(runtimeRoot);
  if (!dir.existsSync()) return const ['runtime-root'];

  final missing = <String>[];
  if (!Directory(engineSrcDir(runtimeRoot)).existsSync()) missing.add('src');
  if (!Directory(engineVenvDir(runtimeRoot)).existsSync()) missing.add('venv');
  // models-store 允许不存在（首次下载后再建），但 src / venv 必须有。
  return missing;
}

String _sep() => Platform.pathSeparator;
