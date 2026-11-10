import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:protocol/protocol.dart' show jsNumStr;
import 'package:window_manager/window_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/storage/shell_prefs.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/responsive.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/buttons.dart';
import '../controller/library_controller.dart';
import '../controller/reader_focus.dart';
import '../controller/queue_controller.dart';
import '../domain/lib_book.dart';
import 'reader/reader_image_cache.dart';
import 'reader/reader_mobile.dart';
import 'reader/reader_mobile_stage.dart';
import 'reader/reader_paged_stage.dart';
import 'reader/reader_prefs.dart';
import 'reader/reader_settings.dart';
import 'reader/reader_webtoon.dart';
import 'reader/reader_widgets.dart';
import 'reader/reader_zoom.dart';

/// 完整阅读器（B.6 + 重设计稿 manga-viewer）。
///
/// 两端共用同一份会话 / 页码 / 偏好，舞台与工具栏按端分叉：
/// - **桌面**：[PageView] + [ReaderBar]（页码滑条 / 缩放 chips / 对照 / 网格），
///   翻页由键盘、两侧 56px 热区、滚轮与触控板横滑驱动，缩放见 [ReaderZoom]；
/// - **移动**：[MobileReaderStage]（跟手翻页 / 双击 2.5× / 长按放大镜 / 亮度边缘）
///   + [ReaderTopBar] + [ReaderBottomBar]（上一话·滑条·页码·下一话 + 五动作），
///   工具栏 3s 自动隐藏并带进度线，页码 / 亮度 / 换话有 OSD 气泡。
/// - 页面内容：**有译文显示译文，没有译文回退原图**（`viewer.tsx` 同语义），
///   并在页内给「未翻译」角标。
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  late final PageController _controller;

  /// 当前页的**事实源是 [readerPageProvider]**，不是 State 字段。
  ///
  /// 切视图页签 / 切模块都会重建阅读器的 page（State 被丢弃），
  /// 页码放 State 里就必然回到第 1 页；放 provider 才能「续读同一页」。
  /// 只有手动关闭（[ReaderSessionNotifier.close]）才归零。
  int get _index => ref.read(readerPageProvider);

  /// 上次打开的会话标识；换书 / 换话时强制回第一页（不做续读）。
  String? _openedSession;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: ref.read(readerPageProvider));
    _hideCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted && _barVisible) {
          setState(() => _barVisible = false);
        }
      });
    _nudgeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _focusNotifier = ref.read(readerFocusProvider.notifier);
    _fullscreenNotifier = ref.read(readerFullscreenProvider.notifier);
    // 🔴 桌面快捷键**不能只靠 Focus**：焦点会被顶栏按钮、抽屉弹层、以及
    // 切模块时的 IndexedStack 拿走，而 `autofocus` 只在首次挂载请求一次，
    // 回到阅读器不会再请求 —— 表现就是「快捷键时好时不好」。
    // 注册到 HardwareKeyboard：所有按键先过这里，与焦点无关；
    // 只在「桌面 + 阅读器是当前路由」时接管，弹层打开时自动放行。
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    // 系统全屏状态可能被「窗口标题栏 / 绿色按钮 / Ctrl+Cmd+F」改掉，
    // 不能只在 `_toggleFocus` 里记一次 —— 否则用户手动退出全屏后，
    // 阅读器仍以为自己在全屏，顶部不给红绿灯让位。
    windowManager.addListener(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() => _clock = _formatClock());
    });
    WidgetsBinding.instance.addObserver(this);
    // 首帧后预热前后页：第一次翻页不该是冷启动（冷启动 = 空白一帧 = 闪）。
    // 放在 initState 而不是 build：build 会重入，等于每次重建都排一串预载定时器。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !context.isMobile) return;
      final session = ref.read(readerSessionProvider);
      if (session == null || session.pages <= 0) return;
      _preload(ref.read(readerPageProvider), session.pages);
    });
  }

  /// 退到后台就释放常亮（设计稿：退出或退后台自动释放），回来再申请。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!context.isMobile) return;
    if (state == AppLifecycleState.resumed) {
      _awakeApplied = false;
      _syncWakelock();
      return;
    }
    if (_awakeApplied && (state == AppLifecycleState.paused || state == AppLifecycleState.inactive)) {
      _awakeApplied = false;
      unawaited(WakelockPlus.disable().catchError((_) {}));
    }
  }

  /// 系统全屏状态变化（用户从窗口标题栏 / 绿色按钮 / 系统快捷键切换）。
  ///
  /// 专注模式本身不变（壳层仍然隐藏），但「是否真全屏」变了 ——
  /// 顶部让位依赖这个事实：退出全屏后必须重新给红绿灯让出 28px。
  @override
  void onWindowEnterFullScreen() => _fullscreenNotifier?.set(true);

  @override
  void onWindowLeaveFullScreen() => _fullscreenNotifier?.set(false);

  /// 工具栏可见性（重设计稿：点中心呼出/收起，3s 无操作自动隐藏）。
  bool _barVisible = true;
  Timer? _barTimer;

  /// 移动端 3s 自动隐藏的进度线（设计稿 `.hidebar`）。
  late final AnimationController _hideCtrl;

  /// 对照模式（桌面端：原文/译文双栏，C 键或按钮切换）。
  bool _compare = false;

  /// 网格总览（桌面端：G 键或按钮，缩略图点选跳页）。
  bool _gridOpen = false;

  /// 缩放状态（桌面）：顶栏调节器 / Ctrl+滚轮 / 触控板捏合共用一份（D-164）。
  final _zoom = ReaderZoom();

  /// 滚轮与触摸板横滑的翻页累计：一次手势只翻一页（正 = 下一页）。
  double _scrollAcc = 0;

  /// 触控板捏合的基准 scale（`PointerPanZoomUpdateEvent.scale` 是累计值）。
  double _panZoomScale = 1;
  DateTime _lastScrollTurn = DateTime.fromMillisecondsSinceEpoch(0);

  // ── 移动端 OSD / 提示态 ──
  String _osdMain = '';
  String? _osdSub;
  bool _osdVisible = false;
  Timer? _osdTimer;

  bool _brightVisible = false;
  Timer? _brightTimer;

  bool _endOpen = false;

  bool _hintVisible = false;
  double _hintOpacity = 1;
  Timer? _hintTimer;

  String _clock = '';
  Timer? _clockTimer;

  /// 桌面「翻不动时轻推一下」的橡皮筋（设计稿 `.nudge`，220ms）。
  late final AnimationController _nudgeCtrl;
  double _nudgeSign = 1;

  /// 快捷键速查卡（`?`）。
  bool _helpOpen = false;

  /// 进入专注模式前窗口是否已经全屏：退出时按原样还原。
  bool _wasFullScreen = false;

  /// 提前抓住 notifier：dispose 里 `ref` 已不可用，但 notifier 仍属于常驻容器。
  ReaderFocusNotifier? _focusNotifier;
  ReaderFullscreenNotifier? _fullscreenNotifier;

  /// 专注模式是否开着（本地镜像：dispose 里不能再 `ref.read` 判状态）。
  bool _focusOn = false;

  /// 最近一次 build 的窄/宽屏判定（dispose 里 `context` 已不可用）。
  bool _mobile = false;

  /// 沉浸式状态栏是否已经应用（避免每帧重复下发）。
  bool? _immersiveApplied;

  /// 保持常亮是否已经申请（退后台会被释放，回前台再申）。
  bool _awakeApplied = false;

  /// 点按分区提示只在本次进程内展一次（设计稿：首次进入 2s）。
  static bool _tapHintShown = false;

  /// 桌面裸滚轮 / macOS 触摸板横滑翻页。
  ///
  /// 阈 + 冷却：触摸板惯性滚动会连着吐出几十个 delta，不冷却就一次挥动翻十页。
  void _advanceByScroll(Offset delta) {
    final d = delta.dx.abs() >= delta.dy.abs() ? delta.dx : delta.dy;
    if (d == 0) return;
    final now = DateTime.now();
    if (now.difference(_lastScrollTurn).inMilliseconds < 300) {
      _scrollAcc = 0;
      return;
    }
    if (_scrollAcc != 0 && _scrollAcc.sign != d.sign) _scrollAcc = 0;
    _scrollAcc += d;
    if (_scrollAcc.abs() < 20) return;
    final dir = _scrollAcc > 0 ? 1 : -1;
    _scrollAcc = 0;
    _lastScrollTurn = now;
    final total = ref.read(readerSessionProvider)?.pages ?? 0;
    _go(dir, total);
  }

  /// 触控板（macOS）的平移 / 捏合。
  ///
  /// 纯平移**不在这里翻页** —— 那是 `PageView` 的本职（1:1 跟手 + 松手落位），
  /// 我们只在两件事上插手：捏合缩放，以及「放大态时的平移」。
  void _onPanZoom(PointerPanZoomUpdateEvent e) {
    // 对照模式没有 PageView 接管平移：横扫自己翻页；
    // 捏合（scale 变化）交给每栏的 InteractiveViewer，`_zoom` 不参与 ——
    // 否则对照里捏一下会把单页模式的缩放状态带脏。
    if (_compare) {
      // 只认横向：纵向滑动不该翻页。
      if (e.panDelta.dx.abs() <= e.panDelta.dy.abs()) return;
      // `panDelta` 是**内容位移**（左滑为负 = 下一页），取反后交给同一套
      // 阈值 + 300ms 冷却（与滚轮同源，避免一次挥动翻十页）。
      _advanceByScroll(Offset(-e.panDelta.dx, 0));
      return;
    }
    final factor = _panZoomScale == 0 ? 1.0 : e.scale / _panZoomScale;
    if ((factor - 1).abs() > 0.005) {
      _panZoomScale = e.scale;
      _zoom.scaleAt(e.localPosition, factor);
      return;
    }
    if (_zoom.zoomed) _zoom.panBy(-e.panDelta);
  }

  /// 桌面滚轮三分支（设计稿 desktop.html 同口径）：
  /// Ctrl/⌘+滚轮 = 锚点缩放；放大态 = 平移；其余 = 翻页。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // 对照模式：没有舞台缩放（两栏各自 InteractiveViewer），滚轮一律翻页，
    // Ctrl/⌘+滚轮也不缩放 —— 否则会污染单页模式的 `_zoom`。
    if (_compare) {
      _advanceByScroll(event.scrollDelta);
      return;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      _zoom.scaleAt(event.localPosition, math.exp(-event.scrollDelta.dy * 0.0015));
      return;
    }
    if (_zoom.zoomed) {
      _zoom.panBy(-event.scrollDelta);
      return;
    }
    _advanceByScroll(event.scrollDelta);
  }

  /// 预载窗口（重设计稿：前后各 N 页，延后 200ms 等翻页动画结束——只取字节
  /// 热身图片解码缓存，不渲染）。
  void _preload(int index, int total) {
    final session = ref.read(readerSessionProvider);
    if (session == null) return;
    final span = ref.read(readerPrefsProvider).preload;
    Timer(const Duration(milliseconds: 200), () async {
      final client = ref.read(mangaSvcClientProvider);
      final steps = [
        for (var d = 1; d <= span; d++) ...[d, -d],
      ];
      for (final d in steps) {
        final seq = index + d;
        if (seq < 1 || seq > total) continue;
        final wantTranslated = !_showOriginal && session.translated.contains(seq);
        final key = readerImageKey(
          bookKey: session.key,
          chapterNo: session.chapterNo,
          seq: seq,
          translated: wantTranslated,
        );
        if (ReaderImageCache.get(key) != null) continue;
        try {
          final bytes = session.chapterNo == null
              ? await client.getBookFile(session.key, seq, translated: wantTranslated)
              : await client.getChapterFile(session.key, session.chapterNo!, seq, translated: wantTranslated);
          if (bytes.isEmpty) continue;
          // 预载必须**落进缓存**：只取不用等于白取，翻过去还是空白一帧。
          ReaderImageCache.put(key, Uint8List.fromList(bytes));
        } catch (_) {
          // 预载失败静默：正式取图路径会再走一次并给出错误 UI。
        }
      }
    });
  }

  void _armBarTimer() {
    // 3s 自动隐藏是**移动端专属**（index.html §01：桌面顶栏常驻，点图才隐藏）。
    if (!context.isMobile) return;
    _barTimer?.cancel();
    if (mounted && _hideCtrl.value != 0) _hideCtrl.value = 0;
    if (mounted && !_hideCtrl.isAnimating) _hideCtrl.forward(from: 0);
    _barTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _barVisible) setState(() => _barVisible = false);
    });
  }

  void _toggleBar() {
    setState(() => _barVisible = !_barVisible);
    if (_barVisible) {
      _armBarTimer();
    } else {
      _barTimer?.cancel();
      _hideCtrl.stop();
      _hideCtrl.value = 0;
    }
  }

  /// 滑条/页码跳页（重设计稿：跳页弹 OSD 级页码气泡——顶栏页码即 OSD）。
  void _jumpTo(int page, int total) {
    // 跳页同样即时落位：滑条拖到哪就是哪，不再补一段动画。
    _commitPage(page, total);
  }

  /// 移动端跳页（不走 PageView 动画：舞台自己按动画档位收尾）。
  void _jumpMobile(int page, int total) {
    final to = page.clamp(0, total - 1);
    if (to == _index) return;
    _commitPage(to, total);
    _showOsdForPage(to, total);
    _armBarTimer();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    windowManager.removeListener(this);
    _barTimer?.cancel();
    _osdTimer?.cancel();
    _brightTimer?.cancel();
    _hintTimer?.cancel();
    _clockTimer?.cancel();
    _hideCtrl.dispose();
    _nudgeCtrl.dispose();
    _exitFocus();
    _controller.dispose();
    _zoom.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (_awakeApplied) unawaited(WakelockPlus.disable().catchError((_) {}));
    if (_immersiveApplied == true) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// 是否显示原图。**默认 false = 看译文**；用户切换后持久化。
  late bool _showOriginal = readReaderShowOriginal();

  void _toggleOriginal() {
    // 对照里点「显示原图 / 显示翻译」（或按 `O`）= **退出对照并只显示该侧**，
    // 与「点某一栏」同一条设计稿口径；非对照时就是单纯的原图 ⇄ 译文。
    _focusSide(original: !_showOriginal);
  }

  void _go(int delta, int total) {
    final next = (_index + delta).clamp(0, total - 1);
    if (next == _index) {
      // 首末页翻不动：轻推 3% 给个「到头了」的反馈（设计稿 `.nudge`）。
      _nudge(delta);
      return;
    }
    _commitPage(next, total);
  }

  /// 翻页的唯一落点：**先写 provider（页码事实源），再同步 PageView**。
  ///
  /// 🔴 对照模式与条漫模式里没有 `PageView`，`_controller.hasClients == false`。
  /// 之前直接 `jumpToPage()`，在对照模式下会断言「没有 client」——
  /// 表现就是「对照时按方向键翻不动」。现在没有 client 也照样翻页，
  /// 由 `index` 驱动 `ComparePane.seq` 重建。
  void _commitPage(int next, int total) {
    final to = next.clamp(0, total - 1);
    if (to == _index) return;
    // 翻页即归位（用户口径）：不留上一页的放大/位移。
    _zoom.reset();
    ref.read(readerPageProvider.notifier).set(to);
    if (_controller.hasClients) {
      // 翻页即时切换（2026-11-07 用户裁定，设计稿也写明「默认无动画」）。
      // 预载交给 `onPageChanged`：jumpToPage 会触发它，这里再调一次就是双份。
      _controller.jumpToPage(to);
    } else {
      _preload(to, total);
    }
  }

  void _nudge(int dir) {
    _nudgeSign = dir.toDouble();
    _nudgeCtrl.forward(from: 0);
  }

  /// 轻推的横向位移：sin(0→π) 先出后回，峰值 12px。
  double get _nudgeDx => math.sin(_nudgeCtrl.value * math.pi) * _nudgeSign * 12;

  // ────────────────────────── 移动端 OSD ──────────────────────────

  void _showOsd(String main, [String? sub]) {
    if (!ref.read(readerPrefsProvider).pageNum) return;
    _osdTimer?.cancel();
    setState(() {
      _osdMain = main;
      _osdSub = sub;
      _osdVisible = true;
    });
    _osdTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _osdVisible = false);
    });
  }

  void _showOsdForPage(int page, int total) {
    final session = ref.read(readerSessionProvider);
    _showOsd(
      AppLocalizations.of(context).readerPage(page + 1, total),
      session?.chapterNo == null ? null : _chapterSub(session!),
    );
  }

  void _nudgeBrightness(double delta) {
    ref.read(readerPrefsProvider.notifier).nudgeBrightness(delta);
    _brightTimer?.cancel();
    if (!_brightVisible) setState(() => _brightVisible = true);
    _brightTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _brightVisible = false);
    });
  }

  void _maybeScheduleTapHint() {
    if (!context.isMobile || _tapHintShown) return;
    if (!ref.read(readerPrefsProvider).tapTurn) return;
    _tapHintShown = true;
    // 首帧之后再亮：build 期间 setState 会被断言拦下。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showTapHint();
    });
  }

  void _showTapHint() {
    setState(() {
      _hintVisible = true;
      _hintOpacity = 1;
    });
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _hintOpacity = 0);
      _hintTimer = Timer(AppMotion.pageSwitch, () {
        if (mounted) setState(() => _hintVisible = false);
      });
    });
  }

  String _formatClock() =>
      MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.now(), alwaysUse24HourFormat: true);

  /// 沉浸式状态栏 / 还原（移动端）。
  void _syncSystemUi() {
    final want = context.isMobile && ref.read(readerPrefsProvider).immersive;
    if (want == _immersiveApplied) return;
    _immersiveApplied = want;
    SystemChrome.setEnabledSystemUIMode(want ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  /// 保持常亮（移动端才有意义；桌面由系统电源策略管，不作为）。
  void _syncWakelock() {
    final want = context.isMobile && ref.read(readerPrefsProvider).awake;
    if (want == _awakeApplied) return;
    _awakeApplied = want;
    // 桌面 / Web 没有常亮语义，插件会抛 UnsupportedError —— 静默即可。
    unawaited((want ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {}));
  }

  // ────────────────────────── 章节导航 ──────────────────────────

  LibBook? _bookOf(ReaderSession session, List<LibBook> books) {
    for (final b in books) {
      if (b.key == session.key) return b;
    }
    return null;
  }

  List<LibChapter> _chaptersOf(LibBook book) => [...book.chapters]..sort((a, b) => a.no.compareTo(b.no));

  ({LibChapter? prev, LibChapter? next}) _siblingsOf(ReaderSession session, List<LibBook> books) {
    if (session.chapterNo == null) return (prev: null, next: null);
    final book = _bookOf(session, books);
    if (book == null) return (prev: null, next: null);
    final list = _chaptersOf(book);
    final i = list.indexWhere((c) => c.no == session.chapterNo);
    if (i < 0) return (prev: null, next: null);
    return (prev: i > 0 ? list[i - 1] : null, next: i < list.length - 1 ? list[i + 1] : null);
  }

  void _openChapter(ReaderSession session, LibChapter chapter) {
    ref
        .read(readerSessionProvider.notifier)
        .open(
          ReaderSession(
            key: session.key,
            chapterNo: chapter.no,
            pages: chapter.pageCount,
            translated: chapter.translatedSeqs,
          ),
        );
    setState(() => _endOpen = false);
    _zoom.reset();
    _showOsd(AppLocalizations.of(context).readerPage(1, chapter.pageCount), _chapterSubByNo(chapter.no));
  }

  String _chapterSub(ReaderSession session) => _chapterSubByNo(session.chapterNo!);

  String _chapterSubByNo(double no) => AppLocalizations.of(context).chapterTitle(jsNumStr(no));

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(readerSessionProvider);
    final prefs = ref.watch(readerPrefsProvider);

    // 沉浸式状态栏跟着偏好走（首帧后应用，避免 build 期间下发系统调用）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSystemUi();
      _syncWakelock();
    });
    _maybeScheduleTapHint();

    if (session == null || session.pages <= 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.shelfEmpty,
              style: TextStyle(fontSize: AppFont.px12_5, color: palette.textSecondary),
            ),
            const SizedBox(height: 10),
            AppButton(
              label: l10n.readerClose,
              onTap: () => context.go('/manga/library'),
              variant: AppButtonVariant.link,
              fontSize: AppFont.px12,
            ),
          ],
        ),
      );
    }

    // 换书 / 换话：把控制器挪回第一页（页码本身已由 `open()` 归零）。
    //
    // ⚠️ 只在**同一份 State 内**会话变了才跳。首次构建（`_openedSession == null`）
    // 必须什么都不做 —— 那时控制器已按 [readerPageProvider] 的页码初始化，
    // 一跳就会把「重建后续读」硬拽回第 1 页。
    final sessionTag = '${session.key}/${session.chapterNo ?? ''}/${session.pages}';
    final previousTag = _openedSession;
    _openedSession = sessionTag;
    final total = session.pages;
    if (previousTag != null && previousTag != sessionTag) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 跳的是**页码事实源**，不是硬编码 0：点「第 N 页」进来时页码已设好，
        // 写死 0 会把用户刚点的那一页吃掉。
        if (mounted && _controller.hasClients) {
          _controller.jumpToPage(ref.read(readerPageProvider).clamp(0, total - 1));
        }
      });
    }

    // 页码从 provider 来：路由重建后能续读；页数变少（换书 / 后端数据变化）时兜底夹住。
    final page = ref.watch(readerPageProvider);
    final index = page.clamp(0, total - 1);
    if (page != index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(readerPageProvider.notifier).set(index);
      });
    }
    if (context.isMobile && _clock.isEmpty) {
      _clock = _formatClock();
    }
    final mobile = context.isMobile;
    _mobile = mobile;
    // 上一话 / 下一话 / 章节抽屉都要靠书架数据：必须 watch，
    // 否则书架加载完这一帧拿到的仍是空列表，按钮永远灰着。
    final books = ref.watch(libraryProvider).value ?? const <LibBook>[];
    final siblings = _siblingsOf(session, books);
    final book = _bookOf(session, books);

    return PopScope(
      // 全屏阅读时壳层导航是隐藏的：系统返回手势 = 关闭阅读器（回漫画库），
      // 而不是把整个 App 退出或抛给 go_router 处理分支栈。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      // 只保留 autofocus（让焦点留在阅读器里）；**不挂 onKeyEvent** ——
      // 同一次按键会被 HardwareKeyboard handler 和 Focus 各处理一遍，
      // G / C 这种开关翻转两次等于没反应。
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Positioned.fill(child: _nightWrap(prefs, _stage(context, session, prefs, index, total, book, siblings))),
            // 沉浸式自绘时钟：只在工具栏收起时画 —— 工具栏在时那一行是标题，
            // 两个都画会压在返回键上。
            if (mobile && prefs.immersive && !_barVisible)
              Positioned(
                left: 26,
                top: 8,
                child: IgnorePointer(child: ReaderClock(text: _clock)),
              ),
            // 点按分区可视化（首次进入 2s）。
            if (mobile)
              Positioned.fill(
                child: TapZoneHint(rtl: prefs.rtl, visible: _hintVisible, opacity: _hintOpacity),
              ),
            // 页码 / 换话 OSD。
            if (mobile)
              Positioned.fill(
                child: Align(
                  alignment: const Alignment(0, -0.24),
                  child: ReaderOsd(main: _osdMain, sub: _osdSub, visible: _osdVisible),
                ),
              ),
            // 亮度 OSD（左缘居中）。
            if (mobile)
              Positioned.fill(
                child: Align(
                  alignment: const Alignment(-0.72, 0),
                  child: BrightOsd(value: prefs.brightness, visible: _brightVisible),
                ),
              ),
            // 顶栏（玻璃，可自动隐藏）。
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: AnimatedSlide(
                offset: _barVisible ? Offset.zero : const Offset(0, -1),
                duration: AppMotion.fast,
                curve: AppMotion.morphCurve,
                child: mobile
                    ? SafeArea(bottom: false, child: _topBar(session, l10n, index, total))
                    : _bar(session, l10n, index, total),
              ),
            ),
            // 底栏（移动端专属：上一话 / 滑条 / 页码 / 下一话 + 五动作）。
            if (mobile)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSlide(
                  offset: _barVisible ? Offset.zero : const Offset(0, 1),
                  duration: AppMotion.fast,
                  curve: AppMotion.morphCurve,
                  child: IgnorePointer(
                    ignoring: !_barVisible,
                    child: AnimatedBuilder(
                      animation: _hideCtrl,
                      builder: (context, _) => ReaderBottomBar(
                        pageValue: index,
                        pageCount: total,
                        onPageChanged: (p) => _jumpMobile(p, total),
                        mode: prefs.mode,
                        onToggleMode: () => ref
                            .read(readerPrefsProvider.notifier)
                            .setMode(prefs.mode == ReaderMode.webtoon ? ReaderMode.paged : ReaderMode.webtoon),
                        night: prefs.night,
                        onNight: (n) => ref.read(readerPrefsProvider.notifier).setNight(n),
                        brightness: prefs.brightness,
                        onBrightness: (v) => ref.read(readerPrefsProvider.notifier).setBrightness(v),
                        // 没有目录（未归并单话 / 书架还没加载）就置灰：点了没反应比灰着更糟。
                        onChapters: (book == null || book.chapters.isEmpty) ? null : () => _openChapters(session, book),
                        onSettings: _openSettings,
                        hideProgress: _barVisible ? _hideCtrl.value : 0,
                        onPrevChapter: siblings.prev == null ? null : () => _openChapter(session, siblings.prev!),
                        onNextChapter: siblings.next == null ? null : () => _openChapter(session, siblings.next!),
                        onInteract: _armBarTimer,
                      ),
                    ),
                  ),
                ),
              ),
            // 章末衔接卡（翻页模式拖到末页）：× / 点遮罩都能关。
            if (_endOpen) Positioned.fill(child: _endOverlay(session, book, siblings, prefs)),
            // 网格总览（桌面端）：缩略图点选跳页，当前页主色描边。
            if (_gridOpen && !mobile)
              Positioned.fill(
                child: Container(
                  color: palette.bg.withValues(alpha: 0.94),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Text(
                              l10n.readerGrid,
                              style: TextStyle(
                                fontSize: AppFont.px13,
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            AppButton(
                              label: l10n.readerClose,
                              onTap: () => setState(() => _gridOpen = false),
                              variant: AppButtonVariant.ghost,
                              height: 26,
                              horizontalPadding: 10,
                              fontSize: AppFont.px10_5,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 150,
                            childAspectRatio: 0.72,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                          ),
                          itemCount: total,
                          itemBuilder: (context, i) => GridCell(
                            session: session,
                            seq: i + 1,
                            showOriginal: _showOriginal,
                            current: i == index,
                            onTap: () {
                              _jumpTo(i + 1, total);
                              setState(() => _gridOpen = false);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 快捷键速查卡（`?`）：Esc / 点遮罩 / × 都能关。
            if (_helpOpen) Positioned.fill(child: ReaderHelpCard(onClose: () => setState(() => _helpOpen = false))),
            // 亮度遮罩（物理亮度语义：盖住包括工具栏在内的一切）。
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: (1 - prefs.brightness) * 0.72)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 全局键盘入口（`HardwareKeyboard` handler）。
  ///
  /// 三个守卫，缺一个都会出事：
  /// - 阅读器**可见**：被别的模块保活时它 offstage，`isCurrent` 仍是 true；
  /// - 阅读器必须是**当前路由**：抽屉（`showGeneralDialog` / bottom sheet）
  ///   打开时它就不是 current，此时放行，方向键归弹层里的滑条；
  /// - 必须有会话：无会话时按键无意义。
  /// 端点差异交给 `_onKey`：桌面键只在桌面分支处理，移动端只会命中
  /// 方向键 / Esc / 音量键。
  bool _onHardwareKey(KeyEvent event) {
    if (!mounted) return false;
    // 被别的模块保活时（IndexedStack 里 offstage + TickerMode 关）：
    // `ModalRoute.isCurrent` 依然是 true，但用户根本看不到阅读器 ——
    // 不挡的话，在设置页的输入框里敲 C 会被当成「切换对照」。
    if (!TickerMode.getValuesNotifier(context).value.enabled) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    final session = ref.read(readerSessionProvider);
    if (session == null || session.pages <= 0) return false;
    return _onKey(event, session.pages, ref.read(readerPrefsProvider)) == KeyEventResult.handled;
  }

  KeyEventResult _onKey(KeyEvent event, int total, ReaderPrefs prefs) {
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    if (!isDown && !isRepeat) return KeyEventResult.ignored;

    // 带 ⌘ / Ctrl / Alt 的组合键一律放行：全局 handler 不看焦点，
    // 不排除的话 ⌘C 会被当成「C = 对照」吃掉（复制 / 系统快捷键全哑）。
    // Shift 不算：`?` 本身就是 Shift+/，`+` 需要 Shift+=。
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isMetaPressed || kb.isAltPressed) return KeyEventResult.ignored;

    // 方向键：RTL 时镜像；按住可连发（KeyRepeatEvent 也走这条）。
    final rtl = prefs.rtl;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _go(rtl ? -1 : 1, total);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _go(rtl ? 1 : -1, total);
      return KeyEventResult.handled;
    }
    // 其余快捷键只在「按下」时处理：连发会把 C/G/O/F 这类开关连点成风车。
    if (!isDown) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Esc 的归属裁决：先关最上面那层，全屏时只退全屏，最后才关阅读器。
      if (_helpOpen) {
        setState(() => _helpOpen = false);
        return KeyEventResult.handled;
      }
      if (_gridOpen) {
        setState(() => _gridOpen = false);
        return KeyEventResult.handled;
      }
      if (_compare) {
        setState(() => _compare = false);
        return KeyEventResult.handled;
      }
      if (_endOpen) {
        setState(() => _endOpen = false);
        return KeyEventResult.handled;
      }
      if (_focusOn) {
        unawaited(_toggleFocus());
        return KeyEventResult.handled;
      }
      _close();
      return KeyEventResult.handled;
    }

    if (!context.isMobile) {
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        setState(() => _compare = !_compare);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyG) {
        setState(() => _gridOpen = !_gridOpen);
        return KeyEventResult.handled;
      }
      // O：原图 ⇄ 译文（250ms 交叉淡入由舞台的 AnimatedSwitcher 负责）。
      if (event.logicalKey == LogicalKeyboardKey.keyO) {
        _toggleOriginal();
        return KeyEventResult.handled;
      }
      // F：全屏（全屏时 Esc 只退全屏）。
      if (event.logicalKey == LogicalKeyboardKey.keyF) {
        unawaited(_toggleFocus());
        return KeyEventResult.handled;
      }
      // ?：Shift + / —— 呼出快捷键速查卡。
      if (event.logicalKey == LogicalKeyboardKey.question ||
          (event.logicalKey == LogicalKeyboardKey.slash && HardwareKeyboard.instance.isShiftPressed)) {
        setState(() => _helpOpen = !_helpOpen);
        return KeyEventResult.handled;
      }
      // +/− 步进缩放（设计稿快捷键表，25% 一档，50–200%）。
      if (event.logicalKey == LogicalKeyboardKey.equal || event.logicalKey == LogicalKeyboardKey.numpadAdd) {
        _zoom.step(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.minus || event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
        _zoom.step(-1);
        return KeyEventResult.handled;
      }
    }

    // 音量键翻页（仅安卓，且设置里开着）：volumeUp = 下一页、volumeDown = 上一页。
    if (!context.isMobile || !prefs.volumeKeys) return KeyEventResult.ignored;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 音量键在 LogicalKeyboardKey 标准表里没有命名键 —— 用 USB HID 用法识别
      // （consumer page：0x0c00e9 = 音量+、0x0c00ea = 音量−）。
      const volumeUp = 0x000c00e9, volumeDown = 0x000c00ea;
      if (event.physicalKey.usbHidUsage == volumeUp) {
        _mobileGo(prefs.rtl ? -1 : 1, total);
        return KeyEventResult.handled;
      }
      if (event.physicalKey.usbHidUsage == volumeDown) {
        _mobileGo(prefs.rtl ? 1 : -1, total);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// 对照里点某一侧 = 退出对照并只显示那一侧（设计稿口径）。
  void _focusSide({required bool original}) {
    setState(() {
      _compare = false;
      _showOriginal = original;
    });
    persistReaderShowOriginal(original);
  }

  /// 专注模式（F / 顶栏全屏按钮）：**应用级别全屏** + 隐藏壳层，只显示阅读器。
  ///
  /// 用 `setFullScreen` 而不是 `maximize`：macOS 的 `maximize` 实际是 `zoom:`
  /// ——只把窗口切到「标准大小」，既不铺满屏幕、也不隐藏菜单栏，
  /// 看起来就是「变大了但没全屏」。全屏必须走 `setFullScreen`。
  Future<void> _toggleFocus() async {
    final next = !_focusOn;
    _focusOn = next;
    _focusNotifier?.set(next);
    if (_mobile || kIsWeb) return;
    try {
      if (next) {
        _wasFullScreen = await windowManager.isFullScreen();
        if (!_wasFullScreen) await windowManager.setFullScreen(true);
      } else if (!_wasFullScreen) {
        await windowManager.setFullScreen(false);
      }
      // 记「真的全屏了吗」：`setFullScreen` 是异步系统调用，可能失败
      // （某些 Linux WM / 无窗口管理器）。顶部让位按真实结果决定。
      _fullscreenNotifier?.set(await windowManager.isFullScreen());
    } catch (_) {
      // 没有窗口管理器（测试 / Web）时静默：专注模式的状态位照切，
      // 让位仍按平台给（macOS 避免红绿灯压住顶栏）。
      _fullscreenNotifier?.set(false);
    }
  }

  /// 离开阅读器前还壳（关闭 / 切页 / 切模块都会走到）。
  void _exitFocus() {
    if (!_focusOn) return;
    _focusOn = false;
    _focusNotifier?.set(false);
    _fullscreenNotifier?.set(false);
    if (!_mobile && !kIsWeb && !_wasFullScreen) {
      unawaited(windowManager.setFullScreen(false).catchError((_) {}));
    }
  }

  /// 移动端翻页（不走 PageView）。
  void _mobileGo(int delta, int total) {
    final next = (_index + delta).clamp(0, total - 1);
    if (next == _index) return;
    _commitPage(next, total);
    _showOsdForPage(next, total);
  }

  Widget _stage(
    BuildContext context,
    ReaderSession session,
    ReaderPrefs prefs,
    int index,
    int total,
    LibBook? book,
    ({LibChapter? prev, LibChapter? next}) siblings,
  ) {
    if (prefs.mode == ReaderMode.webtoon) {
      return ReaderWebtoonView(
        session: session,
        showOriginal: _showOriginal,
        onCenterTap: _toggleBar,
        // 条漫的尾巴卡与翻页浮层共用同一张卡：文案与去向都由屏幕统一给。
        endCard: ReaderEndCard(
          nextLabel: _endNextLabel(session, book, siblings),
          backLabel: _endBackLabel(session, book),
          onNext: () => _endNext(session, book, siblings),
          onBack: _endBackAction(session, book, siblings),
        ),
      );
    }
    if (context.isMobile) {
      return MobileReaderStage(
        session: session,
        index: index,
        showOriginal: _showOriginal,
        prefs: prefs,
        onPage: (p) {
          ref.read(readerPageProvider.notifier).set(p);
          // 翻页 OSD 由设置里的「显示页码」总开关控制（_showOsd 内部判 prefs.pageNum）。
          _showOsdForPage(p, total);
          if (_barVisible) _armBarTimer();
          _preload(p, total);
        },
        onToggleBar: _toggleBar,
        onBrightnessDelta: _nudgeBrightness,
        onEndReached: () => setState(() => _endOpen = true),
      );
    }
    return _desktopStage(context, session, prefs, index, total);
  }

  Widget _desktopStage(BuildContext context, ReaderSession session, ReaderPrefs prefs, int index, int total) {
    final palette = AppPalette.of(context);
    // 舞台内容按模式分叉，**外壳共用**：滚轮 / 触控板横扫 / 轻推 /
    // 两侧 56px 热区都要在对照里同样可用 —— 之前对照是另一套 Row，
    // 结果「左右翻页按钮」和横扫一起丢了。
    final body = _compare ? _compareBody(context, session, index, total) : _pagesBody(session, index, total);

    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: _onPointerSignal,
            onPointerPanZoomStart: (_) => _panZoomScale = 1,
            onPointerPanZoomUpdate: _onPanZoom,
            child: AnimatedBuilder(
              animation: _nudgeCtrl,
              builder: (context, child) => Transform.translate(offset: Offset(_nudgeDx, 0), child: child),
              child: body,
            ),
          ),
        ),
        // 底部提示条（设计稿 `.foot`）：随工具栏一起隐藏。
        if (_barVisible) const Positioned(left: 0, right: 0, bottom: 0, child: ReaderFootBar()),
        // 缩放 OSD 只在单页模式有意义：对照的两栏各自 InteractiveViewer，`_zoom` 不参与。
        if (!_compare)
          Positioned(
            left: 0,
            right: 0,
            top: 8,
            child: Center(child: ZoomOsd(zoom: _zoom)),
          ),
        // 点击两侧翻页（两种模式共用）：对照里也需要看得见的翻页入口。
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 56,
          child: GestureDetector(
            key: const Key('reader-hotzone-prev'),
            behavior: HitTestBehavior.translucent,
            onTap: () => _go(-1, total),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(LucideIcons.chevronLeft, size: 20, color: palette.textSecondary),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 56,
          child: GestureDetector(
            key: const Key('reader-hotzone-next'),
            behavior: HitTestBehavior.translucent,
            onTap: () => _go(1, total),
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(LucideIcons.chevronRight, size: 20, color: palette.textSecondary),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 单页舞台：与在线阅读器共用 [PagedReaderStage]（PageView + 缩放）。
  Widget _pagesBody(ReaderSession session, int index, int total) {
    return PagedReaderStage(
      controller: _controller,
      zoom: _zoom,
      pageCount: total,
      index: index,
      onPageChanged: (i) {
        ref.read(readerPageProvider.notifier).set(i);
        if (_barVisible) _armBarTimer();
        _preload(i, total);
      },
      onTap: _toggleBar,
      pageBuilder: (context, i) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: ReaderPage(
          key: ValueKey('img-$i-$_showOriginal'),
          session: session,
          seq: i + 1,
          showOriginal: _showOriginal,
        ),
      ),
    );
  }

  /// 对照舞台：原文/译文双栏。
  ///
  /// 点击口径（2026-11-08 用户裁定，覆盖设计稿原案）：**点图不退出对照**，
  /// 而是按整舞台宽度三分区翻页 / 呼出工具栏 —— 在对照里看两版图，
  /// 恰恰是最需要「点一下继续翻」的场景，退出对照反而打断。
  /// 退出对照仍走 C 键 / 顶栏对照按钮 / Esc / 「显示原图·显示翻译」。
  Widget _compareBody(BuildContext context, ReaderSession session, int index, int total) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final stageWidth = box.maxWidth;
        // 两栏各占一半（中间 1px 分隔线忽略不计）。
        void handleTap(double globalX) {
          if (globalX < stageWidth * 0.3) {
            _go(-1, total);
          } else if (globalX > stageWidth * 0.7) {
            _go(1, total);
          } else {
            _toggleBar();
          }
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ComparePane(
                title: l10n.readerPaneOriginal,
                showOriginal: true,
                session: session,
                seq: index + 1,
                onTapAt: (p) => handleTap(p.dx),
              ),
            ),
            Container(width: 1, color: palette.divider),
            Expanded(
              child: ComparePane(
                title: l10n.readerPaneTranslated,
                showOriginal: false,
                session: session,
                seq: index + 1,
                onTapAt: (p) => handleTap(stageWidth / 2 + p.dx),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 移动端顶栏（玻璃）：返回 + 标题/话名 + 原文⇄译文 chip。
  Widget _topBar(ReaderSession session, AppLocalizations l10n, int index, int total) {
    return ReaderTopBar(
      title: session.key,
      subtitle: session.chapterNo == null
          ? ''
          : '${l10n.chapterTitle(jsNumStr(session.chapterNo!))} · ${l10n.readerPage(index + 1, total)}',
      toggleLabel: _showOriginal ? l10n.readerShowTranslated : l10n.readerShowOriginal,
      onToggle: _toggleOriginal,
      onClose: _close,
    );
  }

  /// 桌面顶栏（页码 / 缩放 / 原文切换 / 对照 / 网格 / 关闭）。
  Widget _bar(ReaderSession session, AppLocalizations l10n, int index, int total) {
    return ReaderBar(
      title: session.chapterNo == null
          ? session.key
          : '${session.key} · ${l10n.chapterTitle(jsNumStr(session.chapterNo!))}',
      pageText: l10n.readerPage(index + 1, total),
      toggleLabel: _showOriginal ? l10n.readerShowTranslated : l10n.readerShowOriginal,
      onToggle: _toggleOriginal,
      onClose: _close,
      pageValue: index,
      pageCount: total,
      onPageChanged: (p) => _jumpTo(p, total),
      onSettings: _openSettings,
      onCompare: () => setState(() => _compare = !_compare),
      onCompareActive: _compare,
      onGrid: () => setState(() => _gridOpen = !_gridOpen),
      onGridActive: _gridOpen,
      onFullscreen: context.isMobile ? null : () => unawaited(_toggleFocus()),
      onHelp: context.isMobile ? null : () => setState(() => _helpOpen = true),
      zoom: context.isMobile ? null : _zoom,
    );
  }

  bool _isSingleChapter(ReaderSession session, LibBook? book) =>
      session.chapterNo == null || book == null || !book.isBook;

  /// 夜间滤镜（设计稿 mobile.html `.tint`）：只作用在页面内容上，工具栏保持可读。
  ///
  /// 强度取 `prefs.nightIntensity`（0.2–1.0），各档基准系数按「强度 40% 时
  /// 等于设计稿原值」反推：暖 0.25 / 黑 1.125（夹到 0.85）/ 红 0.5。
  Widget _nightWrap(ReaderPrefs prefs, Widget child) {
    final k = prefs.nightIntensity;
    return switch (prefs.night) {
      ReaderNight.warm => NightTint(
        color: const Color(0xFFFF9A3C).withValues(alpha: 0.25 * k),
        child: child,
      ),
      ReaderNight.black => NightTint(
        color: Colors.black.withValues(alpha: (1.125 * k).clamp(0.0, 0.85)),
        desaturate: true,
        child: child,
      ),
      ReaderNight.red => NightTint(
        color: const Color(0xFFB22222).withValues(alpha: 0.5 * k),
        child: child,
      ),
      ReaderNight.off => child,
    };
  }

  /// 章末卡主按钮文案：有下一话 = 「下一话」，否则这一本到头了 = 「回书架」。
  String? _endNextLabel(ReaderSession session, LibBook? book, ({LibChapter? prev, LibChapter? next}) siblings) =>
      siblings.next == null ? AppLocalizations.of(context).readerEndcardBackShelf : null;

  /// 章末卡副按钮文案：有目录 = 「回目录」，未归并单话 = 「回书架」。
  String _endBackLabel(ReaderSession session, LibBook? book) => _isSingleChapter(session, book)
      ? AppLocalizations.of(context).readerEndcardBackShelf
      : AppLocalizations.of(context).readerEndcardBack;

  /// 章末卡的副按钮：**文案与主按钮撞车时不给**。
  ///
  /// 单话读到头：主按钮「回书架」（没有下一话）+ 副按钮「回书架」（没有目录）
  /// 会算出两个一模一样的按钮，用户只会觉得是 bug。
  VoidCallback? _endBackAction(ReaderSession session, LibBook? book, ({LibChapter? prev, LibChapter? next}) siblings) {
    final nextLabel = _endNextLabel(session, book, siblings);
    if (nextLabel != null && nextLabel == _endBackLabel(session, book)) return null;
    return () => _endBack(session, book);
  }

  /// 章末浮层：点遮罩关闭；点卡片本身不关（内层 GestureDetector 吃掉）。
  Widget _endOverlay(
    ReaderSession session,
    LibBook? book,
    ({LibChapter? prev, LibChapter? next}) siblings,
    ReaderPrefs prefs,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _endOpen = false),
      child: ColoredBox(
        color: readerStageColor(prefs.stageBg).withValues(alpha: 0.86),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: ReaderEndCard(
              nextLabel: _endNextLabel(session, book, siblings),
              backLabel: _endBackLabel(session, book),
              onClose: () => setState(() => _endOpen = false),
              onNext: () => _endNext(session, book, siblings),
              onBack: _endBackAction(session, book, siblings),
            ),
          ),
        ),
      ),
    );
  }

  void _endNext(ReaderSession session, LibBook? book, ({LibChapter? prev, LibChapter? next}) siblings) {
    final next = siblings.next;
    if (next != null) {
      _openChapter(session, next);
    } else {
      // 没有下一话 = 这一本到头了，主按钮是「回书架」：走书架口径（清选中），
      // 不能只 close 留在上一次选中的书上。
      _endToShelf();
    }
  }

  /// 回书架：关会话 + 落回书架网格（窄屏清选中，否则会停在上次选中的书上）。
  void _endToShelf() {
    ref.read(readerSessionProvider.notifier).close();
    if (context.isMobile) ref.read(selectedBookProvider.notifier).select(null);
    if (context.mounted) context.go('/manga/library');
  }

  /// 「回目录」= 回这本书的章节列表（顺便选中该书，右栏 / 窄屏详情直接落在目录）。
  /// 未归并单话没有目录层级，按「回书架」处理（窄屏顺手清选中，落在书架网格）。
  void _endBack(ReaderSession session, LibBook? book) {
    if (_isSingleChapter(session, book)) {
      _endToShelf();
      return;
    }
    ref.read(readerSessionProvider.notifier).close();
    ref.read(selectedBookProvider.notifier).select(book!.key);
    if (context.mounted) context.go('/manga/library');
  }

  /// 章节抽屉（当前话高亮，点选换话）。
  void _openChapters(ReaderSession session, LibBook? book) {
    if (book == null || book.chapters.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final chapters = _chaptersOf(book);
    final currentIdx = chapters.indexWhere((c) => c.no == session.chapterNo);
    showAppSheet<void>(
      context: context,
      builder: (ctx) => AppSheet(
        title: l10n.readerChaptersTitle,
        subtitle: l10n.readerPage(currentIdx < 0 ? 1 : currentIdx + 1, chapters.length),
        onClose: () => Navigator.of(ctx).pop(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in chapters)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openChapter(session, c);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                  decoration: BoxDecoration(
                    color: c.no == session.chapterNo ? palette.accSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: c.no == session.chapterNo
                              ? palette.acc
                              : (c.done ? palette.good : palette.mut.withValues(alpha: 0.5)),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.chapterTitle(jsNumStr(c.no)),
                          style: TextStyle(
                            fontSize: AppFont.px12_5,
                            fontWeight: c.no == session.chapterNo ? FontWeight.w700 : FontWeight.w500,
                            color: c.no == session.chapterNo ? palette.acc : palette.ink,
                          ),
                        ),
                      ),
                      Text(
                        l10n.readerPage(c.pageCount, c.pageCount),
                        style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 阅读设置抽屉：与在线阅读器共用 [ReaderSettingsSheet]。
  void _openSettings() {
    showAppSheet<void>(context: context, builder: (_) => const ReaderSettingsSheet());
  }

  void _close() {
    _exitFocus();
    ref.read(readerSessionProvider.notifier).close();
    if (context.mounted) context.go('/manga/library');
  }
}

/// 仅测试用：点按分区提示「本次进程只展一次」，用例之间要能重置。
@visibleForTesting
void resetReaderTapHint() => _ReaderScreenState._tapHintShown = false;

/// 分段控件（设计稿 `.setrow .seg`）：等宽按钮组，选中 = 主色底。
/// 「PageView 重新挂载时对齐页码」的薄壳（见 `_desktopStage` 里的注释）。
