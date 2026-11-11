import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/music_models.dart';
import 'music_providers.dart';
import 'music_session.dart';

/// 播放器状态快照（队列 / 当前曲 / 进度 / 模式 / 音质 / 音量 / 红心）。
///
/// 播放推进是**模拟时钟**（D-201：设计稿原型 500ms 步进，无真实音频流）；
/// 接入真实音源时只替换推进实现，状态与动作语义不变。
@immutable
class MusicPlayerState {
  const MusicPlayerState({
    required this.queue,
    required this.idx,
    required this.positionMs,
    required this.playing,
    required this.mode,
    required this.quality,
    required this.volume,
    required this.muted,
    required this.likedIds,
    required this.queueFromLiked,
    this.queueTitle,
  });

  /// 初始态（设计稿演示口径：正在播放 s1，进度 63s）。
  factory MusicPlayerState.initial(Set<String> likedIds) => MusicPlayerState(
    queue: const [],
    idx: -1,
    positionMs: 0,
    playing: false,
    mode: PlayMode.list,
    quality: QualityTier.lossless,
    volume: 72,
    muted: false,
    likedIds: likedIds,
    queueFromLiked: false,
  );

  final List<MusicSong> queue;
  final int idx;
  final int positionMs;
  final bool playing;
  final PlayMode mode;
  final QualityTier quality;
  final int volume;
  final bool muted;

  /// 红心集合（网易云/酷狗可写回；QQ 只读、咪咕无 —— UI 按 session 能力显隐）。
  final Set<String> likedIds;

  /// 队列是否来自「我喜欢的音乐」—— 心动模式唯一合法来源（N10）。
  final bool queueFromLiked;

  /// 当前队列来源标题（每日推荐 / 我喜欢的音乐 / 具体歌单名）。
  ///
  /// 移动全屏播放器顶栏显示它（M04）；播放器不自行拼文案，只存数据。
  final String? queueTitle;

  MusicSong? get current => (idx >= 0 && idx < queue.length) ? queue[idx] : null;

  /// 进度 0–1（时长 0 兜底，不做除零以外的猜测）。
  double progressOf(MusicSong song) =>
      song.duration.inMilliseconds <= 0 ? 0 : (positionMs / song.duration.inMilliseconds).clamp(0.0, 1.0);

  MusicPlayerState copyWith({
    List<MusicSong>? queue,
    int? idx,
    int? positionMs,
    bool? playing,
    PlayMode? mode,
    QualityTier? quality,
    int? volume,
    bool? muted,
    Set<String>? likedIds,
    bool? queueFromLiked,
    String? queueTitle,
  }) => MusicPlayerState(
    queue: queue ?? this.queue,
    idx: idx ?? this.idx,
    positionMs: positionMs ?? this.positionMs,
    playing: playing ?? this.playing,
    mode: mode ?? this.mode,
    quality: quality ?? this.quality,
    volume: volume ?? this.volume,
    muted: muted ?? this.muted,
    likedIds: likedIds ?? this.likedIds,
    queueFromLiked: queueFromLiked ?? this.queueFromLiked,
    queueTitle: queueTitle ?? this.queueTitle,
  );
}

/// 播放器事件（需要轻提示的语义；UI 层监听后映射 ARB 文案）。
enum PlayerNoticeKind { heartbeatExit, queueEmptyRemoveForbidden }

/// 播放器通知（带自增 seq，UI 只对最新一条响应一次）。
@immutable
class PlayerNotice {
  const PlayerNotice({required this.seq, required this.kind});
  final int seq;
  final PlayerNoticeKind kind;
}

/// 播放器 Notifier：队列 / 传输 / 模式 / 音质 / 音量 / 红心（design.html core.js 语义）。
class PlayerNotifier extends Notifier<MusicPlayerState> {
  Timer? _ticker;
  int _noticeSeq = 0;

  @override
  MusicPlayerState build() {
    ref.onDispose(_stopTicker);
    final liked = ref.watch(likedSeedsProvider);
    return MusicPlayerState.initial(liked);
  }

  // ── 时钟 ─────────────────────────────────────────────────────────────────
  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _syncTicker() {
    if (state.playing && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    } else if (!state.playing) {
      _stopTicker();
    }
  }

