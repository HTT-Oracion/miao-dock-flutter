import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../features/manga/controller/reader_focus.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/toast.dart';
import '../controller/online_detail_controller.dart';
import '../data/online_image_loader.dart';
import '../controller/online_reader_controller.dart';
import '../domain/online_error.dart';
import '../domain/online_models.dart';
import 'widgets/online_common.dart';
import 'widgets/online_page_image.dart';
import 'widgets/online_reader_widgets.dart';
import '../../../../shared/responsive.dart';

import 'package:flutter/gestures.dart';

import '../domain/online_download.dart';

/// 在线阅读器（`/manga/online/reader`）。
///
/// 壳层行为与本地阅读器一致：桌面保留 NavRail / AppTitleBar（专注模式才隐藏），
/// 移动端整屏；翻译状态条与翻译本话入口只在本模块新增。
class OnlineReaderScreen extends ConsumerStatefulWidget {
  const OnlineReaderScreen({super.key});

  @override
  ConsumerState<OnlineReaderScreen> createState() => _OnlineReaderScreenState();
}

class _OnlineReaderScreenState extends ConsumerState<OnlineReaderScreen> {
  final FocusNode _focus = FocusNode(debugLabel: 'online-reader');
  final GlobalKey _stageKey = GlobalKey();
  Timer? _hideTimer;
  Timer? _hintTimer;
  bool _opened = false;
  bool _showTapHint = true;
  bool _focusOn = false;
  bool _wasFullScreen = false;
  double _dragDx = 0;
  double _stageWidth = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
    _hintTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showTapHint = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    _focus.dispose();
    if (_focusOn) {
      ref.read(readerFocusProvider.notifier).set(false);
      ref.read(readerFullscreenProvider.notifier).set(false);
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted || _opened) return;
    final launch = ref.read(onlineReaderLaunchProvider);
    if (launch == null) {
      context.go('/manga/online');
      return;
    }
    _opened = true;
    final notifier = ref.read(onlineReaderProvider.notifier);
    await notifier.open(
      source: launch.source,
      comic: launch.comic,
      chapter: launch.chapter,
      chapters: launch.chapters,
      startPage: launch.page,
    );
    if (!mounted) return;
    if (launch.autoTranslate) await notifier.startTranslation();
    if (!mounted) return;
    if (launch.page != null && launch.page! > 1) {
      final l10n = AppLocalizations.of(context);
      showAppToast(context, l10n.onlinePageRestored(launch.page!), tone: ToastTone.info);
    }
    _scheduleHide();
    _focus.requestFocus();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!context.isMobile) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      ref.read(onlineReaderProvider.notifier).setControlsVisible(false);
    });
  }

  void _interact() {
    final state = ref.read(onlineReaderProvider);
    if (state == null) return;
    if (!state.controlsVisible) {
      ref.read(onlineReaderProvider.notifier).setControlsVisible(true);
    }
    _scheduleHide();
    _focus.requestFocus();
  }

  Future<void> _close() async {
    final returnLocation = ref.read(onlineReaderLaunchProvider)?.returnLocation ?? '/manga/online';
    await _exitFocus();
    ref.read(onlineReaderProvider.notifier).close();
    ref.read(onlineReaderLaunchProvider.notifier).clear();
    if (mounted) context.go(returnLocation);
  }

  Future<void> _exitFocus() async {
    if (!_focusOn) return;
    _focusOn = false;
    ref.read(readerFocusProvider.notifier).set(false);
    ref.read(readerFullscreenProvider.notifier).set(false);
    try {
      if (!context.isMobile && !_wasFullScreen) await windowManager.setFullScreen(false);
    } catch (_) {
      // 无窗口管理器（测试 / Web）时忽略。
    }
  }

  Future<void> _toggleFocus() async {
    if (context.isMobile) return;
    final next = !_focusOn;
    _focusOn = next;
    ref.read(readerFocusProvider.notifier).set(next);
    try {
      if (next) {
        _wasFullScreen = await windowManager.isFullScreen();
        if (!_wasFullScreen) await windowManager.setFullScreen(true);
      } else if (!_wasFullScreen) {
        await windowManager.setFullScreen(false);
      }
      ref.read(readerFullscreenProvider.notifier).set(await windowManager.isFullScreen());
    } catch (_) {
      ref.read(readerFullscreenProvider.notifier).set(false);
    }
    if (mounted) setState(() {});
  }

  void _nextPage() {
    ref.read(onlineReaderProvider.notifier).nextPage();
    _interact();
  }

  void _prevPage() {
    ref.read(onlineReaderProvider.notifier).previousPage();
    _interact();
  }

  void _toggleTranslated() {
    final state = ref.read(onlineReaderProvider);
    final l10n = AppLocalizations.of(context);
    if (state == null) return;
    if (!state.canToggleTranslated) {
      showAppToast(context, l10n.onlineTranslateLocked, tone: ToastTone.warn);
      return;
    }
    ref.read(onlineReaderProvider.notifier).setShowOriginal(!state.showOriginal);
    _interact();
  }

  void _compare() {
    showAppToast(context, AppLocalizations.of(context).onlineReaderCompareUnsupported, tone: ToastTone.info);
  }

  void _showGrid(OnlineReaderState state) {
    final l10n = AppLocalizations.of(context);
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => AppSheet(
        title: l10n.onlineReaderGridTitle,
        icon: LucideIcons.grid2x2,
        onClose: () => Navigator.of(sheetContext).pop(),
        width: 400,
        child: OnlineReaderGridContent(
          state: state,
          onPage: (page) {
            Navigator.of(sheetContext).pop();
            ref.read(onlineReaderProvider.notifier).goToPage(page);
            _interact();
          },
        ),
      ),
    );
  }

  void _showChapters(OnlineReaderState state) {
    final l10n = AppLocalizations.of(context);
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => AppSheet(
        title: l10n.onlineReaderChapterTitle,
        icon: LucideIcons.list,
        onClose: () => Navigator.of(sheetContext).pop(),
        width: 400,
        child: OnlineReaderChaptersContent(
          state: state,
          onChapter: (chapter) {
            Navigator.of(sheetContext).pop();
            ref.read(onlineReaderProvider.notifier).switchChapter(chapter: chapter);
            _interact();
          },
        ),
      ),
    );
  }

  void _showSettings(OnlineReaderState state) {
    final l10n = AppLocalizations.of(context);
    final launch = ref.read(onlineReaderLaunchProvider);
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => AppSheet(
        title: l10n.onlineReaderTranslateTitle,
        icon: LucideIcons.languages,
        onClose: () => Navigator.of(sheetContext).pop(),
        width: 400,
        child: OnlineReaderSettingsContent(
          state: state,
          sourceLang: _languageLabel(l10n, launch?.source.manifest.lang ?? ''),
          onRange: (range) => ref.read(onlineReaderProvider.notifier).setRange(range),
          onRetranslate: (value) => ref.read(onlineReaderProvider.notifier).setRetranslate(value),
          onGoSettings: () {
            Navigator.of(sheetContext).pop();
            _goSettings();
          },
        ),
      ),
    );
  }

  void _showBrightness(OnlineReaderState state) {
    final l10n = AppLocalizations.of(context);
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => AppSheet(
        title: l10n.onlineReaderBrightnessTitle,
        icon: LucideIcons.sun,
        onClose: () => Navigator.of(sheetContext).pop(),
        width: 400,
        child: Consumer(
          builder: (context, ref, _) {
            final latest = ref.watch(onlineReaderProvider);
            return OnlineReaderBrightnessContent(
              value: latest?.brightness ?? state.brightness,
              onChanged: (value) => ref.read(onlineReaderProvider.notifier).setBrightness(value),
            );
          },
        ),
      ),
    );
  }

  void _showHelp() {
    final l10n = AppLocalizations.of(context);
    showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: l10n.onlineReaderHelpTitle,
        icon: LucideIcons.keyboard,
        width: 380,
        onClose: () => Navigator.of(dialogContext).pop(),
        actions: [
          AppButton(
            label: l10n.onlineClose,
            onTap: () => Navigator.of(dialogContext).pop(),
            variant: AppButtonVariant.secondary,
            height: 32,
          ),
        ],
        child: const OnlineReaderHelpContent(),
      ),
    );
  }

  String _languageLabel(AppLocalizations l10n, String lang) => switch (lang) {
    'ja' => l10n.onlineLangJapanese,
    'zh' => l10n.onlineLangChinese,
    'en' => l10n.onlineLangEnglish,
    _ => lang,
  };

  void _goSettings() {
    _exitFocus();
    ref.read(onlineReaderProvider.notifier).close();
    ref.read(onlineReaderLaunchProvider.notifier).clear();
    context.go('/settings?section=translate');
  }

  void _onStageTap(OnlineReaderState state, TapUpDetails details) {
    final width = _stageWidth;
    final x = details.localPosition.dx;
    if (state.zoom > 1.01) {
      _interact();
      return;
    }
    if (state.pageError != null || state.loadingPages) return;
    final onLeft = x < width * 0.30;
    final onRight = x > width * 0.70;
    if (onLeft || onRight) {
      // 移动端左右热区只翻页：始终收起工具栏，保持沉浸阅读。
      if (context.isMobile) {
        ref.read(onlineReaderProvider.notifier).setControlsVisible(false);
        if (onLeft) {
          ref.read(onlineReaderProvider.notifier).previousPage();
        } else {
          ref.read(onlineReaderProvider.notifier).nextPage();
        }
      } else if (onLeft) {
        _prevPage();
      } else {
        _nextPage();
      }
      return;
    }
    if (state.controlsVisible) {
      ref.read(onlineReaderProvider.notifier).toggleControls();
    } else {
      ref.read(onlineReaderProvider.notifier).setControlsVisible(true);
      _scheduleHide();
    }
  }

  void _onStageDoubleTap(OnlineReaderState state) {
    final notifier = ref.read(onlineReaderProvider.notifier);
    notifier.setZoom(state.zoom > 1.01 ? 1 : 2.5);
    _interact();
  }

  void _onScroll(PointerScrollEvent event, OnlineReaderState state) {
    if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) {
      final notifier = ref.read(onlineReaderProvider.notifier);
      notifier.setZoom(state.zoom + (event.scrollDelta.dy > 0 ? -0.25 : 0.25));
      return;
    }
    if (state.pageError != null) return;
    if (event.scrollDelta.dy > 0) {
      _nextPage();
    } else if (event.scrollDelta.dy < 0) {
      _prevPage();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final state = ref.read(onlineReaderProvider);
    if (state == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.pageDown) {
      _nextPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.pageUp) {
      _prevPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyT) {
      _toggleTranslated();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyG) {
      _showGrid(state);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _toggleFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      _compare();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.question ||
        (key == LogicalKeyboardKey.slash && HardwareKeyboard.instance.isShiftPressed)) {
      _showHelp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_focusOn) {
        _toggleFocus();
      } else {
        _close();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.numpadAdd) {
      ref.read(onlineReaderProvider.notifier).setZoom(state.zoom + 0.25);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      ref.read(onlineReaderProvider.notifier).setZoom(state.zoom - 0.25);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    ref.listen<OnlineReaderState?>(onlineReaderProvider, (previous, next) {
      final before = previous?.translation.state;
      final after = next?.translation.state;
      if (after == TranslationState.done && before != TranslationState.done) {
        showAppToast(context, l10n.onlineTranslateDoneToast(next?.translation.total ?? 0), tone: ToastTone.good);
      }
    });
    final state = ref.watch(onlineReaderProvider);
    if (state == null) {
      return ColoredBox(
        color: palette.bg,
        child: const Center(child: OnlineReaderSpinner()),
      );
    }
    _stageWidth = MediaQuery.sizeOf(context).width;
    final visible = state.controlsVisible;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _exitFocus();
          ref.read(onlineReaderProvider.notifier).close();
        }
      },
      child: Material(
        color: palette.bg,
        child: KeyboardListener(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (event) => _onKey(_focus, event),
          child: Column(
            children: [
              if (!context.isMobile || visible)
                _SlideBar(
                  visible: visible,
                  offset: const Offset(0, -0.35),
                  child: SafeArea(
                    bottom: false,
                    child: OnlineReaderTopBar(
                      state: state,
                      mobile: context.isMobile,
                      onBack: _close,
                      onClose: _close,
                      onPage: (page) {
                        ref.read(onlineReaderProvider.notifier).goToPage(page);
                        _interact();
                      },
                      onOriginal: () {
                        ref.read(onlineReaderProvider.notifier).setShowOriginal(true);
                        _interact();
                      },
                      onTranslated: _toggleTranslated,
                      onTranslate: () {
                        ref.read(onlineReaderProvider.notifier).startTranslation();
                        _interact();
                      },
                      onCompare: _compare,
                      onGrid: () => _showGrid(state),
                      onChapters: () => _showChapters(state),
                      onHelp: _showHelp,
                      onFullscreen: _toggleFocus,
                      onSettings: () => _showSettings(state),
                      onZoom: () {
                        ref.read(onlineReaderProvider.notifier).cycleZoom();
                        _interact();
                      },
                    ),
                  ),
                ),
              if (!context.isMobile || visible)
                _SlideBar(
                  visible: visible,
                  offset: const Offset(0, -0.35),
                  child: OnlineTranslationBar(
                    state: state,
                    mobile: context.isMobile,
                    onTranslate: () {
                      ref.read(onlineReaderProvider.notifier).startTranslation();
                      _interact();
                    },
                    onRetry: () {
                      ref.read(onlineReaderProvider.notifier).retryTranslation();
                      _interact();
                    },
                    onOriginal: () {
                      ref.read(onlineReaderProvider.notifier).onlyOriginal();
                      _interact();
                    },
                    onSettings: () => _showSettings(state),
                  ),
                ),
              Expanded(
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) _onScroll(event, state);
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _stageWidth = constraints.maxWidth;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => _onStageTap(state, details),
                        onDoubleTap: () => _onStageDoubleTap(state),
                        onHorizontalDragStart: (_) => _dragDx = 0,
                        onHorizontalDragUpdate: (details) => _dragDx += details.delta.dx,
                        onHorizontalDragEnd: (_) {
                          if (!context.isMobile || state.zoom > 1.01 || state.webtoon) return;
                          final page = pageFromSwipe(
                            dx: _dragDx,
                            page: state.page,
                            pageCount: state.pageCount,
                            width: constraints.maxWidth,
                          );
                          if (page != state.page) {
                            ref.read(onlineReaderProvider.notifier).goToPage(page);
                            // 移动端滑动翻页不叫出工具栏。
                            if (context.isMobile) {
                              ref.read(onlineReaderProvider.notifier).setControlsVisible(false);
                            } else if (state.controlsVisible) {
                              _interact();
                            }
                          }
                          _dragDx = 0;
                        },
                        child: Stack(
                          key: _stageKey,
                          children: [
                            Positioned.fill(child: ColoredBox(color: onlineReaderStageColor())),
                            Positioned.fill(child: _stageBody(context, state)),
                            if (context.isMobile && _showTapHint) const Positioned.fill(child: _TapHintOverlay()),
                            if (state.osdVisible &&
                                !state.pageLoading &&
                                !state.loadingPages &&
                                state.pageError == null)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Center(child: _Osd(state: state)),
                                ),
                              ),
                            if (state.night)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ColoredBox(
                                    color: Color.lerp(palette.shadow, palette.blue, 0.2)!.withValues(alpha: 0.32),
                                  ),
                                ),
                              ),
                            if (state.brightness < 1)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ColoredBox(
                                    color: palette.shadow.withValues(alpha: (1 - state.brightness) * 0.75),
                                  ),
                                ),
                              ),
                            if (!context.isMobile && !state.webtoon) ...[
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                child: _EdgeButton(
                                  left: true,
                                  tooltip: l10n.onlineReaderPrevPage,
                                  enabled: state.page > 1 && state.pageError == null,
                                  onTap: _prevPage,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                bottom: 0,
                                child: _EdgeButton(
                                  left: false,
                                  tooltip: l10n.onlineReaderNextPage,
                                  enabled: state.page < state.pageCount && state.pageError == null,
                                  onTap: _nextPage,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (!context.isMobile || visible)
                _SlideBar(
                  visible: visible,
                  offset: const Offset(0, 0.35),
                  child: context.isMobile
                      ? OnlineReaderMobileBottomBar(
                          state: state,
                          onPage: (page) {
                            ref.read(onlineReaderProvider.notifier).goToPage(page);
                            _interact();
                          },
                          onPrevChapter: () {
                            final chapter = state.prevChapter;
                            if (chapter != null) {
                              ref.read(onlineReaderProvider.notifier).switchChapter(chapter: chapter);
                              _interact();
                            }
                          },
                          onNextChapter: () {
                            final chapter = state.nextChapter;
                            if (chapter != null) {
                              ref.read(onlineReaderProvider.notifier).switchChapter(chapter: chapter);
                              _interact();
                            }
                          },
                          onNight: () {
                            ref.read(onlineReaderProvider.notifier).toggleNight();
                            _interact();
                          },
                          onWebtoon: () {
                            ref.read(onlineReaderProvider.notifier).toggleWebtoon();
                            _interact();
                          },
                          onBrightness: () => _showBrightness(state),
                          onChapters: () => _showChapters(state),
                          onSettings: () => _showSettings(state),
                        )
                      : const OnlineReaderFootBar(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stageBody(BuildContext context, OnlineReaderState state) {
    if (state.loadingPages) {
      return OnlineReaderStageStatus(
        icon: LucideIcons.image,
        title: AppLocalizations.of(context).onlineReaderLoading,
        hint: AppLocalizations.of(context).onlineReaderLoadingHint,
      );
    }
    if (state.pagesError != null) {
      return OnlineReaderStageStatus(
        icon: LucideIcons.wifiOff,
        title: AppLocalizations.of(context).onlinePageError,
        hint: AppLocalizations.of(context).onlinePageErrorHint,
        code: 'HTTP_ERROR',
        actions: [
          AppButton(
            label: AppLocalizations.of(context).onlineErrorRetry,
            onTap: () {
              _opened = false;
              _bootstrap();
            },
            variant: AppButtonVariant.primary,
            height: 32,
          ),
        ],
      );
    }
    if (state.webtoon) {
      return _WebtoonStage(
        state: state,
        onTap: _interact,
        onPage: (page) {
          ref.read(onlineReaderProvider.notifier).goToPage(page);
        },
      );
    }
    if (state.pageLoading) {
      final l10n = AppLocalizations.of(context);
      return ColoredBox(
        color: onlineReaderStageColor(),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const OnlineReaderSpinner(),
              const SizedBox(height: 12),
              Text(
                l10n.onlineReaderLoading,
                style: TextStyle(fontSize: AppFont.px11_5, color: AppPalette.of(context).ink2),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.onlineReaderLoadingHint,
                style: TextStyle(fontSize: AppFont.px10, color: AppPalette.of(context).mut),
              ),
            ],
          ),
        ),
      );
    }
    if (state.pageError != null) {
      final l10n = AppLocalizations.of(context);
      return OnlineReaderStageStatus(
        icon: LucideIcons.imageOff,
        title: l10n.onlinePageError,
        hint: l10n.onlinePageErrorHint,
        code: state.pageError is OnlineException
            ? (state.pageError! as OnlineException).code.wireName
            : 'SOURCE_CRASHED',
        actions: [
          AppButton(
            label: l10n.onlinePageRetry,
            onTap: () {
              ref.read(onlineReaderProvider.notifier).retryPage();
              _interact();
            },
            variant: AppButtonVariant.primary,
            height: 32,
          ),
          AppButton(label: l10n.onlinePageSkip, onTap: _nextPage, variant: AppButtonVariant.ghost, height: 32),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = context.isMobile;
        final maxWidth = constraints.maxWidth * (mobile ? 1.0 : 0.88);
        final maxHeight = constraints.maxHeight - (mobile ? 0 : 20);
        final scanning = state.translation.state == TranslationState.running && !state.pageHasTranslation(state.page);
        final translated = state.showingTranslated && state.pageHasTranslation(state.page);
        return Center(
          child: SizedBox(
            width: maxWidth,
            height: maxHeight,
            child: ClipRect(
              child: Transform.scale(
                scale: state.zoom,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(color: AppPalette.of(context).shadow, blurRadius: 50, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: AppMotion.pageSwitch,
                    child: state.pageBytes == null
                        ? const OnlineReaderStageStatus(icon: LucideIcons.image, title: '', hint: '')
                        : OnlinePageImage(
                            key: ValueKey('${state.chapter.id}-${state.page}-$translated-${state.pageBytes!.length}'),
                            page: state.page,
                            bytes: state.pageBytes!,
                            translated: translated,
                            scanning: scanning,
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SlideBar extends StatelessWidget {
  const _SlideBar({required this.visible, required this.offset, required this.child});

  final bool visible;
  final Offset offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: AppMotion.fast,
        curve: AppMotion.morphCurve,
        offset: visible ? Offset.zero : offset,
        child: AnimatedOpacity(duration: AppMotion.fast, opacity: visible ? 1 : 0, child: child),
      ),
    );
  }
}

class _WebtoonPage extends ConsumerStatefulWidget {
  const _WebtoonPage({
    required this.page,
    required this.config,
    required this.sourceId,
    required this.allowedHosts,
    required this.translated,
    required this.scanning,
  });

  final int page;
  final ImageLoadingConfig? config;
  final String sourceId;
  final List<String> allowedHosts;
  final bool translated;
  final bool scanning;

  @override
  ConsumerState<_WebtoonPage> createState() => _WebtoonPageState();
}

class _WebtoonPageState extends ConsumerState<_WebtoonPage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = widget.config;
    if (config == null) {
      setState(() => _failed = true);
      return;
    }
    try {
      final bytes = await ref
          .read(onlineImageLoaderProvider)
          .load(config, sourceId: widget.sourceId, allowedHosts: widget.allowedHosts);
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return ColoredBox(
        color: onlineReaderStageColor(),
        child: Center(child: Icon(LucideIcons.imageOff, color: AppPalette.of(context).ink2)),
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return ColoredBox(
        color: onlineReaderStageColor(),
        child: const Center(child: OnlineReaderSpinner()),
      );
    }
    return OnlinePageImage(page: widget.page, bytes: bytes, translated: widget.translated, scanning: widget.scanning);
  }
}

class _TapHintOverlay extends StatelessWidget {
  const _TapHintOverlay();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    Widget zone(String text, {bool mid = false}) => Expanded(
      flex: mid ? 133 : 100,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.acc.withValues(alpha: 0.05),
          border: Border.all(color: palette.acc.withValues(alpha: 0.5)),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: AppFont.px10, color: mid ? palette.ink2 : palette.acc),
        ),
      ),
    );
    return IgnorePointer(
      child: Row(
        children: [
          zone(l10n.onlineReaderTapPrev),
          zone(l10n.onlineReaderTapMid, mid: true),
          zone(l10n.onlineReaderTapNext),
        ],
      ),
    );
  }
}

class _Osd extends StatelessWidget {
  const _Osd({required this.state});

  final OnlineReaderState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.96),
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Text(
        AppLocalizations.of(context).onlineReaderPageOf(state.page, state.pageCount),
        style: TextStyle(fontSize: AppFont.px14, fontWeight: FontWeight.w600, color: palette.ink),
      ),
    );
  }
}

class _EdgeButton extends StatefulWidget {
  const _EdgeButton({required this.left, required this.tooltip, required this.enabled, required this.onTap});

  final bool left;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_EdgeButton> createState() => _EdgeButtonState();
}

class _EdgeButtonState extends State<_EdgeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final opacity = !widget.enabled ? 0.0 : (_hover ? 1.0 : 0.35);
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: Tooltip(
          message: widget.tooltip,
          child: Container(
            width: 56,
            height: double.infinity,
            alignment: widget.left ? Alignment.centerLeft : Alignment.centerRight,
            padding: EdgeInsets.only(left: widget.left ? 12 : 0, right: widget.left ? 0 : 12),
            decoration: BoxDecoration(
              gradient: _hover && widget.enabled
                  ? LinearGradient(
                      begin: widget.left ? Alignment.centerLeft : Alignment.centerRight,
                      end: widget.left ? Alignment.centerRight : Alignment.centerLeft,
                      colors: [palette.shadow.withValues(alpha: 0.18), palette.shadow.withValues(alpha: 0)],
                    )
                  : null,
            ),
            child: Opacity(
              opacity: opacity,
              child: Icon(
                widget.left ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
                size: 20,
                color: palette.ink2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WebtoonStage extends StatefulWidget {
  const _WebtoonStage({required this.state, required this.onTap, required this.onPage});

  final OnlineReaderState state;
  final VoidCallback onTap;
  final ValueChanged<int> onPage;

  @override
  State<_WebtoonStage> createState() => _WebtoonStageState();
}

class _WebtoonStageState extends State<_WebtoonStage> {
  late final PageController _controller = PageController(
    initialPage: (widget.state.page - 1).clamp(0, widget.state.pageCount > 0 ? widget.state.pageCount - 1 : 0).toInt(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: PageView.builder(
        controller: _controller,
        scrollDirection: Axis.vertical,
        itemCount: widget.state.pageCount,
        onPageChanged: (index) {
          final page = index + 1;
          if (page != widget.state.page) widget.onPage(page);
        },
        itemBuilder: (context, index) {
          final page = index + 1;
          final config = page <= widget.state.pageConfigs.length ? widget.state.pageConfigs[page - 1] : null;
          return Center(
            child: AspectRatio(
              aspectRatio: 930 / 1353,
              child: _WebtoonPage(
                page: page,
                config: config,
                sourceId: widget.state.sourceId,
                allowedHosts: widget.state.sourceHosts,
                translated: widget.state.showingTranslated && widget.state.pageHasTranslation(page),
                scanning:
                    widget.state.translation.state == TranslationState.running &&
                    !widget.state.pageHasTranslation(page),
              ),
            ),
          );
        },
      ),
    );
  }
}
