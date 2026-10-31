import '../../l10n/app_localizations.dart';

/// 视图 id → ARB 文案（侧栏视图组与工具条面包屑共用同一份映射）。
///
/// 放在 `app/shell/` 而非 `shared/`：它依赖 [AppLocalizations]，属壳层装配件；
/// 业务域不应各自维护自己的视图名。
String viewLabel(AppLocalizations l10n, String id) => switch (id) {
  'drop' => l10n.viewDrop,
  'queue' => l10n.viewQueue,
  'library' => l10n.viewLibrary,
  'notready' => l10n.viewNotready,
  'discover' => l10n.viewDiscover,
  'playlist' => l10n.viewPlaylist,
  'local' => l10n.viewLocal,
  'history' => l10n.viewHistory,
  _ => id,
};

/// 模块序号 → ARB 文案（0 漫画翻译 / 1 音乐 / 2 番剧）。
String moduleLabel(AppLocalizations l10n, int index) => switch (index) {
  0 => l10n.navManga,
  1 => l10n.navMusic,
  _ => l10n.navAnime,
};
