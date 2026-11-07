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

import '../../../core/storage/shell_prefs.dart';
import '../../../core/theme/tokens.dart';
import '../../../shared/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/app_switch.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';
import 'reader/reader_prefs.dart';
import 'reader/reader_webtoon.dart';
import 'reader/reader_widgets.dart';
import 'reader/reader_zoom.dart';

/// 完整阅读器（B.6）。
///
/// - 桌面：左右方向键 / 点击两侧 / 滚轮 / 触摸板横滑翻页，
///   Ctrl/⌘+滚轮、触摸板捏合与顶栏调节器缩放（翻页归位 100%）；
/// - 移动端：左右滑动翻页、双指捏合缩放（[PinchPage]）。
/// - 页面内容：**有译文显示译文，没有译文回退原图**（miao-dock `viewer.tsx` 同语义），
///   所以「未翻译完也能点查看」。
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
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
    // 重建时直接从上次的页码起翻（服务端页数变少的情况由 build 里的 clamp 兜底）。
    _controller = PageController(initialPage: ref.read(readerPageProvider));
  }

  /// 工具栏可见性（重设计稿：点中心呼出/收起，3s 无操作自动隐藏）。
  bool _barVisible = true;
  Timer? _barTimer;

  /// 对照模式（重设计稿桌面端：原文/译文双栏，C 键或按钮切换）。
  bool _compare = false;

  /// 网格总览（重设计稿桌面端：G 键或按钮，缩略图点选跳页）。
  bool _gridOpen = false;

  /// 缩放状态（桌面）：顶栏调节器 / Ctrl+滚轮 / 触控板捏合共用一份（D-164）。
  final _zoom = ReaderZoom();

  /// 滚轮与触摸板横滑的翻页累计：一次手势只翻一页（正 = 下一页）。
  double _scrollAcc = 0;
  DateTime _lastScrollTurn = DateTime.fromMillisecondsSinceEpoch(0);

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

  /// 桌面滚轮三分支（设计稿 desktop.html 同口径）：
  /// Ctrl/⌘+滚轮 = 锚点缩放；放大态 = 平移；其余 = 翻页。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
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

  /// 预载窗口（重设计稿：前后各 2 页，延后 200ms 等翻页动画结束——只取字节热身
  /// 图片解码缓存，不渲染）。
  void _preload(int index, int total) {
    final session = ref.read(readerSessionProvider);
    if (session == null) return;
    Timer(const Duration(milliseconds: 200), () async {
      final client = ref.read(mangaSvcClientProvider);
      for (final d in [1, -1, 2, -2]) {
        final seq = index + d;
        if (seq < 1 || seq > total) continue;
        final wantTranslated = !_showOriginal && session.translated.contains(seq);
        try {
          if (session.chapterNo == null) {
            await client.getBookFile(session.key, seq, translated: wantTranslated);
          } else {
            await client.getChapterFile(session.key, session.chapterNo!, seq, translated: wantTranslated);
          }
        } catch (_) {
          // 预载失败静默：正式取图路径会再走一次并给出错误 UI。
        }
      }
    });
  }

  void _armBarTimer() {
    _barTimer?.cancel();
    _barTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _barVisible = false);
    });
  }

  void _toggleBar() {
    setState(() => _barVisible = !_barVisible);
    if (_barVisible) _armBarTimer();
  }

  /// 滑条/页码跳页（重设计稿：跳页弹 OSD 级页码气泡——顶栏页码即 OSD）。
  void _jumpTo(int page, int total) {
    final to = page.clamp(0, total - 1);
    if (to == _index) return;
    // 翻页即归位（用户口径）：不留上一页的放大/位移。
    _zoom.reset();
    _controller.animateToPage(to, duration: AppMotion.pageSwitch, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _barTimer?.cancel();
    _controller.dispose();
    _zoom.dispose();
    super.dispose();
  }

  /// 是否显示原图。**默认 false = 看译文**；用户切换后持久化。
  late bool _showOriginal = readReaderShowOriginal();

  void _toggleOriginal() {
    setState(() => _showOriginal = !_showOriginal);
    persistReaderShowOriginal(_showOriginal);
  }

  void _go(int delta, int total) {
    final next = (_index + delta).clamp(0, total - 1);
    if (next == _index) return;
    _zoom.reset();
    _controller.animateToPage(next, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(readerSessionProvider);
    final prefs = ref.watch(readerPrefsProvider);

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
    if (previousTag != null && previousTag != sessionTag) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpToPage(0);
      });
    }

    final total = session.pages;
    // 页码从 provider 来：路由重建后能续读；页数变少（换书 / 后端数据变化）时兜底夹住。
    final page = ref.watch(readerPageProvider);
    final index = page.clamp(0, total - 1);
    if (page != index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(readerPageProvider.notifier).set(index);
      });
    }
    return PopScope(
      // 全屏阅读时壳层导航是隐藏的：系统返回手势 = 关闭阅读器（回漫画库），
      // 而不是把整个 App 退出或抛给 go_router 处理分支栈。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _go(1, total);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _go(-1, total);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (_gridOpen) {
              setState(() => _gridOpen = false);
              return KeyEventResult.handled;
            }
            if (_compare) {
              setState(() => _compare = false);
              return KeyEventResult.handled;
            }
            _close();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyC && !context.isMobile) {
            setState(() => _compare = !_compare);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyG && !context.isMobile) {
            setState(() => _gridOpen = !_gridOpen);
            return KeyEventResult.handled;
          }
          // +/− 步进缩放（设计稿快捷键表，桌面专属；25% 一档，50–200%）。
          if (!context.isMobile &&
              (event.logicalKey == LogicalKeyboardKey.equal || event.logicalKey == LogicalKeyboardKey.numpadAdd)) {
            _zoom.step(1);
            return KeyEventResult.handled;
          }
          if (!context.isMobile &&
              (event.logicalKey == LogicalKeyboardKey.minus || event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
            _zoom.step(-1);
            return KeyEventResult.handled;
          }
          // 音量键翻页（重设计稿，仅安卓 spike）：volumeUp = 下一页、volumeDown = 上一页，
          // RTL 时语义镜像。🔴 spike 说明：真机验证音量键是否被系统优先消费——
          // 若系统拦截则需 platform channel（Android 侧 override onKeyDown），记 P4 尾批待验。
          if (!context.isMobile) return KeyEventResult.ignored;
          if (defaultTargetPlatform == TargetPlatform.android) {
            // 音量键在 LogicalKeyboardKey 标准表里没有命名键 —— 用 USB HID 用法识别
            // （consumer page：0x0c00e9 = 音量+、0x0c00ea = 音量−）。
            const volumeUp = 0x000c00e9, volumeDown = 0x000c00ea;
            final rtl = ref.read(readerPrefsProvider).rtl;
            if (event.physicalKey.usbHidUsage == volumeUp) {
              _go(rtl ? -1 : 1, total);
              return KeyEventResult.handled;
            }
            if (event.physicalKey.usbHidUsage == volumeDown) {
              _go(rtl ? 1 : -1, total);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            Column(
              children: [
                // 工具栏自动隐藏（重设计稿 280ms slideY）：翻页/呼出会重置 3s 计时。
                AnimatedSlide(
                  offset: _barVisible ? Offset.zero : const Offset(0, -1),
                  duration: AppMotion.fast,
                  curve: AppMotion.morphCurve,
                  // 移动端全屏阅读时壳层不再提供 SafeArea，顶栏自己避让状态栏 / 刘海
                  // （设计稿 `.rtop{padding-top:30px}` 同口径）。
                  child: context.isMobile
                      ? SafeArea(bottom: false, child: _bar(session, l10n, index, total))
                      : _bar(session, l10n, index, total),
                ),
                Expanded(
                  // 夜间滤镜（重设计稿：作用于页面内容，工具栏保持可读）。
                  child: switch (prefs.night) {
                    ReaderNight.warm => NightTint(
                      color: const Color(0xFFFF9A3C).withValues(alpha: 0.10),
                      child: _readerStage(context, session, prefs),
                    ),
                    ReaderNight.black => NightTint(
                      color: Colors.black.withValues(alpha: 0.45),
                      desaturate: true,
                      child: _readerStage(context, session, prefs),
                    ),
                    ReaderNight.red => NightTint(
                      color: const Color(0xFFB22222).withValues(alpha: 0.20),
                      child: _readerStage(context, session, prefs),
                    ),
                    ReaderNight.off => _readerStage(context, session, prefs),
                  },
                ),
              ],
            ),
            // 亮度遮罩（物理亮度语义：盖住包括工具栏在内的一切）。
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: (1 - prefs.brightness) * 0.72)),
              ),
            ),
            // 网格总览（重设计稿桌面端）：缩略图点选跳页，当前页主色描边。
            if (_gridOpen)
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
            // 左缘亮度手势（重设计稿移动端）：36px 竖滑调亮度。
            if (context.isMobile)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 36,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (d) {
                    ref
                        .read(readerPrefsProvider.notifier)
                        .setBrightness(prefs.brightness + (d.delta.dy < 0 ? 0.04 : -0.04));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 阅读器顶栏（页码 / 缩放 / 原文切换 / 关闭 / 设置）。
  ///
  /// 抽成方法是因为移动端全屏时要单独套 [SafeArea]（壳层不再提供顶部避让）。
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
      // 桌面专属调节器：移动端靠双指捏合，顶栏放不下也不该放。
      zoom: context.isMobile ? null : _zoom,
    );
  }

  /// 阅读舞台：按模式分流——翻页（PageView + 点按分区 + 两侧点击）或条漫连续滚动。
  Widget _readerStage(BuildContext context, ReaderSession session, ReaderPrefs prefs) {
    if (prefs.mode == ReaderMode.webtoon) {
      return ReaderWebtoonView(session: session, showOriginal: _showOriginal, onCenterTap: _toggleBar);
    }
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final total = session.pages;
    // 对照模式（重设计稿桌面端）：原文/译文双栏，点按分区与翻页手势退出服务。
    if (_compare) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ComparePane(title: l10n.readerPaneOriginal, showOriginal: true, session: session, seq: _index + 1),
          ),
          Container(width: 1, color: palette.divider),
          Expanded(
            child: ComparePane(
              title: l10n.readerPaneTranslated,
              showOriginal: false,
              session: session,
              seq: _index + 1,
            ),
          ),
        ],
      );
    }
    final desktop = !context.isMobile;
    final pages = PageView.builder(
      controller: _controller,
      // 桌面翻页由键盘 / 滚轮 / 触摸板横滑 / 两侧热区驱动：PageView 自己滚会跟舞台
      // 缩放抢手势（放大态拖动应当是平移），所以桌面关掉它（D-164）。
      physics: desktop ? const NeverScrollableScrollPhysics() : null,
      itemCount: total,
      onPageChanged: (i) {
        // 页码写回 provider（不是 setState）：provider 变更会触发本屏重建，
        // 同时保证「切走再回来」还能停在这一页。
        _zoom.reset();
        ref.read(readerPageProvider.notifier).set(i);
        if (_barVisible) _armBarTimer();
        _preload(i, total);
      },
      itemBuilder: (context, i) {
        final page = ReaderPage(session: session, seq: i + 1, showOriginal: _showOriginal);
        // key 里带上 showOriginal：切换模式时强制重建该页，确保重新取图。
        final key = ValueKey('p-$i-$_showOriginal');
        return desktop
            ? ZoomablePage(key: key, zoom: _zoom, onTap: _toggleBar, child: page)
            : PinchPage(key: key, child: page);
      },
    );
    return Stack(
      children: [
        Positioned.fill(
          child: desktop ? Listener(onPointerSignal: _onPointerSignal, child: pages) : pages,
        ),
        // 缩放 OSD（桌面）：顶栏隐藏时捏合也看得到百分比。
        if (desktop)
          Positioned(
            left: 0,
            right: 0,
            top: 8,
            child: Center(child: ZoomOsd(zoom: _zoom)),
          ),
        // 移动端点按分区（重设计稿）：左/右 30% 翻页、中心呼出/收起工具栏。
        if (context.isMobile)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (d) {
                final rel = d.localPosition.dx / MediaQuery.sizeOf(context).width;
                // RTL：左右语义镜像（prefs.rtl）。
                final forwardSide = prefs.rtl ? 0.3 : 0.7;
                final isForward = prefs.rtl ? rel < forwardSide : rel > forwardSide;
                if (rel > 0.3 && rel < 0.7) {
                  _toggleBar();
                } else if (isForward) {
                  _go(1, total);
                } else {
                  _go(-1, total);
                }
              },
            ),
          ),
        // 桌面端点击两侧翻页（移动端用滑动，不挡手势区）。
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 56,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _go(-1, total),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 12),
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
            behavior: HitTestBehavior.translucent,
            onTap: () => _go(1, total),
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(LucideIcons.chevronRight, size: 20, color: palette.textSecondary),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 阅读设置抽屉（重设计稿底部抽屉 380ms 形变）：
  /// 模式 / 夜间三档 / 亮度 / 自动滚动（条漫专属）。
  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.of(context).panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final prefs = ref.watch(readerPrefsProvider);
          final l10n = AppLocalizations.of(context);
          final palette = AppPalette.of(context);
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetLabel(l10n.readerModeTitle),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      AppButton(
                        label: l10n.readerModePaged,
                        onTap: () => ref.read(readerPrefsProvider.notifier).setMode(ReaderMode.paged),
                        variant: prefs.mode == ReaderMode.paged ? AppButtonVariant.primary : AppButtonVariant.secondary,
                        height: 30,
                        horizontalPadding: 14,
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        label: l10n.readerModeWebtoon,
                        onTap: () => ref.read(readerPrefsProvider.notifier).setMode(ReaderMode.webtoon),
                        variant: prefs.mode == ReaderMode.webtoon
                            ? AppButtonVariant.primary
                            : AppButtonVariant.secondary,
                        height: 30,
                        horizontalPadding: 14,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SheetLabel(l10n.readerNightTitle),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      for (final (m, label) in [
                        (ReaderNight.off, l10n.readerNightOff),
                        (ReaderNight.warm, l10n.readerNightWarm),
                        (ReaderNight.black, l10n.readerNightBlack),
                        (ReaderNight.red, l10n.readerNightRed),
                      ]) ...[
                        AppButton(
                          label: label,
                          onTap: () => ref.read(readerPrefsProvider.notifier).setNight(m),
                          variant: prefs.night == m ? AppButtonVariant.primary : AppButtonVariant.secondary,
                          height: 30,
                          horizontalPadding: 13,
                          fontSize: AppFont.px11,
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Text(
                        l10n.readerBrightnessTitle,
                        style: TextStyle(fontSize: AppFont.px12, color: palette.textSecondary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            activeTrackColor: palette.accent,
                            inactiveTrackColor: palette.progressTrack,
                            thumbColor: palette.accent,
                          ),
                          child: Slider(
                            value: prefs.brightness,
                            min: 0.2,
                            max: 1,
                            onChanged: (v) => ref.read(readerPrefsProvider.notifier).setBrightness(v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (prefs.mode == ReaderMode.webtoon) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.readerAutoScroll,
                                style: TextStyle(fontSize: AppFont.px12, color: palette.textPrimary),
                              ),
                              Text(
                                l10n.readerAutoScrollHint,
                                style: TextStyle(fontSize: AppFont.px10, color: palette.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        AppSwitch(
                          value: prefs.autoScroll,
                          onChanged: (_) => ref.read(readerPrefsProvider.notifier).toggleAutoScroll(),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.readerRtl,
                          style: TextStyle(fontSize: AppFont.px12, color: palette.textPrimary),
                        ),
                      ),
                      AppSwitch(value: prefs.rtl, onChanged: (_) => ref.read(readerPrefsProvider.notifier).toggleRtl()),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          );
        },
      ),
    );
  }

  void _close() {
    ref.read(readerSessionProvider.notifier).close();
    if (context.mounted) context.go('/manga/library');
  }
}
