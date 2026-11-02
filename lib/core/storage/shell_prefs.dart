import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 壳层偏好持久化 —— 对应原项目 `src/stores/shell-prefs.ts`。
///
/// 只落一个布尔，故不引入 `shared_preferences`（未登记依赖，见
/// `docs/internal/third-party-packages.md` §纪律 1）；用 `dart:io` 写单文件。
///
/// 存储形态刻意沿用原项目的窄枚举（`'1'` / `'0'`）而非 JSON：
/// 「没写过」必须回落到界面既有形态（显示标签），否则升级后侧栏会凭空少一行字。
/// 缺键、空串、损坏内容一律按「没写过」处理。
const String _kSidebarLabelsKey = 'miao.sidebar-labels';
const String _kThemeModeKey = 'miao.theme-mode';
const String _kTranslateSourceKey = 'miao.translate-source';
const String _kEngineDirKey = 'miao.engine-dir';
const String _kAutoStartEngineKey = 'miao.auto-start-engine';

/// 已解析的偏好目录：移动端由 [ensureShellPrefsLoaded] 经 path_provider 取得
/// （Android 没有稳定 `$HOME`，`Directory.systemTemp.parent` 实测指向 `/`，
/// 写盘必然失败——用户实测「连接成功但保存失败」即此因）；null = 未预热，
/// 回落桌面端的 HOME 推导。
String? _resolvedDir;

/// 启动时预热：移动端先取应用支持目录再读文件进内存；
/// 桌面端路径是同步可得的，只需预热内存缓存。必须在 `runApp` 之前 await。
Future<void> ensureShellPrefsLoaded() async {
  if (kIsWeb) return;
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final support = await getApplicationSupportDirectory();
      _resolvedDir = '${support.path}/miao-dock-flutter';
      debugPrint('[prefs] dir=$_resolvedDir');
    } catch (e) {
      // 🔴 热重载/热重启不会注册新加的原生插件——path_provider 要完整重编才有。
      debugPrint('[prefs] 目录解析失败（若刚加 path_provider，请完整 flutter run 重编）：$e');
      return;
    }
  }
  _readPrefs();
  debugPrint('[prefs] 预热完成，键=${_memoryPrefs?.keys.toList()}');
}

/// 偏好文件路径：移动端用预热目录，桌面端基于 `$HOME`（macOS 与 Windows 用
/// Application Support、Linux 用 `.config`；Windows 走 `LOCALAPPDATA`）。
File _prefsFile() {
  final resolved = _resolvedDir;
  if (resolved != null) return File('$resolved/shell-prefs.json');
  final env = Platform.environment;
  final home = env['HOME'] ?? '.';
  // 路径一律基于 `HOME`：macOS 启用 App Sandbox 时，沙箱内 `HOME` 本身就是容器目录
  // （`~/Library/Containers/<bundle-id>/Data`），因此这条路径沙箱内外都合法，
  // 不需要为沙箱单独分支。
  final String dir;
  if (Platform.isWindows) {
    dir = '${env['LOCALAPPDATA'] ?? env['APPDATA'] ?? '.'}\\miao-dock-flutter';
  } else if (Platform.isMacOS) {
    dir = '$home/Library/Application Support/miao-dock-flutter';
  } else {
    dir = '$home/.config/miao-dock-flutter';
  }
  return File('$dir/shell-prefs.json');
}

/// 同步读偏好（启动首帧要用，不能异步）。
///
/// 失败一律回落空表：偏好读不到只影响观感，不该让应用起不来。
Map<String, String>? _memoryPrefs;

Map<String, String> _readPrefs() {
  final memory = _memoryPrefs;
  if (memory != null) return Map<String, String>.of(memory);
  if (kIsWeb) return const {};
  try {
    final file = _prefsFile();
    if (!file.existsSync()) return _memoryPrefs = <String, String>{};
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return _memoryPrefs = <String, String>{};
    return Map<String, String>.of(_memoryPrefs = {for (final e in decoded.entries) '${e.key}': '${e.value}'});
  } catch (_) {
    return _memoryPrefs = <String, String>{};
  }
}