  void _tick() {
    final song = state.current;
    if (song == null) return;
    final total = song.duration.inMilliseconds;
    final next = state.positionMs + 500;
    if (next >= total) {
      if (state.mode == PlayMode.order && state.idx == state.queue.length - 1) {
        state = state.copyWith(positionMs: total, playing: false);
        _syncTicker();
        return;
      }
      _advance(auto: true);
      return;
    }
    state = state.copyWith(positionMs: next);
  }

  // ── 播放动作 ──────────────────────────────────────────────────────────────
  /// 播某首：已在队列则跳过去，否则插到当前之后（N23 / core.js playSong）。
  void playSong(MusicSong song, {bool fromLiked = false}) {
    final i = state.queue.indexWhere((s) => s.id == song.id);
    if (i < 0) {
      final insertAt = state.idx + 1;
      final queue = [...state.queue]..insert(insertAt.clamp(0, state.queue.length), song);
      state = state.copyWith(queue: queue, idx: insertAt.clamp(0, queue.length - 1), queueFromLiked: fromLiked);
    } else {
      state = state.copyWith(idx: i, queueFromLiked: fromLiked);
    }
    _startCurrent();
  }

  /// 整组播放（推荐卡 / 歌单「播放全部」/ 榜单详情）。
  void playAll(List<MusicSong> songs, {bool fromLiked = false, int start = 0, String? title}) {
    if (songs.isEmpty) return;
    state = state.copyWith(
      queue: List.unmodifiable(songs),
      idx: start.clamp(0, songs.length - 1),
      queueFromLiked: fromLiked,
      queueTitle: title,
    );
    _startCurrent();
  }

  /// 「下一首播放」：插到当前之后；已在队列则先摘出再插；是当前曲则不摘（N23 边界）。
  void enqueueNext(MusicSong song) {
    if (state.current?.id == song.id) return;
    final queue = [...state.queue];
    var idx = state.idx;
    final existingIdx = queue.indexWhere((s) => s.id == song.id);
    if (existingIdx >= 0) {
      queue.removeAt(existingIdx);
      if (existingIdx < idx) idx -= 1;
    }
    final insertAt = (idx + 1).clamp(0, queue.length);
    queue.insert(insertAt, song);
    state = state.copyWith(queue: queue, idx: idx);
  }

  void _startCurrent() {
    state = state.copyWith(positionMs: 0, playing: true);
    ref.read(historyFeedProvider.notifier).append(state.current!);
    _prefetchLyrics(state.current);
    _syncTicker();
  }

  /// 歌词预取：真实音源的歌词是异步的，先发请求让缓存就绪；
  /// 播放进度每 500ms 推进一帧，届时 `lyricsFor` 自然读到缓存，不必改 UI 取数口径。
  void _prefetchLyrics(MusicSong? song) {
    if (song == null) return;
    ref.read(musicRepositoryProvider).loadLyrics(song).catchError((Object _) => const SongLyrics(lines: []));
  }

  void playAt(int i) {
    if (i < 0 || i >= state.queue.length) return;
    state = state.copyWith(idx: i);
    _startCurrent();
  }

  void toggle() {
    if (state.current == null) return;
    state = state.copyWith(playing: !state.playing);
    _syncTicker();
  }

  /// 上一曲 / 下一曲。`auto` = 播完自动切（受模式语义约束，core.js nextTrack）。
  void nextTrack({bool auto = false}) => _advance(auto: auto);

  void prevTrack() {
    if (state.queue.isEmpty) return;
    _jump((state.idx - 1 + state.queue.length) % state.queue.length);
  }

  void _advance({required bool auto}) {
    if (state.queue.isEmpty) return;
    switch (state.mode) {
      case PlayMode.shuffle when state.queue.length > 1:
        var n = state.idx;
        while (n == state.idx) {
          n = DateTime.now().microsecondsSinceEpoch % state.queue.length;
        }
        _jump(n);
      case PlayMode.one when auto:
        _jump(state.idx); // 单曲循环：自动切歌回到开头
      default:
        _jump((state.idx + 1) % state.queue.length);
    }
  }

  void _jump(int i) {
    state = state.copyWith(idx: i, positionMs: 0);
    ref.read(historyFeedProvider.notifier).append(state.current!);
    _prefetchLyrics(state.current);
    _syncTicker();
  }

