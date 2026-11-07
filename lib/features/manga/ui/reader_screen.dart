import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// 完整阅读器（B.6）。
///
/// - 桌面：左右方向键 / 点击两侧翻页，滚轮与拖拽缩放；
/// - 移动端：左右滑动翻页、双指缩放（[InteractiveViewer] + [PageView]）。
/// - 页面内容：**有译文显示译文，没有译文回退原图**（miao-dock `viewer.tsx` 同语义），
///   所以「未翻译完也能点查看」。
/// 完整阅读器（B.6）。
///
/// - 桌面：左右方向键 / 点击两侧翻页，滚轮与拖拽缩放；
/// - 移动端：左右滑动翻页、双指缩放（[InteractiveViewer] + [PageView]）。
/// - 页面内容：**有译文显示译文，没有译文回退原图**（miao-dock `viewer.tsx` 同语义），
///   所以「未翻译完也能点查看」。
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _controller = PageController();
  int _index = 0;

  /// 工具栏可见性（重设计稿：点中心呼出/收起，3s 无操作自动隐藏）。
  bool _barVisible = true;
  Timer? _barTimer;

  /// 对照模式（重设计稿桌面端：原文/译文双栏，C 键或按钮切换）。
  bool _compare = false;

  /// 网格总览（重设计稿桌面端：G 键或按钮，缩略图点选跳页）。
  bool _gridOpen = false;

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
    _controller.animateToPage(to, duration: AppMotion.pageSwitch, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _barTimer?.cancel();
    _controller.dispose();
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

    final total = session.pages;
    return Focus(
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
                child: ReaderBar(
                  title: session.chapterNo == null
                      ? session.key
                      : '${session.key} · ${l10n.chapterTitle(jsNumStr(session.chapterNo!))}',
                  pageText: l10n.readerPage(_index + 1, total),
                  toggleLabel: _showOriginal ? l10n.readerShowTranslated : l10n.readerShowOriginal,
                  onToggle: _toggleOriginal,
                  onClose: _close,
                  pageValue: _index,
                  pageCount: total,
                  onPageChanged: (p) => _jumpTo(p, total),
                  onSettings: _openSettings,
                  onCompare: () => setState(() => _compare = !_compare),
                  onCompareActive: _compare,
                  onGrid: () => setState(() => _gridOpen = !_gridOpen),
                  onGridActive: _gridOpen,
                ),
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
                          current: i == _index,
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
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: total,
          onPageChanged: (i) {
            setState(() => _index = i);
            if (_barVisible) _armBarTimer();
            _preload(i, total);
          },
          // key 里带上 showOriginal：切换模式时强制重建该页，确保重新取图。
          itemBuilder: (context, i) => ZoomablePage(
            key: ValueKey('p-$i-$_showOriginal'),
            child: ReaderPage(session: session, seq: i + 1, showOriginal: _showOriginal),
          ),
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