/// 写偏好：先建目录再写；失败静默（下次启动回落到默认值）。
bool _writePref(String key, String value) {
  final prefs = {..._readPrefs(), key: value};
  _memoryPrefs = prefs;
  if (kIsWeb) return false;
  try {
    final file = _prefsFile();
    if (!file.existsSync()) file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(prefs), flush: true);
    return true;
  } catch (_) {
    // 偏好非关键路径，写失败不阻断交互。
    return false;
  }
}

/// 侧栏是否显示文字标签（原项目 `initialSidebarLabels`）：默认 true。
///
/// 语义与其他偏好一致：只有明确写过 `'0'` 才是关。
class SidebarLabelsNotifier extends Notifier<bool> {
  @override
  bool build() => _readPrefs()[_kSidebarLabelsKey] != '0';

  void set(bool on) {
    state = on;
    _writePref(_kSidebarLabelsKey, on ? '1' : '0');
  }

  void toggle() => set(!state);
}

final sidebarLabelsProvider = NotifierProvider<SidebarLabelsNotifier, bool>(SidebarLabelsNotifier.new);

/// 主题模式的持久化读写（与 `themeModeProvider` 配对；原项目存 `localStorage`）。
String readPersistedThemeMode() => _readPrefs()[_kThemeModeKey] ?? 'dark';

void persistThemeMode(String mode) => _writePref(_kThemeModeKey, mode);

/// 翻译来源（`local` / `llm` / `remote`）；null = 没写过，由平台默认决定。
///
/// 缺键时返回 null 而**不是** `'local'`：移动端要回落到 `remote`，
/// 硬编码默认值会让移动端拿到不可用的本地来源。
String? readTranslateSource() {
  final v = _readPrefs()[_kTranslateSourceKey];
  if (v == null || v.isEmpty) return null;
  return v;
}

void persistTranslateSource(String source) => _writePref(_kTranslateSourceKey, source);

/// 引擎目录（用户选过的安装/导入位置）；null = 用默认值。
///
/// 🔴 存的是**字符串路径**而不是布尔值：目录必须可搬可导入（D-027），
/// 记不住路径就等于每次启动都回到默认位置，「导入」白做。
String? readEngineDir() {
  final v = _readPrefs()[_kEngineDirKey];
  if (v == null || v.isEmpty) return null;
  return v;
}

void persistEngineDir(String dir) => _writePref(_kEngineDirKey, dir);

/// 「启动应用时自动起引擎」（design.html 默认「开」）。
///
/// 缺键返回 true：设计稿的默认值就是开，用户没动过就按开处理。
bool readAutoStartEngine() {
  final v = _readPrefs()[_kAutoStartEngineKey];
  if (v == null) return true;
  return v == 'true';
}

void persistAutoStartEngine(bool value) => _writePref(_kAutoStartEngineKey, value ? 'true' : 'false');

/// 远程服务地址（`域名:端口` 或完整 URL）；null = 未配置。
///
/// 远程模式（手机 / 插件 / Web）用它连桌面端：本机不跑引擎，
/// 所有翻译都发生在**对面**那台已经启动引擎的机器上（D-045）。
String? readRemoteBaseUrl() {
  final v = _readPrefs()['miao.remote-base-url'];
  return (v == null || v.isEmpty) ? null : v;
}

bool persistRemoteBaseUrl(String url) => _writePref('miao.remote-base-url', url);

/// 远程令牌。远程连接必须带令牌，否则等于把桌面端暴露给同网段任何人。
String? readRemoteToken() {
  final v = _readPrefs()['miao.remote-token'];
  return (v == null || v.isEmpty) ? null : v;
}

bool persistRemoteToken(String token) => _writePref('miao.remote-token', token);

/// 阅读器是否显示原图（false = 显示译文，默认）。
///
/// 用户要求：进阅读器**默认看译文**，点按钮才切原图；该偏好需持久化。
bool readReaderShowOriginal() => _readPrefs()['miao.reader-show-original'] == 'true';

void persistReaderShowOriginal(bool value) => _writePref('miao.reader-show-original', value ? 'true' : 'false');
