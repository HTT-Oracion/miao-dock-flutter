import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/widgets/toast.dart';
import '../controller/online_browse_controller.dart';
import '../controller/online_detail_controller.dart';
import '../controller/online_download_controller.dart';
import '../controller/online_sources_controller.dart';
import '../domain/online_download.dart';
import '../domain/online_models.dart';
import '../domain/online_source.dart';
import 'widgets/online_browse_views.dart';
import 'widgets/online_chrome.dart';
import 'widgets/online_common.dart';
import 'widgets/online_detail_view.dart';
import 'widgets/online_shelf.dart';
import 'widgets/online_source_panel.dart';

/// 在线漫画（漫画翻译模块第 4 视图，`/manga/online`）。
///
/// 桌面：左栏 246 + 主区；移动：平台 chips + 搜索 + 分段 + 网格，详情从右滑入。
/// 源管理归设置；移动端「导入源」用底部 sheet 复刻设置里的同一分区。
class OnlineScreen extends ConsumerStatefulWidget {
  const OnlineScreen({super.key});

  @override
  ConsumerState<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends ConsumerState<OnlineScreen> {
  String? _detailKey;
  String? _detailSourceId;
  bool _disclaimerScheduled = false;
  bool _sourceSheetOpen = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final mobile = context.isMobile;
    final uri = GoRouterState.of(context).uri;
    final segments = uri.pathSegments;
    final detailMode = segments.length >= 5 && segments[2] == 'detail';
    final detailSourceId = detailMode ? segments[3] : null;
    final detailComicId = detailMode ? segments[4] : null;

    _maybeOpenDetail(detailMode, detailSourceId, detailComicId);
    _maybeShowDisclaimer();

    ref.listen<DownloadNotice?>(onlineDownloadNoticeProvider, (previous, next) {
      if (next == null || previous?.revision == next.revision) return;
      final l10n = AppLocalizations.of(context);
      final cache = next.task.target == DownloadTarget.cache;
      final message = switch (next.kind) {
        DownloadNoticeKind.started =>
          cache
              ? l10n.onlineCacheStartedToast(next.task.chapterTitle)
              : l10n.onlineDownloadStartedToast(next.task.chapterTitle),
        DownloadNoticeKind.completed =>
          cache
              ? l10n.onlineCacheDoneToast(next.task.chapterTitle, next.task.total)
              : l10n.onlineDownloadDoneToast(next.task.chapterTitle, next.task.total),
      };
      showAppToast(context, message, tone: next.kind == DownloadNoticeKind.completed ? ToastTone.good : ToastTone.info);
    });

    if (kIsWeb) {
      return ColoredBox(
        color: palette.bg,
        child: Center(
          child: OnlineStateBox(
            icon: LucideIcons.wifiOff,
            title: l10n.onlineWebUnsupportedShort,
            description: l10n.onlineWebUnsupported,
          ),
        ),
      );
    }

    final nav = ref.watch(onlineNavProvider);
    final source = ref.watch(activeOnlineSourceProvider);
    final abnormalBanner = source?.isAbnormal == true
        ? Padding(
            padding: EdgeInsets.fromLTRB(mobile ? 14 : 22, mobile ? 8 : 12, mobile ? 14 : 22, 0),
            child: OnlineBanner(
              text: l10n.onlineSourceAbnormalBanner(source!.consecutiveFailures),
              tone: OnlineBannerTone.warn,
              icon: LucideIcons.alertTriangle,
            ),
          )
        : null;
    final body = _buildBody(context, ref, nav, detailMode, mobile);
    if (!mobile) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OnlineShelf(onManageSources: _goSettingsSources, onOpenComic: _openComic, onContinue: _continueProgress),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OnlineTopBar(
                  title: _titleOf(l10n, detailMode, nav),
                  onManageSources: _goSettingsSources,
                  onSearchSubmitted: (_) {
                    if (detailMode) context.go('/manga/online');
                  },
                ),
                ?abnormalBanner,
                Expanded(child: body),
              ],
            ),
          ),
        ],
      );
    }

    final base = Column(
      children: [
        OnlineMobilePlatformBar(onImportSource: _openSourceSheet),
        OnlineMobileSearchBar(
          onSubmitted: (_) {
            if (detailMode) context.go('/manga/online');
          },
        ),
        OnlineMobileSubTabs(),
        ?abnormalBanner,
        Expanded(child: body),
      ],
    );
    return Stack(
      children: [
        Positioned.fill(child: base),
        if (detailMode)
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: 0),
              duration: AppMotion.drawer,
              curve: AppMotion.morphCurve,
              builder: (context, value, child) => FractionalTranslation(translation: Offset(value, 0), child: child),
              child: OnlineMobileDetailSlide(
                onBack: _closeDetail,
                onRead: _openReader,
                onDownload: (detail, chapter, translate) => _download(detail, chapter, translate: translate),
                onCache: (detail, chapter, translate) => _cache(detail, chapter, translate: translate),
                onManageSources: _openSourceSheet,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, OnlineNavState nav, bool detailMode, bool mobile) {
    if (detailMode && !mobile) {
      return OnlineDesktopDetailView(
        onBack: _closeDetail,
        onRead: _openReader,
        onDownload: (value, chapter, translate) => _download(value, chapter, translate: translate),
        onManageSources: _goSettingsSources,
      );
    }
    if (nav.query.isNotEmpty) {
      return OnlineSearchView(onOpenComic: _openComicForNav);
    }
    return switch (nav.view) {
      OnlineView.discover => OnlineDiscoverView(onOpenComic: _openComicForNav, onManageSources: _goSettingsSources),
      OnlineView.categories => OnlineCategoryView(onOpenComic: _openComicForNav),
      OnlineView.recent => OnlineRecentView(onOpenComic: _openComic, onContinue: _continueProgress),
      OnlineView.downloads => const OnlineDownloadsView(),
    };
  }

  String _titleOf(AppLocalizations l10n, bool detailMode, OnlineNavState nav) {
    if (detailMode) return l10n.onlineDetailTitle;
    if (nav.query.isNotEmpty) return l10n.onlineSearchAction;
    return switch (nav.view) {
      OnlineView.discover => l10n.onlineDiscover,
      OnlineView.categories => l10n.onlineCategories,
      OnlineView.recent => l10n.onlineRecent,
      OnlineView.downloads => l10n.onlineDownloads,
    };
  }

  void _maybeOpenDetail(bool detailMode, String? sourceId, String? comicId) {
    if (!detailMode || sourceId == null || comicId == null) {
      _detailKey = null;
      return;
    }
    final key = '$sourceId/$comicId';
    if (key == _detailKey) return;
    _detailKey = key;
    _detailSourceId = sourceId;
    Future.microtask(() async {
      if (!mounted) return;
      try {
        await ref.read(onlineSourcesProvider.future);
      } catch (_) {
        // 源清单失败时仍让详情 provider 给出错误态。
      }
      if (!mounted) return;
      ref.read(onlineSourceSelectionProvider.notifier).select(sourceId);
      await ref.read(onlineDetailProvider.notifier).open(sourceId, comicId);
    });
  }

  void _maybeShowDisclaimer() {
    if (_disclaimerScheduled || !ref.read(onlineDisclaimerProvider)) return;
    _disclaimerScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !ref.read(onlineDisclaimerProvider)) return;
      final l10n = AppLocalizations.of(context);
      void acceptSheet(BuildContext sheetContext) {
        ref.read(onlineDisclaimerProvider.notifier).accept();
        Navigator.of(sheetContext).pop();
      }

      if (context.isMobile) {
        // 设计稿 m-disclaimer：移动端是底部 sheet，主按钮通栏 44 高。
        await showAppSheet<void>(
          context: context,
          builder: (sheetContext) => AppSheet(
            title: l10n.onlineDisclaimerTitle,
            icon: LucideIcons.shield,
            onClose: () => Navigator.of(sheetContext).pop(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.onlineDisclaimerBody,
                  style: TextStyle(fontSize: AppFont.px12, height: 1.9, color: AppPalette.of(sheetContext).ink2),
                ),
                const SizedBox(height: 14),
                AppButton(
                  label: l10n.onlineDisclaimerOk,
                  onTap: () => acceptSheet(sheetContext),
                  variant: AppButtonVariant.primary,
                  width: double.infinity,
                  height: 44,
                  horizontalPadding: 13,
                  fontSize: AppFont.px12,
                  fontWeight: FontWeight.w600,
                ),
              ],
            ),
          ),
        );
        return;
      }
      await showAppDialog<void>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: l10n.onlineDisclaimerTitle,
          icon: LucideIcons.shield,
          width: 440,
          actions: [
            AppButton(
              label: l10n.onlineDisclaimerOk,
              onTap: () => acceptSheet(dialogContext),
              variant: AppButtonVariant.primary,
              height: 32,
              horizontalPadding: 13,
              fontSize: AppFont.px12,
              fontWeight: FontWeight.w600,
            ),
          ],
          child: Text(
            l10n.onlineDisclaimerBody,
            style: TextStyle(fontSize: AppFont.px12, height: 1.9, color: AppPalette.of(dialogContext).ink2),
          ),
        ),
      );
    });
  }

  void _openComic(String sourceId, String comicId) {
    context.go('/manga/online/detail/$sourceId/$comicId');
  }

  void _openComicForNav(OnlineComic comic) {
    final sourceId = ref.read(activeOnlineSourceIdProvider);
    if (sourceId == null) return;
    _openComic(sourceId, comic.id);
  }

  void _closeDetail() => context.go('/manga/online');

  void _goSettingsSources() {
    context.go('/settings?section=online');
  }

  void _openSourceSheet() {
    if (_sourceSheetOpen) return;
    _sourceSheetOpen = true;
    final l10n = AppLocalizations.of(context);
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => AppSheet(
        title: l10n.onlineSourceManageSheet,
        icon: LucideIcons.plug,
        onClose: () => Navigator.of(sheetContext).pop(),
        child: const OnlineSourcePanel(sheetMode: true),
      ),
    ).whenComplete(() => _sourceSheetOpen = false);
  }

  OnlineSource? _sourceById(String? id) {
    final sources = ref.read(onlineSourcesProvider).value;
    if (sources == null) return null;
    if (id != null) {
      for (final source in sources) {
        if (source.id == id) return source;
      }
    }
    return ref.read(activeOnlineSourceProvider);
  }

  Future<void> _openReader(
    OnlineComicDetail detail,
    OnlineChapter chapter, {
    int? page,
    bool autoTranslate = false,
  }) async {
    var source = _sourceById(_detailSourceId);
    if (source == null) {
      try {
        await ref.read(onlineSourcesProvider.future);
      } catch (_) {
        // 源列表失败时下面统一提示。
      }
      if (!mounted) return;
      source = _sourceById(_detailSourceId);
    }
    if (source == null) {
      if (mounted) showAppToast(context, AppLocalizations.of(context).onlineSourceNotReady, tone: ToastTone.warn);
      return;
    }
    final location = _detailSourceId == null ? '/manga/online' : '/manga/online/detail/${source.id}/${detail.comic.id}';
    ref
        .read(onlineReaderLaunchProvider.notifier)
        .set(
          OnlineReaderLaunch(
            source: source,
            comic: detail.comic,
            chapter: chapter,
            chapters: detail.chapters,
            page: page,
            autoTranslate: autoTranslate,
            returnLocation: location,
          ),
        );
    context.go('/manga/online/reader');
  }

  Future<void> _download(OnlineComicDetail detail, OnlineChapter chapter, {required bool translate}) async {
    final source = _sourceById(_detailSourceId);
    if (source == null) return;
    final target = context.isMobile ? DownloadTarget.cache : DownloadTarget.library;
    await ref
        .read(onlineDownloadsProvider.notifier)
        .begin(source: source, comic: detail.comic, chapter: chapter, target: target, translate: translate);
    if (!mounted) return;
    if (translate) {
      await _openReader(detail, chapter, autoTranslate: true);
    }
  }

  Future<void> _cache(OnlineComicDetail detail, OnlineChapter chapter, {required bool translate}) async {
    final source = _sourceById(_detailSourceId);
    if (source == null) return;
    await ref
        .read(onlineDownloadsProvider.notifier)
        .begin(
          source: source,
          comic: detail.comic,
          chapter: chapter,
          target: DownloadTarget.cache,
          translate: translate,
        );
    if (!mounted) return;
    _showCacheSheet();
  }

  void _showCacheSheet() {
    final l10n = AppLocalizations.of(context);
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => AppSheet(
        title: l10n.onlineCacheSheet,
        icon: LucideIcons.download,
        onClose: () => Navigator.of(sheetContext).pop(),
        child: const _MobileCacheBody(),
      ),
    );
  }

  Future<void> _continueProgress(ReadingProgress progress) async {
    final source = _sourceById(progress.sourceId);
    if (source == null) return;
    final comic = OnlineComic(id: progress.comicId, title: progress.comicTitle, coverTone: progress.coverTone);
    final chapter = OnlineChapter(id: progress.chapterId, title: progress.chapterTitle, group: ChapterGroup.serial);
    ref
        .read(onlineReaderLaunchProvider.notifier)
        .set(
          OnlineReaderLaunch(
            source: source,
            comic: comic,
            chapter: chapter,
            chapters: [chapter],
            page: progress.page,
            returnLocation: '/manga/online',
          ),
        );
    context.go('/manga/online/reader');
  }
}

class _MobileCacheBody extends ConsumerWidget {
  const _MobileCacheBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.watch(onlineDownloadsProvider);
    return tasks.when(
      skipLoadingOnRefresh: true,
      loading: () => const SkeletonBox(height: 90, radius: 10),
      error: (error, _) => OnlineErrorBox(
        error: error,
        title: l10n.onlineCacheError,
        description: l10n.onlineCacheErrorHint,
        onRetry: () => ref.read(onlineDownloadsProvider.notifier).refresh(),
      ),
      data: (items) {
        if (items.isEmpty) {
          return OnlineStateBox(
            icon: LucideIcons.download,
            title: l10n.onlineCacheEmpty,
            description: l10n.onlineCacheEmptyHint,
            compact: true,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OnlineBanner(text: l10n.onlineDownloadNoticeMobile, icon: LucideIcons.info),
            OnlineDownloadPanel(tasks: items),
          ],
        );
      },
    );
  }
}
