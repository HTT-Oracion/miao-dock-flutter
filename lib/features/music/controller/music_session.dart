import 'dart:async' show unawaited;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/js_music_source.dart';
import '../domain/music_models.dart';
import '../domain/music_source_engine.dart';
import 'music_providers.dart';
import 'music_auth.dart';

/// 账号与音源会话（设计稿 N04/N05/M10）。
///
/// 当前音源与真实 Cookie 登录状态。
@immutable
class MusicAccountState {
  const MusicAccountState({
    required this.cur,
    required this.logged,
    required this.nick,
    required this.extra,
    this.avatarUrl,
  });

  /// 当前平台 id（字符串身份，见 js_music_source.dart 的口径说明）。
  final String cur;

  /// 当前平台用户的头像地址（源 loginInfo 回读；null = 无头像，显示「?」占位）。
  final String? avatarUrl;
  final bool logged;
  final String? nick;

  /// 非当前平台的登录态（当前平台的登录态由 [logged] 表达）。
  final Map<String, bool> extra;

  static const initial = MusicAccountState(
    cur: 'netease',
    logged: false,
    nick: null,
    extra: {'qq': false, 'kugou': false, 'migu': false},
  );

  /// 平台徽标三态（core.js platBadge）：当前源 / 已登录 / 未登录。
  bool isLogged(String p) => p == cur ? logged : (extra[p] ?? false);

  /// 头像占位字：昵称首字符；空昵称 / 未登录兜底「?」。
  ///
  /// 🔴 为什么收敛在这里：`substring(0, 1)` 对空串抛
  /// `RangeError (end): Invalid value: Only valid value is 0: 0`——
  /// 登录已成功但昵称回读未完成 / 回读失败时 nick 就是空串（用户实测：
  /// 登录后发现页顶部整条红色错误横幅）。所有头像取首字的地方必须走本方法。
  String get avatarInitial => logged && (nick?.isNotEmpty ?? false) ? nick!.substring(0, 1) : '?';

  /// 头像旁的展示名：已登录显示昵称（可为空串，由 UI 兜底），未登录显示「未登录」由 UI 层取词条。
  String get displayName => logged ? (nick ?? '') : '';

  MusicAccountState copyWith({
    String? cur,
    bool? logged,
    String? nick,
    Map<String, bool>? extra,
    String? Function()? avatarUrl,
  }) => MusicAccountState(
    cur: cur ?? this.cur,
    logged: logged ?? this.logged,
    nick: nick ?? this.nick,
    extra: extra ?? this.extra,
    avatarUrl: avatarUrl != null ? avatarUrl() : this.avatarUrl,
  );
}

class MusicAccountNotifier extends Notifier<MusicAccountState> {
  String _current = 'netease';
  String? _nick;

  @override
  MusicAccountState build() {
    final auth = ref.watch(musicAuthProvider);
    // 🔴 当前平台默认取**第一个已导入源**（源体系口径）；
    // 之前写死 netease —— 只导入新平台时 cur 不在清单里，侧栏/徽章全失效。
    final infos = ref.watch(musicPlatformInfosProvider);
    if (infos.isNotEmpty && infos.any((i) => i.id == _current) == false) {
      _current = infos.first.id;
    }
    final logged = (auth.cookieOf(_current) ?? '').isNotEmpty;
    final state = MusicAccountState(
      cur: _current,
      logged: logged,
      nick: logged ? _nick : null,
      extra: {
        // 会话枚举退役：extra 由已导入源的平台集合填充（providers 侧）。
        for (final entry in auth.cookies.entries)
          if (entry.key != _current && entry.value.isNotEmpty) entry.key: true,
      },
    );
    // 🔴 Cookie 从 Keychain 恢复后昵称是空的（昵称只存内存）：不回读的话
    // 头像与右上角永远显示「?」，直到重新登录。
    if (logged && (state.nick?.isNotEmpty ?? false) == false && auth.loading == false) {
      unawaited(_restoreNick(_current, auth.cookieOf(_current) ?? ''));
    }
    return state;
  }

  /// 切音源：未登录 → 由 UI 拉起登录弹窗；已登录 → 直接切；已是当前源 → 不动（N04）。
  void switchPlatform(String p) {
    if (p == state.cur) return;
    final wasLogged = state.isLogged(p);
    _current = p;
    _nick = null;
    state = MusicAccountState(cur: p, logged: wasLogged, nick: null, extra: {...state.extra, state.cur: state.logged});
  }

  /// 接口出口（测试可替换）：JS 源引擎。
  @visibleForTesting
  MusicSourceEngine createEngine() => ref.read(musicSourceEngineProvider);

  /// 从 Keychain 恢复 Cookie 后补回昵称：走该平台 JS 源的 `loginInfo` 能力
  /// （Cookie 注入引擎 Cookie 罐后由源自行携带请求）。
  ///
  /// 源回「未登录」时同步撤下登录态：宁可显示未登录，
  /// 也不能「顶着 ? 的已登录」——那会让用户以为账号异常。
  /// 源未声明能力 / 无该平台源 / 网络失败：保持现状，下一轮再试。
  Future<void> _restoreNick(String p, String cookie) async {
    if (cookie.isEmpty) return;
    try {
      JsMusicSource? source;
      for (final candidate in ref.read(jsMusicSourceRegistryProvider)) {
        if (candidate.isAvailable && candidate.platformId == p) {
          source = candidate;
          break;
        }
      }
      if (source == null || source.capabilities.contains('loginInfo') == false) return;
      final engine = createEngine();
      await engine.setSessionCookie(source, cookie);
      final info = await engine.loginInfo(source);
      if (!ref.mounted) return;
      // 会话可能已切换平台或重新登录，只认当前平台的结果。
      if (p != _current) return;
      if (info == null) return;
      if (!info.loggedIn) {
        // Cookie 过期：撤下登录态并清掉失效凭据。
        _nick = null;
        state = MusicAccountState(cur: _current, logged: false, nick: null, extra: {...state.extra, _current: false});
        await ref.read(musicAuthProvider.notifier).clear(p);
        return;
      }
      state = state.copyWith(nick: info.nick.isNotEmpty ? info.nick : null, avatarUrl: () => info.avatarUrl);
    } on Object {
      // 网络失败：保持现状（已登录 + 「?」），下一轮再试。
    }
  }

  /// 登录成功（真实平台状态回读）。
  void login(String p, String nick, {String? avatarUrl}) {
    if (p == state.cur) {
      _nick = nick;
      state = state.copyWith(logged: true, nick: nick, avatarUrl: () => avatarUrl);
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

    this.loginPlatform = 'netease',
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
  final String loginPlatform;

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
    String? loginPlatform,
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
  void openLogin(String p) => state = state.copyWith(loginOpen: true, loginPlatform: p);
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
