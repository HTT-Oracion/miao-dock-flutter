import 'dart:async';
import 'dart:math' as math;

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
import '../../ui/reader/reader_mobile.dart';
import '../../ui/reader/reader_paged_stage.dart';
import '../../ui/reader/reader_settings.dart';
import '../../ui/reader/reader_widgets.dart';
import '../../ui/reader/reader_prefs.dart';
import '../../ui/reader/reader_stage.dart';
import '../../ui/reader/reader_webtoon_stage.dart';
import '../../ui/reader/reader_zoom.dart';
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
  Timer? _hideTimer;
  Timer? _hintTimer;
  bool _opened = false;
  late final PageController _pageController = PageController();
  final ReaderZoom _zoom = ReaderZoom();
  double _panZoomScale = 1;
  bool _showTapHint = true;
  bool _focusOn = false;
  bool _wasFullScreen = false;

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
    _pageController.dispose();
    _zoom.dispose();
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
    if (launch.autoTranslate && ref.read(onlineReaderProvider)?.translationEnabled == true) {
      await notifier.startTranslation();
    }
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

  void _toggleControls() {
    final state = ref.read(onlineReaderProvider);
    if (state == null) return;
    final next = !state.controlsVisible;
    ref.read(onlineReaderProvider.notifier).setControlsVisible(next);
    if (next) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
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
    final launch = ref.read(onlineReaderLaunchProvider);
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => ReaderSettingsSheet(
        extra: state.translationEnabled
            ? Consumer(
                builder: (context, ref, _) {
                  final l10n = AppLocalizations.of(context);
                  final latest = ref.watch(onlineReaderProvider) ?? state;
                  return OnlineReaderSettingsContent(
                    state: latest,
                    sourceLang: _languageLabel(l10n, launch?.source.sourceLanguage ?? ''),
                    onRange: (range) => ref.read(onlineReaderProvider.notifier).setRange(range),
                    onRetranslate: (value) => ref.read(onlineReaderProvider.notifier).setRetranslate(value),
                    onGoSettings: () {
                      Navigator.of(sheetContext).pop();
                      _goSettings();
                    },
                  );
                },
              )
            : null,
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
        child: OnlineReaderHelpContent(translationEnabled: ref.read(onlineReaderProvider)?.translationEnabled ?? false),
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

  void _onScroll(PointerScrollEvent event, OnlineReaderState state) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      _zoom.scaleAt(event.localPosition, math.exp(-event.scrollDelta.dy * 0.0015));
      return;
    }
    if (_zoom.zoomed) {
      _zoom.panBy(-event.scrollDelta);
      return;
    }
    if (state.pageError != null) return;
    if (event.scrollDelta.dy > 0) {
      _nextPage();
    } else if (event.scrollDelta.dy < 0) {
      _prevPage();
    }
  }

  void _onPanZoom(PointerPanZoomUpdateEvent event) {
    final factor = _panZoomScale == 0 ? 1.0 : event.scale / _panZoomScale;
    if ((factor - 1).abs() > 0.005) {
      _panZoomScale = event.scale;
      _zoom.scaleAt(event.localPosition, factor);
      return;
    }
    if (_zoom.zoomed) _zoom.panBy(-event.panDelta);
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
    if (key == LogicalKeyboardKey.keyT || key == LogicalKeyboardKey.keyO) {
      if (!state.translationEnabled) return KeyEventResult.ignored;
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
      if (!state.translationEnabled) return KeyEventResult.ignored;
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
      _zoom.step(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      _zoom.step(-1);
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
    final prefs = ref.watch(readerPrefsProvider);
    if (state == null) {
      return ColoredBox(
        color: palette.bg,
        child: const Center(child: OnlineReaderSpinner()),
      );
    }
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
          child: Stack(
            children: [
              Positioned.fill(child: _stageArea(context, state, prefs, palette, l10n)),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SlideBar(
                      visible: visible,
                      offset: const Offset(0, -0.35),
                      child: SafeArea(
                        bottom: false,
                        child: context.isMobile
                            ? ReaderTopBar(
                                title: state.comic.title,
                                subtitle: '${state.chapter.title} · ${l10n.readerPage(state.page, state.pageCount)}',
                                toggleLabel: state.showOriginal ? l10n.readerShowTranslated : l10n.readerShowOriginal,
                                onToggle: state.translationEnabled ? _toggleTranslated : null,
                                onClose: _close,
                              )
                            : ReaderBar(
                                title: '${state.comic.title} · ${state.chapter.title}',
                                pageText: l10n.readerPage(state.page, state.pageCount),
                                toggleLabel: state.showOriginal ? l10n.readerShowTranslated : l10n.readerShowOriginal,
                                onToggle: state.translationEnabled ? _toggleTranslated : null,
                                onClose: _close,
                                pageValue: state.page - 1,
                                pageCount: state.pageCount,
                                onPageChanged: (page) {
                                  ref.read(onlineReaderProvider.notifier).goToPage(page + 1);
                                  _interact();
                                },
                                onSettings: () => _showSettings(state),
                                onCompare: state.translationEnabled ? _compare : null,
                                onCompareActive: false,
                                onGrid: () => _showGrid(state),
                                onGridActive: false,
                                onFullscreen: _toggleFocus,
                                onHelp: _showHelp,
                                zoom: _zoom,
                                extra: GestureDetector(
                                  onTap: () => _showChapters(state),
                                  child: Icon(LucideIcons.list, size: 15, color: palette.textSecondary),
                                ),
                              ),
                      ),
                    ),
                    if (state.translationEnabled)
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
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SlideBar(
                  visible: visible,
                  offset: const Offset(0, 0.35),
                  child: context.isMobile
                      ? ReaderBottomBar(
                          pageValue: state.page - 1,
                          pageCount: state.pageCount,
                          onPageChanged: (page) {
                            ref.read(onlineReaderProvider.notifier).goToPage(page + 1);
                            _interact();
                          },
                          mode: prefs.mode,
                          onToggleMode: () {
                            ref
                                .read(readerPrefsProvider.notifier)
                                .setMode(prefs.mode == ReaderMode.webtoon ? ReaderMode.paged : ReaderMode.webtoon);
                            _interact();
                          },
                          night: prefs.night,
                          onNight: (night) {
                            ref.read(readerPrefsProvider.notifier).setNight(night);
                            _interact();
                          },
                          brightness: prefs.brightness,
                          onBrightness: (value) {
                            ref.read(readerPrefsProvider.notifier).setBrightness(value);
                            _interact();
                          },
                          onChapters: () => _showChapters(state),
                          onSettings: () => _showSettings(state),
                          hideProgress: 0,
                          onPrevChapter: state.prevChapter == null
                              ? null
                              : () {
                                  ref.read(onlineReaderProvider.notifier).switchChapter(chapter: state.prevChapter!);
                                  _interact();
                                },
                          onNextChapter: state.nextChapter == null
                              ? null
                              : () {
                                  ref.read(onlineReaderProvider.notifier).switchChapter(chapter: state.nextChapter!);
                                  _interact();
                                },
                          onInteract: _interact,
                        )
                      : state.translationEnabled
                      ? const OnlineReaderFootBar()
                      : const ReaderFootBar(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stageArea(
    BuildContext context,
    OnlineReaderState state,
    ReaderPrefs prefs,
    AppPalette palette,
    AppLocalizations l10n,
  ) {
    final mobile = context.isMobile;
    final pagedReady =
        prefs.mode == ReaderMode.paged &&
        state.pageCount > 0 &&
        !state.loadingPages &&
        state.pagesError == null &&
        state.pageError == null &&
        !state.pageLoading;
    final sharedStage = mobile && pagedReady;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: onlineReaderStageColor())),
        Positioned.fill(
          child: sharedStage
              ? ReaderStage(
                  pageCount: state.pageCount,
                  index: state.page - 1,
                  showOriginal: state.showOriginal,
                  prefs: prefs,
                  onPage: (index) {
                    ref.read(onlineReaderProvider.notifier).goToPage(index + 1);
                    final current = ref.read(onlineReaderProvider);
                    if (current != null && current.controlsVisible) _interact();
                  },
                  onToggleBar: _toggleControls,
                  onBrightnessDelta: (delta) => ref.read(readerPrefsProvider.notifier).nudgeBrightness(delta),
                  onEndReached: () {
                    final current = ref.read(onlineReaderProvider);
                    final next = current?.nextChapter;
                    if (next != null) {
                      ref.read(onlineReaderProvider.notifier).switchChapter(chapter: next);
                      _interact();
                    }
                  },
                  showPageBadge: false,
                  pageBuilder: (context, seq, showOriginal) => _OnlinePageView(
                    page: seq,
                    config: seq <= state.pageConfigs.length ? state.pageConfigs[seq - 1] : null,
                    sourceId: state.sourceId,
                    allowedHosts: state.sourceHosts,
                    translated: state.showingTranslated && state.pageHasTranslation(seq),
                    scanning: state.translation.state == TranslationState.running && !state.pageHasTranslation(seq),
                  ),
                )
              : (!mobile && pagedReady)
              ? Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) _onScroll(event, state);
                  },
                  onPointerPanZoomStart: (_) => _panZoomScale = 1,
                  onPointerPanZoomUpdate: _onPanZoom,
                  child: PagedReaderStage(
                    controller: _pageController,
                    zoom: _zoom,
                    pageCount: state.pageCount,
                    index: state.page - 1,
                    onTap: _toggleControls,
                    onPageChanged: (index) {
                      ref.read(onlineReaderProvider.notifier).goToPage(index + 1);
                      _interact();
                    },
                    pageBuilder: (context, index) => _OnlinePageView(
                      page: index + 1,
                      config: index < state.pageConfigs.length ? state.pageConfigs[index] : null,
                      sourceId: state.sourceId,
                      allowedHosts: state.sourceHosts,
                      translated: state.showingTranslated && state.pageHasTranslation(index + 1),
                      scanning:
                          state.translation.state == TranslationState.running && !state.pageHasTranslation(index + 1),
                    ),
                  ),
                )
              : Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) _onScroll(event, state);
                  },
                  child: _stageBody(context, state, prefs),
                ),
        ),
        if (mobile)
          Positioned.fill(
            child: TapZoneHint(rtl: prefs.rtl, visible: _showTapHint && prefs.tapTurn, opacity: 1),
          ),
        if (state.osdVisible && !state.pageLoading && !state.loadingPages && state.pageError == null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(child: _Osd(state: state)),
            ),
          ),
        if (prefs.night != ReaderNight.off)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Color.lerp(palette.shadow, palette.blue, 0.2)!.withValues(alpha: 0.32)),
            ),
          ),
        if (prefs.brightness < 1)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: palette.shadow.withValues(alpha: (1 - prefs.brightness) * 0.75)),
            ),
          ),
        if (!mobile && prefs.mode == ReaderMode.paged) ...[
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
    );
  }

  Widget _stageBody(BuildContext context, OnlineReaderState state, ReaderPrefs prefs) {
    if (state.loadingPages) {
      return _OnlineLoadingStage(text: AppLocalizations.of(context).onlineReaderLoading);
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
    if (prefs.mode == ReaderMode.webtoon) {
      return ReaderWebtoonStage(
        pageCount: state.pageCount,
        onCenterTap: _toggleControls,
        pageBuilder: (context, seq) => _OnlineWebtoonPage(
          page: seq,
          config: seq <= state.pageConfigs.length ? state.pageConfigs[seq - 1] : null,
          sourceId: state.sourceId,
          allowedHosts: state.sourceHosts,
          translated: state.showingTranslated && state.pageHasTranslation(seq),
        ),
      );
    }
    if (state.pageLoading) {
      return _OnlineLoadingStage(text: AppLocalizations.of(context).onlineReaderLoading);
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

class _OnlineLoadingStage extends StatelessWidget {
  const _OnlineLoadingStage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: onlineReaderStageColor(),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OnlineReaderSpinner(),
            const SizedBox(height: 12),
            Text(
              text,
              style: TextStyle(fontSize: AppFont.px11_5, color: AppPalette.of(context).ink2),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlinePageView extends ConsumerStatefulWidget {
  const _OnlinePageView({
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
  ConsumerState<_OnlinePageView> createState() => _OnlinePageViewState();
}

class _OnlinePageViewState extends ConsumerState<_OnlinePageView> {
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
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const OnlineReaderSpinner(),
              const SizedBox(height: 10),
              Text(
                AppLocalizations.of(context).onlineReaderLoading,
                style: TextStyle(fontSize: AppFont.px11, color: AppPalette.of(context).ink2),
              ),
            ],
          ),
        ),
      );
    }
    return OnlinePageImage(page: widget.page, bytes: bytes, translated: widget.translated, scanning: widget.scanning);
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

class _OnlineWebtoonPage extends ConsumerStatefulWidget {
  const _OnlineWebtoonPage({
    required this.page,
    required this.config,
    required this.sourceId,
    required this.allowedHosts,
    required this.translated,
  });

  final int page;
  final ImageLoadingConfig? config;
  final String sourceId;
  final List<String> allowedHosts;
  final bool translated;

  @override
  ConsumerState<_OnlineWebtoonPage> createState() => _OnlineWebtoonPageState();
}

class _OnlineWebtoonPageState extends ConsumerState<_OnlineWebtoonPage> {
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
    final palette = AppPalette.of(context);
    if (_failed) {
      return Container(
        height: 120,
        color: onlineReaderStageColor(),
        alignment: Alignment.center,
        child: Icon(LucideIcons.imageOff, color: palette.ink2),
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return Container(
        height: 420,
        color: onlineReaderStageColor(),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OnlineReaderSpinner(),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context).onlineReaderLoading,
              style: TextStyle(fontSize: AppFont.px11, color: AppPalette.of(context).ink2),
            ),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Image.memory(bytes, fit: BoxFit.fitWidth, width: double.infinity),
        if (widget.translated)
          Positioned.fill(
            child: IgnorePointer(child: ColoredBox(color: palette.blue.withValues(alpha: 0.035))),
          ),
      ],
    );
  }
}
