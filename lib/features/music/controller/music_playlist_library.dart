import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/music_repository.dart';
import '../domain/music_models.dart';
import 'music_providers.dart';
import 'music_session.dart';

/// 我的歌单库状态（设计稿 N41/N43/M18）。
///
/// 三件事必须跨视图保留（对齐 miao-dock 左栏）：两个分组的折叠态、
/// 收藏歌单的取消订阅、自建歌单的本地收藏回执。全部放控制器，UI 只读。
@immutable
class PlaylistLibraryState {
  const PlaylistLibraryState({
    this.createdCollapsed = false,
    this.collectedCollapsed = false,
    this.unsubscribed = const {},
    this.saved = const {},
  });

  final bool createdCollapsed;
  final bool collectedCollapsed;

  /// 已取消订阅的收藏歌单 id（只在屏级状态记，不改数据源，N43）。
  final Set<String> unsubscribed;

  /// 自建歌单 / 榜单的收藏回执（按 id；与收藏歌单的 subscribed 语义位分开）。
  final Set<String> saved;

  /// 详情页收藏按钮态：收藏歌单看 subscribed 语义位，自建歌单看本地回执。
  bool isSaved(MusicPlaylist p) => p.subscribed ? !unsubscribed.contains(p.id) : saved.contains(p.id);

  PlaylistLibraryState copyWith({
    bool? createdCollapsed,
    bool? collectedCollapsed,
    Set<String>? unsubscribed,
    Set<String>? saved,
  }) => PlaylistLibraryState(
    createdCollapsed: createdCollapsed ?? this.createdCollapsed,
    collectedCollapsed: collectedCollapsed ?? this.collectedCollapsed,
    unsubscribed: unsubscribed ?? this.unsubscribed,
    saved: saved ?? this.saved,
  );
}

class PlaylistLibraryNotifier extends Notifier<PlaylistLibraryState> {
  @override
  PlaylistLibraryState build() => const PlaylistLibraryState();

  void toggleGroup({required bool collected}) {
    state = collected
        ? state.copyWith(collectedCollapsed: !state.collectedCollapsed)
        : state.copyWith(createdCollapsed: !state.createdCollapsed);
  }

  /// 收藏歌单取消订阅 / 重新订阅（N43：当前只动分组归属）。
  void toggleSubscribe(String playlistId) {
    final next = {...state.unsubscribed};
    if (!next.remove(playlistId)) next.add(playlistId);
    state = state.copyWith(unsubscribed: next);
  }

  void toggleSaved(String playlistId) {
    final next = {...state.saved};
    if (!next.remove(playlistId)) next.add(playlistId);
    state = state.copyWith(saved: next);
  }
}

final playlistLibraryProvider = NotifierProvider<PlaylistLibraryNotifier, PlaylistLibraryState>(
  PlaylistLibraryNotifier.new,
);

/// 我的歌单库数据（系统歌单 + 创建 + 收藏）。
///
/// 未登录不发请求（UI 走登录 CTA，不是空态也不是失败态）；平台不支持返回空集。
class UserPlaylistsNotifier extends AsyncNotifier<List<MusicPlaylist>> {
  @override
  Future<List<MusicPlaylist>> build() async {
    if (!ref.watch(musicAccountProvider).logged) return const [];
    return ref.watch(musicRepositoryProvider).userPlaylists();
  }
}

final userPlaylistsProvider = AsyncNotifierProvider<UserPlaylistsNotifier, List<MusicPlaylist>>(
  UserPlaylistsNotifier.new,
);

/// 分组结果（派生数据在控制器侧算，UI 只画，AGENTS §4 第 13 条）。
@immutable
class PlaylistGroups {
  const PlaylistGroups({this.liked, this.created = const [], this.collected = const []});

  /// 「我喜欢的音乐」系统歌单：心动模式唯一合法来源（N41）。
  final MusicPlaylist? liked;
  final List<MusicPlaylist> created;
  final List<MusicPlaylist> collected;

  bool get isEmpty => liked == null && created.isEmpty && collected.isEmpty;
}

/// 按 `subscribed` 语义位分组（不靠下标猜，N43）。
PlaylistGroups groupPlaylists(List<MusicPlaylist> all, Set<String> unsubscribed) {
  MusicPlaylist? liked;
  final created = <MusicPlaylist>[];
  final collected = <MusicPlaylist>[];
  for (final p in all) {
    if (p.special && liked == null) {
      liked = p;
      continue;
    }
    if (p.subscribed) {
      if (!unsubscribed.contains(p.id)) collected.add(p);
    } else {
      created.add(p);
    }
  }
  return PlaylistGroups(liked: liked, created: created, collected: collected);
}

/// 详情页收藏态（歌单 / 榜单共用）：收藏歌单看 subscribed，自建歌单看本地回执。
bool isPlaylistSaved(MusicPlaylist p, PlaylistLibraryState state) => state.isSaved(p);

/// 详情屏当前的歌单标题（桌面面包屑第三级 / 移动端返回语义用）。
///
/// 由详情屏在数据到位后写入，壳层只读；带上 id 是为了避免路由已切走时
/// 面包屑还挂着上一张歌单的名字。
class MusicDetailCrumbNotifier extends Notifier<({String id, String name})?> {
  @override
  ({String id, String name})? build() => null;

  void set(String id, String name) {
    final next = (id: id, name: name);
    if (state != next) state = next;
  }

  void clear(String id) {
    if (state?.id == id) state = null;
  }
}

final musicDetailCrumbProvider = NotifierProvider<MusicDetailCrumbNotifier, ({String id, String name})?>(
  MusicDetailCrumbNotifier.new,
);

/// loginRequired → UI 登录 CTA；其余 → 魔法阵（N28/N41 四态口径）。
bool isLoginRequired(Object? error) =>
    error is MusicRepositoryException && error.code == MusicRepositoryErrorCode.loginRequired;
