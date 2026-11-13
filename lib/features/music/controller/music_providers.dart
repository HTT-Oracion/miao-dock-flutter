import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/music_repository.dart';
import '../data/sources/js/quickjs_music_source_engine.dart';
import '../data/sources/js/music_source_import.dart';
import '../domain/js_music_source.dart';
import '../domain/music_source_engine.dart';
import '../data/sources/js_music_source_adapter.dart';
import '../data/platform_music_repository.dart';
import '../domain/music_models.dart';
import '../domain/music_platform_info.dart';
import 'music_auth.dart';
import 'music_player.dart';
import 'music_session.dart';

/// 已导入且可用的 JS 音乐源覆盖的平台集合。
///
/// 🔴 音乐模块的平台清单**只认 JS 源**（与漫画源同口径）：内置 Dart 实现
/// 已导入且可用的 JS 音乐源的**平台描述符**（顺序 = 源注册表顺序，即用户导入
/// / 目录清单顺序）。
///
/// 🔴 音乐模块的平台清单**只认 JS 源**（与漫画源同口径）：内置 Dart 实现
/// 仅作为删除前的兼容保留，不再出现在任何平台选择 UI 里；未导入源时
/// 发现 / 我的呈现导入引导，而不是悄悄回退内置实现。
///
/// 描述符三层兜底：源声明（logo / color）→ 内置品牌（四平台 label/色）→ id 派生。
final musicPlatformInfosProvider = Provider<List<MusicPlatformInfo>>((ref) {
  final infos = <MusicPlatformInfo>[];
  for (final source in ref.watch(jsMusicSourceRegistryProvider)) {
    if (!source.isAvailable) continue;
    if (infos.any((i) => i.id == source.platformId)) continue;
    var info = source.info;
    final brand = platformBrands[info.id];
    if (brand != null) {
      info = info.copyWith(label: brand.label, color: brand.color, builtIn: true);
    } else {
      info = info.copyWith(color: info.color ?? derivedPlatformColor(info.id));
    }
    infos.add(info);
  }
  return infos;
});

/// 仓库装配：按当前音源接 JS 源；该平台没有已导入源时返回 stub 仓库
/// （UI 在空态层拦截，stub 只是兜底防止误调用）。
final musicRepositoryProvider = Provider<MusicRepository>((ref) {
  final account = ref.watch(musicAccountProvider);
  final cookie = ref.watch(musicAuthProvider).cookieOf(account.cur) ?? '';
  JsMusicSource? jsSource;
  for (final candidate in ref.watch(jsMusicSourceRegistryProvider)) {
    if (candidate.isAvailable && candidate.platformId == account.cur) {
      jsSource = candidate;
      break;
    }
  }
  if (jsSource != null) {
    return PlatformMusicRepository(
      platformId: account.cur,
      cookie: cookie,
      source: JsMusicSourceAdapter(source: jsSource, engine: ref.watch(musicSourceEngineProvider), cookie: cookie),
    );
  }
  return PlatformMusicRepository(platformId: account.cur, cookie: cookie);
});

