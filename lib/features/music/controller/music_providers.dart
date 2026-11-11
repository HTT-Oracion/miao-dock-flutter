import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/demo_music_repository.dart';
import '../data/music_repository.dart';
import '../data/platform_music_repository.dart';
import '../domain/music_models.dart';
import 'music_auth.dart';
import 'music_session.dart';

/// 数据源模式：演示数据（离线可跑，覆盖设计稿全部状态）/ 真实平台接口。
///
/// 默认演示：四平台接口是**第三方站点**，无网络或接口风控时整页都不可用；
/// 演示模式保证 UI 与状态自测不依赖外网。切到线上后按当前音源建仓库。
enum MusicSourceMode { demo, online }

class MusicSourceModeNotifier extends Notifier<MusicSourceMode> {
  @override
  MusicSourceMode build() => MusicSourceMode.demo;

  void set(MusicSourceMode mode) => state = mode;
}

final musicSourceModeProvider = NotifierProvider<MusicSourceModeNotifier, MusicSourceMode>(MusicSourceModeNotifier.new);

/// 仓库装配：演示模式 → [DemoMusicRepository]；线上模式 → 按当前音源建
/// [PlatformMusicRepository]（切音源即换仓库，队列不清空，见 N04 边界）。
final musicRepositoryProvider = Provider<MusicRepository>((ref) {
  if (ref.watch(musicSourceModeProvider) == MusicSourceMode.demo) return DemoMusicRepository();
  final account = ref.watch(musicAccountProvider);
  final cookie = ref.watch(musicAuthProvider).cookieOf(account.cur) ?? '';
  return PlatformMusicRepository(platform: account.cur, cookie: cookie);
});

/// 演示仓库的强类型别名（供需要 Demo 特有动作的调用方窄化）。
///
/// 线上模式下没有演示数据可改（导入 / 清空是本地列表动作），按需回落一个
/// 独立演示实例，避免调用点因类型转换崩溃。
final demoMusicRepositoryProvider = Provider<DemoMusicRepository>((ref) {
  final repo = ref.watch(musicRepositoryProvider);
  return repo is DemoMusicRepository ? repo : DemoMusicRepository();
});

/// 红心种子（播放器初始 likedIds；演示口径：s1/s5/s7/s10 已红心）。
final likedSeedsProvider = Provider<Set<String>>((ref) => const {'s1', 's5', 's7', 's10'});

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
  const MusicSearchState({this.query = '', this.songs = const [], this.playlists = const [], this.searched = false});
  final String query;
  final List<MusicSong> songs;
  final List<MusicPlaylist> playlists;
  final bool searched;

  bool get hasResults => songs.isNotEmpty || playlists.isNotEmpty;

  MusicSearchState copyWith({String? query, List<MusicSong>? songs, List<MusicPlaylist>? playlists, bool? searched}) =>
      MusicSearchState(
        query: query ?? this.query,
        songs: songs ?? this.songs,
        playlists: playlists ?? this.playlists,
        searched: searched ?? this.searched,
      );
}

class SearchNotifier extends Notifier<MusicSearchState> {
  @override
  MusicSearchState build() => const MusicSearchState();

  Future<void> submit(String keyword) async {
    state = state.copyWith(query: keyword, searched: true);
    if (keyword.trim().isEmpty) {
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
  Future<List<MusicSong>> build() async => ref.watch(musicRepositoryProvider).localTracks();

  Future<void> _patch() async {
    try {
      state = AsyncData(await ref.read(demoMusicRepositoryProvider).localTracks());
    } on Object catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> importNames(List<String> names) async {
    ref.read(demoMusicRepositoryProvider).addLocalTracks(names);
    _patch();
  }

  /// 清空本地列表（不删文件，N25）：返回快照供撤销。
  Future<List<MusicSong>> clearKeepSnapshot() async {
    final snapshot = List<MusicSong>.of(await ref.read(demoMusicRepositoryProvider).localTracks());
    ref.read(demoMusicRepositoryProvider).clearLocal();
    _patch();
    return snapshot;
  }

  void restore(List<MusicSong> snapshot) {
    ref.read(demoMusicRepositoryProvider).addLocalTracks([for (final s in snapshot) s.title]);
    _patch();
  }
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
