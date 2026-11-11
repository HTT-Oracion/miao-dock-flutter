import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/music_models.dart';
import 'music_auth.dart';

/// 账号与音源会话（设计稿 N04/N05/M10）。
///
/// 当前音源与真实 Cookie 登录状态。
@immutable
class MusicAccountState {
  const MusicAccountState({required this.cur, required this.logged, required this.nick, required this.extra});

  final MusicPlatform cur;
  final bool logged;
  final String? nick;

  /// 非当前平台的登录态（当前平台的登录态由 [logged] 表达）。
  final Map<MusicPlatform, bool> extra;

  static const initial = MusicAccountState(
    cur: MusicPlatform.netease,
    logged: false,
    nick: null,
    extra: {MusicPlatform.qq: false, MusicPlatform.kugou: false, MusicPlatform.migu: false},
  );

  /// 平台徽标三态（core.js platBadge）：当前源 / 已登录 / 未登录。
  bool isLogged(MusicPlatform p) => p == cur ? logged : (extra[p] ?? false);

  MusicAccountState copyWith({MusicPlatform? cur, bool? logged, String? nick, Map<MusicPlatform, bool>? extra}) =>
      MusicAccountState(
        cur: cur ?? this.cur,
        logged: logged ?? this.logged,
        nick: nick ?? this.nick,
        extra: extra ?? this.extra,
      );
}

class MusicAccountNotifier extends Notifier<MusicAccountState> {
  MusicPlatform _current = MusicPlatform.netease;
  String? _nick;

  @override
  MusicAccountState build() {
    final auth = ref.watch(musicAuthProvider);
    final logged = (auth.cookieOf(_current) ?? '').isNotEmpty;
    return MusicAccountState(
      cur: _current,
      logged: logged,
      nick: logged ? _nick : null,
      extra: {
        for (final platform in MusicPlatform.values)
          if (platform != MusicPlatform.local && platform != _current)
            platform: (auth.cookieOf(platform) ?? '').isNotEmpty,
      },
    );
  }

  /// 切音源：未登录 → 由 UI 拉起登录弹窗；已登录 → 直接切；已是当前源 → 不动（N04）。
  void switchPlatform(MusicPlatform p) {
    if (p == state.cur) return;
    final wasLogged = state.isLogged(p);
    _current = p;
    _nick = null;
    state = MusicAccountState(cur: p, logged: wasLogged, nick: null, extra: {...state.extra, state.cur: state.logged});
  }

  /// 登录成功（真实平台状态回读）。
  void login(MusicPlatform p, String nick) {
    if (p == state.cur) {
      _nick = nick;
      state = state.copyWith(logged: true, nick: nick);
      return;
    }
    state = state.copyWith(extra: {...state.extra, p: true});
  }

  /// 退出当前源（N05）；退出后 chip 变「未登录」。
  Future<void> logout() async {
    final platform = state.cur;
    _nick = null;
    state = MusicAccountState(cur: state.cur, logged: false, nick: null, extra: state.extra);
    await ref.read(musicAuthProvider.notifier).clear(platform);
  }
}

final musicAccountProvider = NotifierProvider<MusicAccountNotifier, MusicAccountState>(MusicAccountNotifier.new);

/// 视图滚动位置记忆（N03）：切视图后回来恢复原滚动位置。
///
/// 音乐四视图是同分支下的四个路由，PageStorageBucket 跟着路由换，靠它取不到值；
/// 这里用屏级 Map<视图 id, offset> 记，视图在 dispose 时写回、重建后回填。
class MusicScrollMemoryNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  void save(String viewId, double offset) {
    if (state[viewId] == offset) return;
    state = {...state, viewId: offset};
  }
}

final musicScrollMemoryProvider = NotifierProvider<MusicScrollMemoryNotifier, Map<String, double>>(
  MusicScrollMemoryNotifier.new,
);

/// 「重复点击当前视图 → 回到顶部」信号（N03：省一次无意义重新请求）。
///
/// 用自增计数而不是布尔：同一视图连点两次也要能再滚一次。
class MusicScrollTopNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  void bump(String viewId) => state = {...state, viewId: (state[viewId] ?? 0) + 1};
}

final musicScrollTopProvider = NotifierProvider<MusicScrollTopNotifier, Map<String, int>>(MusicScrollTopNotifier.new);

/// 播放器样式（N17：现代 / 封面渐染 / 透明彩胶 / 音域回响 / 沉浸 / 通透）。
/// 「动态」开关只在现代样式出现（其余样式没有可动元素）。
final playerStyleProvider = NotifierProvider<PlayerStyleNotifier, PlayerStyle>(PlayerStyleNotifier.new);

class PlayerStyleNotifier extends Notifier<PlayerStyle> {
  @override
  PlayerStyle build() => PlayerStyle.modern;
  void set(PlayerStyle s) => state = s;
}

