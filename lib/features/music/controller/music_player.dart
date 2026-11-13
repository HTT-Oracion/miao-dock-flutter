import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/music_repository.dart';
import '../domain/music_models.dart';
import 'music_audio_engine.dart';
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
    required this.heartbeatSeeded,
    required this.likedHeartbeatOn,
    this.heartbeatRestore,
    this.queueTitle,
    this.lyricsRevision = 0,
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
    heartbeatSeeded: false,
    likedHeartbeatOn: false,
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

  /// 当前播放上下文是否已进入过心动模式；换歌单时才复位。
  final bool heartbeatSeeded;

  /// 「我喜欢的音乐」是否开启过心动模式；再次播放该歌单时自动恢复。
  final bool likedHeartbeatOn;

  /// 首次进入心动前的原队列，用于退出心动时恢复。
  final HeartbeatQueueSnapshot? heartbeatRestore;

  /// 歌词加载完成的版本号。
  ///
  /// 🔴 为什么需要它：`lyricsFor` 是**同步读缓存**（构建期调用），真实音源的歌词是
  /// 异步取的。取回后如果不触发一次状态变更，UI 不会重建 —— 表现就是「歌词停留在
  /// 空轴 /「译」按钮看起来没反应」。每次歌词落缓存就把版本 +1。
  final int lyricsRevision;

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
    bool? heartbeatSeeded,
    bool? likedHeartbeatOn,
    HeartbeatQueueSnapshot? heartbeatRestore,
    bool clearHeartbeatRestore = false,
    String? queueTitle,
    int? lyricsRevision,
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
    heartbeatSeeded: heartbeatSeeded ?? this.heartbeatSeeded,
    likedHeartbeatOn: likedHeartbeatOn ?? this.likedHeartbeatOn,
    heartbeatRestore: clearHeartbeatRestore ? null : (heartbeatRestore ?? this.heartbeatRestore),
    queueTitle: queueTitle ?? this.queueTitle,
    lyricsRevision: lyricsRevision ?? this.lyricsRevision,
  );
}

@immutable
class HeartbeatQueueSnapshot {
  const HeartbeatQueueSnapshot({required this.queue, required this.index, required this.queueFromLiked});

  final List<MusicSong> queue;
  final int index;
  final bool queueFromLiked;
}

