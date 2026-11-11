import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/music_session.dart';

/// 视图滚动位置记忆（设计稿 N03）：离开视图时记住位置，回来时恢复。
///
/// 为什么不用 `PageStorage`：音乐四个视图是同一分支下的**四个路由**，
/// 每次 `go` 都会换一个 PageStorageBucket，跨路由取不到值。这里把偏移放
/// [musicScrollMemoryProvider]（屏级状态，跨视图保留），视图重建后回填。
class MusicScrollMemory extends ConsumerStatefulWidget {
  const MusicScrollMemory({super.key, required this.storageKey, required this.builder});

  /// 视图标识（discover / playlist / local / history）。
  final String storageKey;

  /// 用 controller 构建滚动视图的构造器。
  final Widget Function(BuildContext context, ScrollController controller) builder;

  @override
  ConsumerState<MusicScrollMemory> createState() => _MusicScrollMemoryState();
}

class _MusicScrollMemoryState extends ConsumerState<MusicScrollMemory> {
  late final ScrollController _controller = ScrollController();
  late final MusicScrollMemoryNotifier _memory;

  @override
  void initState() {
    super.initState();
    // dispose 里不能再碰 ref，先把 notifier 拿在手里。
    _memory = ref.read(musicScrollMemoryProvider.notifier);
    // 滚动即记：dispose 时子 Scrollable 已先销毁，controller.hasClients 会是 false，
    // 不能等到 dispose 再读 offset（实测写不回去）。
    _controller.addListener(() {
      if (_controller.hasClients) _memory.save(widget.storageKey, _controller.offset);
    });
    // 首帧后回填：此时才有 maxScrollExtent，越界由 clamp 兜住（内容可能变短）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final offset = ref.read(musicScrollMemoryProvider)[widget.storageKey] ?? 0;
      if (offset <= 0) return;
      _controller.jumpTo(offset.clamp(0.0, _controller.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