  /// 拖拽 / 点击进度（0–1 或绝对毫秒）；拖拽中由 UI 节流。
  void seekMs(int ms) {
    final song = state.current;
    if (song == null) return;
    state = state.copyWith(positionMs: ms.clamp(0, song.duration.inMilliseconds));
  }

  void seekRatio(double ratio) {
    final song = state.current;
    if (song == null) return;
    seekMs((song.duration.inMilliseconds * ratio.clamp(0.0, 1.0)).round());
  }

  // ── 模式 / 音质 / 音量 ────────────────────────────────────────────────────
  /// 模式点击循环（N10）：心动档不可用时**整档跳过**；离开「我喜欢的音乐」队列
  /// 自动退回顺序播放并通知 UI 提示。
  void cycleMode() {
    final heartbeatOk = state.queueFromLiked && ref.read(musicAccountProvider).cur == MusicPlatform.netease;
    const order = PlayMode.values;
    var next = order[(order.indexOf(state.mode) + 1) % order.length];
    if (next == PlayMode.heartbeat && !heartbeatOk) {
      next = order[(order.indexOf(PlayMode.heartbeat) + 1) % order.length];
    }
    state = state.copyWith(mode: next);
    if (state.mode != PlayMode.heartbeat &&
        state.queueFromLiked &&
        order.indexOf(next) == order.indexOf(PlayMode.order)) {
      _notice(PlayerNoticeKind.heartbeatExit);
    }
  }

  void setQuality(QualityTier q) => state = state.copyWith(quality: q);

  void setVolume(int v) => state = state.copyWith(volume: v.clamp(0, 100), muted: false);

  void toggleMute() => state = state.copyWith(muted: !state.muted);

  /// 关闭播放（N：停止但保留队列，进度归零）。
  void closePlayer() {
    state = state.copyWith(playing: false, positionMs: 0);
    _syncTicker();
  }

  // ── 队列管理 ──────────────────────────────────────────────────────────────
  /// 单行移除（N14）：只剩一首禁止；移除正在播的曲目自动落到下一首。
  bool removeAt(int i) {
    if (state.queue.length <= 1) {
      _notice(PlayerNoticeKind.queueEmptyRemoveForbidden);
      return false;
    }
    final wasCurrent = i == state.idx;
    final queue = [...state.queue]..removeAt(i);
    var idx = state.idx;
    if (wasCurrent) {
      idx = i.clamp(0, queue.length - 1);
    } else if (i < state.idx) {
      idx -= 1;
    }
    state = state.copyWith(queue: queue, idx: idx);
    return true;
  }

  /// 清空队列（N15）：只保留正在播放的 1 首；返回快照供「撤销」恢复。
  List<MusicSong> clearQueueKeepCurrent() {
    final snapshot = [...state.queue];
    final current = state.current;
    state = state.copyWith(queue: current == null ? const [] : [current], idx: current == null ? -1 : 0);
    return snapshot;
  }

  /// 撤销清空：恢复快照并把索引对回原当前曲。
  void restoreQueue(List<MusicSong> snapshot, int idx) {
    if (snapshot.isEmpty) return;
    state = state.copyWith(queue: [...snapshot], idx: idx.clamp(0, snapshot.length - 1));
  }

  // ── 红心 ──────────────────────────────────────────────────────────────────
  void toggleLike(MusicSong song) {
    final liked = {...state.likedIds};
    liked.contains(song.id) ? liked.remove(song.id) : liked.add(song.id);
    state = state.copyWith(likedIds: liked);
  }

  bool isLiked(MusicSong song) => state.likedIds.contains(song.id);

  void _notice(PlayerNoticeKind kind) {
    ref.read(playerNoticeProvider.notifier).emit(PlayerNotice(seq: ++_noticeSeq, kind: kind));
  }
}

final playerProvider = NotifierProvider<PlayerNotifier, MusicPlayerState>(PlayerNotifier.new);

/// 播放器语义通知（Riverpod 3 无 StateProvider：Notifier + emit）。
class PlayerNoticeNotifier extends Notifier<PlayerNotice?> {
  @override
  PlayerNotice? build() => null;

  void emit(PlayerNotice notice) => state = notice;
}

final playerNoticeProvider = NotifierProvider<PlayerNoticeNotifier, PlayerNotice?>(PlayerNoticeNotifier.new);