/// 播放器事件（需要轻提示的语义；UI 层监听后映射 ARB 文案）。
enum PlayerNoticeKind { queueEmptyRemoveForbidden, playbackUnavailable }

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
  bool _heartbeatLoading = false;

  /// 音频引擎（由 [musicAudioEngineProvider] 注入；测试里是静默实现）。
  MusicAudioEngine? _engine;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _completedSub;

  /// 当前是否已把音频加载进引擎（true 时进度由音频流驱动）。
  bool _audioActive = false;

  /// 每次切歌自增，防止慢请求回来把旧歌写到新歌上。
  int _audioLoadSerial = 0;

  @override
  MusicPlayerState build() {
    ref.onDispose(() {
      _stopTicker();
      _positionSub?.cancel();
      _completedSub?.cancel();
      _engine = null;
    });
    final liked = ref.watch(likedSeedsProvider);
    return MusicPlayerState.initial(liked);
  }

  /// 懒接线：只有真正要出声时才订阅引擎流（避免无播放在听时空转）。
  MusicAudioEngine _ensureEngine() {
    final existing = _engine;
    if (existing != null) return existing;
    final engine = ref.read(musicAudioEngineProvider);
    _engine = engine;
    if (engine.isReal) {
      _positionSub = engine.positionStream.listen((position) {
        final song = state.current;
        if (!_audioActive || song == null) return;
        state = state.copyWith(positionMs: position.inMilliseconds.clamp(0, song.duration.inMilliseconds));
      });
      _completedSub = engine.completedStream.listen((_) {
        if (!_audioActive) return;
        _advance(auto: true);
      });
    }
    return engine;
  }

  /// 各平台 CDN 对 UA / Referer 的校验不同；缺头时酷狗 / QQ 会直接 403。
  static Map<String, String> _streamHeaders(MusicPlatform platform) {
    const ua =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    return switch (platform) {
      MusicPlatform.netease => {'User-Agent': ua, 'Referer': 'https://music.163.com/'},
      MusicPlatform.qq => {'User-Agent': ua, 'Referer': 'https://y.qq.com/'},
      MusicPlatform.kugou => {'User-Agent': ua, 'Referer': 'https://www.kugou.com/'},
      MusicPlatform.migu => {'User-Agent': ua, 'Referer': 'https://music.migu.cn/'},
      MusicPlatform.local => const {},
    };
  }

  // ── 时钟 ─────────────────────────────────────────────────────────────────
  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _syncTicker() {
    if (_audioActive) {
      _stopTicker();
      return;
    }
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
      state = state.copyWith(
        queue: queue,
        idx: insertAt.clamp(0, queue.length - 1),
        mode: state.mode == PlayMode.heartbeat ? PlayMode.order : state.mode,
        queueFromLiked: fromLiked,
        heartbeatSeeded: false,
        clearHeartbeatRestore: true,
      );
    } else {
      state = state.copyWith(
        idx: i,
        mode: state.mode == PlayMode.heartbeat ? PlayMode.order : state.mode,
        queueFromLiked: fromLiked,
        heartbeatSeeded: false,
        clearHeartbeatRestore: true,
      );
    }
    _startCurrent();
  }

  /// 整组播放（推荐卡 / 歌单「播放全部」/ 榜单详情）。
  void playAll(List<MusicSong> songs, {bool fromLiked = false, int start = 0, String? title}) {
    if (songs.isEmpty) return;
    final likedHeartbeatOn = state.likedHeartbeatOn;
    state = state.copyWith(
      queue: List.unmodifiable(songs),
      idx: start.clamp(0, songs.length - 1),
      mode: state.mode == PlayMode.heartbeat ? PlayMode.order : state.mode,
      queueFromLiked: fromLiked,
      heartbeatSeeded: false,
      clearHeartbeatRestore: true,
      queueTitle: title,
    );
    _startCurrent();
    if (fromLiked && likedHeartbeatOn) _setPlayMode(PlayMode.heartbeat);
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

  /// 开始播放当前曲。
  ///
  /// [resumeAtMs] 非空表示「从该进度继续」（暂停后恢复），此时**不重置进度、
  /// 不重复记播放历史**；切歌 / 首次播放传 null 走完整起播。
  void _startCurrent({int? resumeAtMs}) {
    final song = state.current!;
    final serial = ++_audioLoadSerial;
    _audioActive = false;
    final engine = _engine;
    if (engine != null && engine.isReal) unawaited(engine.stop());
    final resume = resumeAtMs != null && resumeAtMs > 0 && resumeAtMs < song.duration.inMilliseconds;
    state = state.copyWith(positionMs: resume ? resumeAtMs : 0, playing: true);
    // 恢复播放不是「又听了一次」，不重复记历史。
    if (!resume) ref.read(historyFeedProvider.notifier).append(song);
    _prefetchLyrics(song);
    _syncTicker();
    unawaited(_loadAudio(song, serial, startAtMs: resume ? resumeAtMs : null));
  }

  /// 取播放地址 → 交给 just_audio。失败时的收口策略：
  ///
  /// · 取不到地址（平台无版权 / 需会员 / 需登录）→ 保留当前歌为「选中但未播放」，
  ///   弹一次「无法播放」提示，**不自动连跳**（连跳会让用户以为播放器抽风）；
  /// · 取到地址但解码失败 → 同上，但会降一档音质重试一次（无损换 320K 常见于会员限制）；
  /// · URL 是 http：just_audio 在 macOS/Android 默认拒绝明文，统一升 https（各平台 CDN 均支持）。
  Future<void> _loadAudio(MusicSong song, int serial, {int? startAtMs}) async {
    bool stale() => serial != _audioLoadSerial || state.current?.id != song.id;
    final repo = ref.read(musicRepositoryProvider);
    var quality = state.quality;
    var url = await _resolveQuietly(repo, song, quality);
    if (stale()) return;
    if (url == null || url.isEmpty) {
      // 会员 / 版权档位失败时降一档再试一次（设计稿音质弹层的降级口径）。
      final fallback = _lowerQuality(quality);
      if (fallback != null) {
        quality = fallback;
        url = await _resolveQuietly(repo, song, quality);
        if (stale()) return;
      }
    }
    if (url == null || url.isEmpty) {
      state = state.copyWith(playing: false);
      _syncTicker();
      _notice(PlayerNoticeKind.playbackUnavailable);
      return;
    }
    final resolved = url.replaceFirst(RegExp('^http://'), 'https://');
    final engine = _ensureEngine();
    if (stale()) return;
    if (!engine.isReal) {
      // 静默引擎（无音频后端 / 测试）：退回模拟时钟，UI 行为仍可验证。
      _audioActive = false;
      _syncTicker();
      return;
    }
    try {
      final ok = await engine.load(
        url: resolved,
        headers: _streamHeaders(song.platform),
        volume: state.muted ? 0 : state.volume / 100,
        play: state.playing,
        // 后台通知 / 锁屏 / 系统媒体面板展示的元数据。
        title: song.title,
        artist: song.artist,
        album: song.album,
        artUri: _artUri(song.coverUrl),
        duration: song.duration,
      );
      if (stale()) return;
      if (!ok) {
        _audioActive = false;
        _syncTicker();
        return;
      }
      _audioActive = true;
      // 恢复播放：加载完成后定位回暂停时的进度（否则会从 0 开始）。
      if (startAtMs != null && startAtMs > 0) {
        await engine.seek(Duration(milliseconds: startAtMs));
      }
      _stopTicker();
    } on Object {
      if (stale()) return;
      _audioActive = false;
      state = state.copyWith(playing: false);
      _syncTicker();
      _notice(PlayerNoticeKind.playbackUnavailable);
    }
  }

  /// 封面 URL → 后台通知用的 artUri（无效 / 缺失则不传）。
  static Uri? _artUri(String? coverUrl) {
    if (coverUrl == null || coverUrl.trim().isEmpty) return null;
    final uri = Uri.tryParse(coverUrl.trim());
    return uri != null && uri.hasScheme ? uri : null;
  }

  Future<String?> _resolveQuietly(MusicRepository repo, MusicSong song, QualityTier quality) async {
    try {
      return await repo.resolvePlayUrl(song, quality);
    } on Object {
      return null;
    }
  }

  /// 降一档音质（标准档没有再降的余地）。
  static QualityTier? _lowerQuality(QualityTier q) => switch (q) {
    QualityTier.master => QualityTier.hires,
    QualityTier.hires => QualityTier.lossless,
    QualityTier.lossless => QualityTier.high,
    QualityTier.high => QualityTier.standard,
    QualityTier.standard => null,
  };

  /// 歌词预取：真实音源的歌词是异步的，先发请求让缓存就绪；
  /// 播放进度每 500ms 推进一帧，届时 `lyricsFor` 自然读到缓存，不必改 UI 取数口径。
  void _prefetchLyrics(MusicSong? song) {
    if (song == null) return;
    final id = song.id;
    unawaited(() async {
      try {
        await ref.read(musicRepositoryProvider).loadLyrics(song);
        if (!ref.mounted || state.current?.id != id) return;
        // 歌词已进缓存：bump 版本号让 UI 重建并读到真歌词（含翻译轨）。
        state = state.copyWith(lyricsRevision: state.lyricsRevision + 1);
      } on Object {
        // 歌词失败不打断播放；UI 继续显示空轴。
      }
    }());
  }

  void playAt(int i) {
    if (i < 0 || i >= state.queue.length) return;
    state = state.copyWith(idx: i);
    _startCurrent();
  }

  void toggle() {
    if (state.current == null) return;
    final next = !state.playing;
    final engine = _engine;

    // 要「开始播放」，但音频还没真正接上引擎（首次点 / 上次加载失败 / 静默回落）
    // → 必须重新走加载流程。只翻 playing 标志会出现「图标在跳、没有声音」。
    //
    // 🔴 必须带上当前进度：否则「暂停 → 播放」会从头开始（用户实测反馈）。
    if (next && (engine == null || !_audioActive)) {
      _startCurrent(resumeAtMs: state.positionMs);
      return;
    }

    state = state.copyWith(playing: next);
    if (_audioActive && engine != null) {
      // play() 的 Future 要等播放停止才完成，不能 await（同 AudioEngine.load 的坑）。
      unawaited(next ? engine.play() : engine.pause());
    }
    _syncTicker();
  }

  /// 上一曲 / 下一曲。`auto` = 播完自动切（受模式语义约束，core.js nextTrack）。
  void nextTrack({bool auto = false}) => _advance(auto: auto);

  void prevTrack() {
    if (state.queue.isEmpty) return;
    if (state.mode == PlayMode.shuffle && state.queue.length > 1) {
      var previous = state.idx;
      while (previous == state.idx) {
        previous = DateTime.now().microsecondsSinceEpoch % state.queue.length;
      }
      _jump(previous);
      return;
    }
    if (state.mode == PlayMode.order) {
      _jump((state.idx - 1).clamp(0, state.queue.length - 1));
      return;
    }
    _jump((state.idx - 1 + state.queue.length) % state.queue.length);
  }

  void _advance({required bool auto}) {
    if (state.queue.isEmpty) return;
    switch (state.mode) {
      case PlayMode.heartbeat:
        if (state.idx + 1 < state.queue.length) {
          _jump(state.idx + 1);
        } else {
          unawaited(_enterHeartbeat(advance: true));
        }
      case PlayMode.shuffle when state.queue.length > 1:
        var n = state.idx;
        while (n == state.idx) {
          n = DateTime.now().microsecondsSinceEpoch % state.queue.length;
        }
        _jump(n);
      case PlayMode.one when auto:
        _jump(state.idx); // 单曲循环：自动切歌回到开头
      case PlayMode.order:
        final next = state.idx + 1;
        if (next >= state.queue.length) {
          state = state.copyWith(
            positionMs: state.current?.duration.inMilliseconds ?? state.positionMs,
            playing: false,
          );
          _syncTicker();
        } else {
          _jump(next);
        }
      default:
        _jump((state.idx + 1) % state.queue.length);
    }
  }

  void _jump(int i) {
    state = state.copyWith(idx: i);
    // 切歌必须真正换流：之前这里只改索引，音频仍停在上一首（表现为「切歌没声音」）。
    _startCurrent();
  }

  /// 拖拽 / 点击进度（0–1 或绝对毫秒）；拖拽中由 UI 节流。
  void seekMs(int ms) {
    final song = state.current;
    if (song == null) return;
    state = state.copyWith(positionMs: ms.clamp(0, song.duration.inMilliseconds));
    final engine = _engine;
    // 只要音频已经加载进引擎就 seek —— 暂停状态下拖动进度条同样要生效。
    if (_audioActive && engine != null) {
      unawaited(engine.seek(Duration(milliseconds: state.positionMs)));
    }
  }

  void seekRatio(double ratio) {
    final song = state.current;
    if (song == null) return;
    seekMs((song.duration.inMilliseconds * ratio.clamp(0.0, 1.0)).round());
  }

  // ── 模式 / 音质 / 音量 ────────────────────────────────────────────────────
  /// 模式点击循环（N10）：心动档不可用时整档跳过。
  void cycleMode() {
    final heartbeatOk = _canUseHeartbeat;
    const order = PlayMode.values;
    var next = order[(order.indexOf(state.mode) + 1) % order.length];
    if (next == PlayMode.heartbeat && !heartbeatOk) {
      next = order[(order.indexOf(PlayMode.heartbeat) + 1) % order.length];
    }
    _setPlayMode(next);
  }

  bool get _canUseHeartbeat => state.queueFromLiked && ref.read(musicAccountProvider).cur == MusicPlatform.netease;

  void _setPlayMode(PlayMode mode) {
    if (mode == PlayMode.heartbeat) {
      if (!_canUseHeartbeat || state.current == null) return;
      state = state.copyWith(mode: mode, likedHeartbeatOn: true);
      unawaited(_enterHeartbeat());
      return;
    }

    final snapshot = state.heartbeatRestore;
    if (state.mode == PlayMode.heartbeat && snapshot != null) {
      final current = state.current;
      final found = current == null ? -1 : snapshot.queue.indexWhere((song) => song.id == current.id);
      final restored = current != null && found < 0 ? [current, ...snapshot.queue] : snapshot.queue;
      state = state.copyWith(
        mode: mode,
        queue: restored,
        idx: current != null && found < 0 ? 0 : (found >= 0 ? found : snapshot.index.clamp(0, restored.length - 1)),
        queueFromLiked: snapshot.queueFromLiked,
        clearHeartbeatRestore: true,
      );
      return;
    }
    state = state.copyWith(mode: mode);
  }

  Future<void> _enterHeartbeat({bool advance = false}) async {
    if (_heartbeatLoading || !_canUseHeartbeat) return;
    final seed = state.current;
    if (seed == null) return;
    final alreadySeeded = state.heartbeatSeeded;
    _heartbeatLoading = true;
    try {
      final similar = await ref.read(musicRepositoryProvider).similarSongs(seed, limit: 20);
      if (state.mode != PlayMode.heartbeat || state.current?.id != seed.id) return;
      final seen = <String>{seed.id};
      final picked = <MusicSong>[];
      for (final song in similar) {
        if (seen.add(song.id)) picked.add(song);
      }
      if (picked.isEmpty) return;

      if (!alreadySeeded) {
        state = state.copyWith(
          heartbeatRestore: HeartbeatQueueSnapshot(
            queue: [...state.queue],
            index: state.idx,
            queueFromLiked: state.queueFromLiked,
          ),
        );
      }

      final queue = alreadySeeded ? [seed, ...picked] : picked;
      if (advance) {
        final start = alreadySeeded && queue.length > 1 ? 1 : 0;
        state = state.copyWith(queue: queue, idx: start, queueFromLiked: true, heartbeatSeeded: true);
        _startCurrent();
      } else if (alreadySeeded) {
        state = state.copyWith(queue: queue, idx: 0, queueFromLiked: true, heartbeatSeeded: true);
      } else {
        state = state.copyWith(queue: queue, idx: 0, queueFromLiked: true, heartbeatSeeded: true);
        _startCurrent();
      }
    } on Object {
      // 与 miao-dock 一致：取相似失败时保留原队列，不做随机歌曲伪降级。
    } finally {
      _heartbeatLoading = false;
    }
  }

  void setQuality(QualityTier q) {
    state = state.copyWith(quality: q);
    final song = state.current;
    if (song != null) {
      final serial = ++_audioLoadSerial;
      _audioActive = false;
      _syncTicker();
      unawaited(_loadAudio(song, serial));
    }
  }

  void setVolume(int v) {
    state = state.copyWith(volume: v.clamp(0, 100), muted: false);
    // 不判 _audioActive：引擎已建好就同步（加载中 / 刚暂停时也要生效）。
    _engine?.setVolume(state.volume / 100);
  }

  void toggleMute() {
    state = state.copyWith(muted: !state.muted);
    _engine?.setVolume(state.muted ? 0 : state.volume / 100);
  }

  /// 关闭播放（N：停止但保留队列，进度归零）。
  void closePlayer() {
    _audioLoadSerial += 1;
    _audioActive = false;
    final engine = _engine;
    if (engine != null && engine.isReal) unawaited(engine.stop());
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
    if (song.platform == MusicPlatform.local) return;
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