/// QuickJS 音乐源引擎单例：runtime 创建成本高，跨仓库重建共享。
final musicSourceEngineProvider = Provider<MusicSourceEngine>((ref) {
  final engine = QuickJsMusicSourceEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// 已安装的 JS 音乐源注册表（启动时枚举落盘包；导入 / 卸载后 refresh）。
final jsMusicSourceRegistryProvider = NotifierProvider<JsMusicSourceRegistry, List<JsMusicSource>>(
  JsMusicSourceRegistry.new,
);

class JsMusicSourceRegistry extends Notifier<List<JsMusicSource>> {
  @override
  List<JsMusicSource> build() => MusicSourceImporter().installedSources();

  void refresh() => state = MusicSourceImporter().installedSources();
}

/// 收藏集合由真实账号同步前保持为空，不预置演示歌曲。
final likedSeedsProvider = Provider<Set<String>>((ref) => const {});

/// 当前曲目的歌词（**会自动随歌词加载完成而刷新**）。
///
/// 🔴 为什么不能直接用 `musicRepositoryProvider.lyricsFor(song)`：
/// 真实音源的歌词是异步预取的，`lyricsFor` 只是同步读缓存。缓存填好之后仓库本身
/// 没有任何状态变化，UI 不会重建 —— 表现就是「歌词一直是空轴」/「点了『译』没反应」。
/// 这里显式依赖 `playerProvider.lyricsRevision`，歌词一落缓存就重新求值。
final currentLyricsProvider = Provider<SongLyrics>((ref) {
  final song = ref.watch(playerProvider.select((s) => s.current));
  // 版本号参与依赖：值本身不用，但变化会触发本 provider 重算。
  ref.watch(playerProvider.select((s) => s.lyricsRevision));
  if (song == null) return const SongLyrics(lines: []);
  return ref.watch(musicRepositoryProvider).lyricsFor(song);
});

// ── 发现页各分区（加载 / 失败 / 空三态，AsyncValue 直达 UI）──────────────────

class _RecCardsNotifier extends AsyncNotifier<List<MusicRecCard>> {
  @override
  Future<List<MusicRecCard>> build() async => ref.watch(musicRepositoryProvider).recCards();
}

class _RecPlaylistsNotifier extends AsyncNotifier<List<MusicPlaylist>> {
  @override
  Future<List<MusicPlaylist>> build() async => ref.watch(musicRepositoryProvider).recommendedPlaylists();
}

class _ChartsNotifier extends AsyncNotifier<List<MusicChart>> {
  @override
  Future<List<MusicChart>> build() async => ref.watch(musicRepositoryProvider).charts();
}

/// 每日推荐：未登录返回空集（UI 呈现登录 CTA 卡，不是错误态）。
class _DailyNotifier extends AsyncNotifier<List<MusicSong>> {
  @override
  Future<List<MusicSong>> build() async {
    if (!ref.watch(musicAccountProvider).logged) return const [];
    return ref.watch(musicRepositoryProvider).dailySongs();
  }
}

final recCardsProvider = AsyncNotifierProvider<_RecCardsNotifier, List<MusicRecCard>>(_RecCardsNotifier.new);
final recPlaylistsProvider = AsyncNotifierProvider<_RecPlaylistsNotifier, List<MusicPlaylist>>(
  _RecPlaylistsNotifier.new,
);
final chartsProvider = AsyncNotifierProvider<_ChartsNotifier, List<MusicChart>>(_ChartsNotifier.new);
final dailySongsProvider = AsyncNotifierProvider<_DailyNotifier, List<MusicSong>>(_DailyNotifier.new);

/// 详情数据（歌单 / 榜单 / 每日推荐共用）。family 参数用 record，值语义自带相等性。
typedef MusicSourceRef = (MusicSourceKind, String);

final sourceDetailProvider = FutureProvider.autoDispose
    .family<({MusicPlaylist meta, List<MusicSong> songs}), MusicSourceRef>((ref, refId) {
      final (kind, id) = refId;
      return ref.watch(musicRepositoryProvider).sourceDetail(kind, id);
    });

// ── 搜索（N06：输入即分组返回单曲 / 歌单）────────────────────────────────────

@immutable
class MusicSearchState {
  const MusicSearchState({
    this.query = '',
    this.songs = const [],
    this.playlists = const [],
    this.recent = const [],
    this.searched = false,
  });
  final String query;
  final List<MusicSong> songs;
  final List<MusicPlaylist> playlists;
  final List<String> recent;
  final bool searched;

  bool get hasResults => songs.isNotEmpty || playlists.isNotEmpty;

  MusicSearchState copyWith({
    String? query,
    List<MusicSong>? songs,
    List<MusicPlaylist>? playlists,
    List<String>? recent,
    bool? searched,
  }) => MusicSearchState(
    query: query ?? this.query,
    songs: songs ?? this.songs,
    playlists: playlists ?? this.playlists,
    recent: recent ?? this.recent,
    searched: searched ?? this.searched,
  );
}

class SearchNotifier extends Notifier<MusicSearchState> {
  @override
  MusicSearchState build() => const MusicSearchState();

  Future<void> submit(String keyword) async {
    final value = keyword.trim();
    final recent = value.isEmpty
        ? state.recent
        : [value, ...state.recent.where((item) => item != value)].take(8).toList();
    state = state.copyWith(query: keyword, recent: recent, searched: true);
    if (value.isEmpty) {
      state = state.copyWith(songs: const [], playlists: const []);
      return;
    }
    try {
      final r = await ref.read(musicRepositoryProvider).search(keyword);
      state = state.copyWith(songs: r.songs, playlists: r.playlists);
    } on MusicRepositoryException {
      state = state.copyWith(songs: const [], playlists: const []);
      rethrow;
    }
  }

  void clear() => state = const MusicSearchState();
}

final musicSearchProvider = NotifierProvider<SearchNotifier, MusicSearchState>(SearchNotifier.new);

// ── 本地音乐（导入 / 清空带撤销）──────────────────────────────────────────────

class _LocalNotifier extends AsyncNotifier<List<MusicSong>> {
  @override
  Future<List<MusicSong>> build() async => const [];

  Future<void> importNames(List<String> names) async {
    final current = state.value ?? const <MusicSong>[];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final additions = <MusicSong>[
      for (final (index, raw) in names.indexed)
        MusicSong(
          id: 'local-$stamp-$index',
          title: raw.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          artist: '',
          album: '',
          duration: Duration.zero,
          platformId: 'local',
        ),
    ];
    state = AsyncData([...current, ...additions]);
  }

  /// 清空本地列表（不删文件，N25）：返回快照供撤销。
  Future<List<MusicSong>> clearKeepSnapshot() async {
    final snapshot = List<MusicSong>.of(state.value ?? const []);
    state = const AsyncData([]);
    return snapshot;
  }

  void restore(List<MusicSong> snapshot) => state = AsyncData(snapshot);
}

final musicLocalProvider = AsyncNotifierProvider<_LocalNotifier, List<MusicSong>>(_LocalNotifier.new);

// ── 播放历史（播放器追加 / 清空带撤销；按今天·昨天·更早分组）─────────────────

class _HistoryNotifier extends AsyncNotifier<List<MusicHistoryEntry>> {
  @override
  Future<List<MusicHistoryEntry>> build() async => ref.watch(musicRepositoryProvider).history();

  /// 播放器切曲时追加（同一首 10 分钟内去重，避免快进退重复记录）。
  void append(MusicSong song) {
    final current = state.value;
    if (current == null) return;
    if (current.isNotEmpty && current.first.song.id == song.id) return;
    state = AsyncData([MusicHistoryEntry(song: song, playedAt: DateTime.now()), ...current]);
  }

  /// 清空（N26）：不弹二次确认，撤销由 UI 走 [restore]。
  List<MusicHistoryEntry> clearKeepSnapshot() {
    final snapshot = List<MusicHistoryEntry>.of(state.value ?? const []);
    state = AsyncData(const []);
    return snapshot;
  }

  void restore(List<MusicHistoryEntry> snapshot) => state = AsyncData(snapshot);
}

final historyFeedProvider = AsyncNotifierProvider<_HistoryNotifier, List<MusicHistoryEntry>>(_HistoryNotifier.new);

/// 历史分组（今天 / 昨天 / 更早）。分组键 0/1/2 供 UI 排序与 ARB 映射。
enum HistoryGroup { today, yesterday, earlier }

HistoryGroup historyGroupOf(DateTime playedAt, DateTime now) {
  final day = DateTime(playedAt.year, playedAt.month, playedAt.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  return diff <= 0 ? HistoryGroup.today : (diff == 1 ? HistoryGroup.yesterday : HistoryGroup.earlier);
}