/// 音乐模块浮层与开关的集中 UI 态（对应设计稿全局 S 对象的浮层位）。
@immutable
class MusicUiState {
  const MusicUiState({
    this.searchOpen = false,
    this.queueOpen = false,
    this.immersiveOpen = false,
    this.islandOpen = false,
    this.accountMenuOpen = false,
    this.accountSheetOpen = false,
    this.loginOpen = false,

    this.loginPlatform = MusicPlatform.netease,
    this.songMenuSongId,
    this.qualitySheetOpen = false,
    this.styleSheetOpen = false,
    this.lyricsSettingsOpen = false,
    this.desktopLyricsOn = false,
    this.translateOn = true,
  });

  final bool searchOpen;
  final bool queueOpen;
  final bool immersiveOpen;
  final bool islandOpen;
  final bool accountMenuOpen;

  /// 移动端「账号与音源」抽屉（M10）。
  final bool accountSheetOpen;
  final bool loginOpen;
  final MusicPlatform loginPlatform;

  /// 歌曲行菜单当前曲目（右键 / 长按 / ⋯ 共用一份菜单，N23/M15）。
  final String? songMenuSongId;
  final bool qualitySheetOpen;
  final bool styleSheetOpen;
  final bool lyricsSettingsOpen;

  /// 桌面歌词开关与设置（N19：字号 16–40、高亮色、1/2 行；设置即时反映）。
  final bool desktopLyricsOn;

  /// 「译」翻译歌词显隐（N18/M13）。
  final bool translateOn;

  MusicUiState copyWith({
    bool? searchOpen,
    bool? queueOpen,
    bool? immersiveOpen,
    bool? islandOpen,
    bool? accountMenuOpen,
    bool? accountSheetOpen,
    bool? loginOpen,
    MusicPlatform? loginPlatform,
    String? songMenuSongId,
    bool clearSongMenu = false,
    bool? qualitySheetOpen,
    bool? styleSheetOpen,
    bool? lyricsSettingsOpen,
    bool? desktopLyricsOn,
    bool? translateOn,
  }) => MusicUiState(
    searchOpen: searchOpen ?? this.searchOpen,
    queueOpen: queueOpen ?? this.queueOpen,
    immersiveOpen: immersiveOpen ?? this.immersiveOpen,
    islandOpen: islandOpen ?? this.islandOpen,
    accountMenuOpen: accountMenuOpen ?? this.accountMenuOpen,
    accountSheetOpen: accountSheetOpen ?? this.accountSheetOpen,
    loginOpen: loginOpen ?? this.loginOpen,
    loginPlatform: loginPlatform ?? this.loginPlatform,
    songMenuSongId: clearSongMenu ? null : (songMenuSongId ?? this.songMenuSongId),
    qualitySheetOpen: qualitySheetOpen ?? this.qualitySheetOpen,
    styleSheetOpen: styleSheetOpen ?? this.styleSheetOpen,
    lyricsSettingsOpen: lyricsSettingsOpen ?? this.lyricsSettingsOpen,
    desktopLyricsOn: desktopLyricsOn ?? this.desktopLyricsOn,
    translateOn: translateOn ?? this.translateOn,
  );
}

class MusicUiNotifier extends Notifier<MusicUiState> {
  @override
  MusicUiState build() => const MusicUiState();

  void setSearch(bool v) => state = state.copyWith(searchOpen: v);
  void setQueue(bool v) => state = state.copyWith(queueOpen: v);
  void setImmersive(bool v) => state = state.copyWith(immersiveOpen: v);
  void setIsland(bool v) => state = state.copyWith(islandOpen: v);
  void setAccountMenu(bool v) => state = state.copyWith(accountMenuOpen: v);
  void setAccountSheet(bool v) => state = state.copyWith(accountSheetOpen: v);
  void openLogin(MusicPlatform p) => state = state.copyWith(loginOpen: true, loginPlatform: p);
  void closeLogin() => state = state.copyWith(loginOpen: false);
  void openSongMenu(String songId) => state = state.copyWith(songMenuSongId: songId);
  void closeSongMenu() => state = state.copyWith(clearSongMenu: true);
  void setQualitySheet(bool v) => state = state.copyWith(qualitySheetOpen: v);
  void setStyleSheet(bool v) => state = state.copyWith(styleSheetOpen: v);
  void setLyricsSettings(bool v) => state = state.copyWith(lyricsSettingsOpen: v);
  void setDesktopLyrics(bool v) => state = state.copyWith(desktopLyricsOn: v);
  void setTranslate(bool v) => state = state.copyWith(translateOn: v);
}

final musicUiProvider = NotifierProvider<MusicUiNotifier, MusicUiState>(MusicUiNotifier.new);

/// 账号菜单锚点（全局坐标，右下角）。
///
/// 为什么不用 `LayerLink` + `CompositedTransformFollower`：工具条的动作区在
/// `DragToMoveArea` 里，跟随者的坐标系与锚点不在同一合成层时会被落在左上角
/// （实测位置跑偏）。这里在点击时把胶囊的全局矩形记下来，菜单用 `Positioned`
/// 精确贴在胶囊下方，坐标可控、也方便夹在窗口内。
class MusicAccountAnchorNotifier extends Notifier<Rect?> {
  @override
  Rect? build() => null;

  void set(Rect? rect) => state = rect;
}

final musicAccountAnchorProvider = NotifierProvider<MusicAccountAnchorNotifier, Rect?>(MusicAccountAnchorNotifier.new);
