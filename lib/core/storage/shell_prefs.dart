import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// 偏好文件路径（均基于 `$HOME`）：macOS 与 Windows 用 Application Support、
/// Linux 用 `.config`；Windows 走 `LOCALAPPDATA`。
File _prefsFile() {
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
Map<String, String> _readPrefs() {
  if (kIsWeb) return const {};
  try {
    final file = _prefsFile();
    if (!file.existsSync()) return const {};
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return const {};
    return {for (final e in decoded.entries) '${e.key}': '${e.value}'};
  } catch (_) {
    return const {};
  }
}

/// 写偏好：先建目录再写；失败静默（下次启动回落到默认值）。
void _writePref(String key, String value) {
  if (kIsWeb) return;
  try {
    final file = _prefsFile();
    if (!file.existsSync()) file.parent.createSync(recursive: true);
    final prefs = {..._readPrefs(), key: value};
    file.writeAsStringSync(jsonEncode(prefs));
  } catch (_) {
    // 偏好非关键路径，写失败不阻断交互。
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
