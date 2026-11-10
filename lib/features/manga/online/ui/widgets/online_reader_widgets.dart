import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/theme/tokens.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/widgets/buttons.dart';
import '../../domain/online_download.dart';
import '../../domain/online_models.dart';
import '../../controller/online_reader_controller.dart';
import 'online_common.dart';
import '../../../../../shared/responsive.dart';

/// 漫画页画布色（内容，不是界面主题色）：纸面 / 墨线 / 气泡永远保持纸感，
/// 不随深浅主题变化。集中在这里，禁止在页面绘制处散写色值。
const Color _paper = Color(0xFFF5F2EA);
const Color _pageInk = Color(0xFF222222);
const Color _pageInkSoft = Color(0xFF555555);
const Color _pageInkMuted = Color(0xFF777777);
const Color _pageTranslatedInk = Color(0xFF3B4A55);
const Color _stageBlack = Color(0xFF000000);

/// 阅读器顶栏（桌面 48 / 移动 52）。
class OnlineReaderTopBar extends StatelessWidget {
  const OnlineReaderTopBar({
    super.key,
    required this.state,
    required this.mobile,
    required this.onBack,
    required this.onClose,
    required this.onPage,
    required this.onOriginal,
    required this.onTranslated,
    required this.onTranslate,
    required this.onCompare,
    required this.onGrid,
    required this.onChapters,
    required this.onHelp,
    required this.onFullscreen,
    required this.onSettings,
    required this.onZoom,
  });

  final OnlineReaderState state;
  final bool mobile;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final ValueChanged<int> onPage;
  final VoidCallback onOriginal;
  final VoidCallback onTranslated;
  final VoidCallback onTranslate;
  final VoidCallback onCompare;
  final VoidCallback onGrid;
  final VoidCallback onChapters;
  final VoidCallback onHelp;
  final VoidCallback onFullscreen;
  final VoidCallback onSettings;
  final VoidCallback onZoom;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final translating =
        state.translation.state == TranslationState.running ||
        state.translation.state == TranslationState.queued ||
        state.translation.state == TranslationState.unavailable;
    final title = _ReaderTitle(state: state, mobile: mobile);
    return Container(
      height: mobile ? 52 : 48,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 8 : 14),
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(bottom: BorderSide(color: palette.line2)),
      ),
      child: Row(
        children: [
          _TooltipIcon(
            tooltip: l10n.onlineReaderBack,
            icon: LucideIcons.arrowLeft,
            size: mobile ? 44 : 34,
            onTap: onBack,
          ),
          const SizedBox(width: 6),
          Expanded(child: title),
          if (!mobile) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 168,
              child: OnlinePageSlider(page: state.page, pageCount: state.pageCount, onPage: onPage),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 56,
              child: Text(
                l10n.onlineReaderPageOf(state.page, state.pageCount),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppFont.px11,
                  color: palette.ink2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _GroupSep(),
            AppButton(
              label: '${(state.zoom * 100).round()}%',
              onTap: onZoom,
              variant: AppButtonVariant.ghost,
              height: 26,
              horizontalPadding: 8,
              fontSize: AppFont.px10_5,
            ),
            const SizedBox(width: 10),
            _LanguageSeg(state: state, onOriginal: onOriginal, onTranslated: onTranslated, height: 26, minWidth: 44),
            const SizedBox(width: 10),
            AppButton(
              label: l10n.onlineReaderTranslationOfChapter,
              icon: LucideIcons.languages,
              onTap: translating ? null : onTranslate,
              variant: AppButtonVariant.primary,
              height: 26,
              horizontalPadding: 10,
              fontSize: AppFont.px10_5,
              fontWeight: FontWeight.w600,
            ),
            _GroupSep(),
            _TooltipIcon(tooltip: l10n.onlineReaderCompare, icon: LucideIcons.columns2, size: 34, onTap: onCompare),
            _TooltipIcon(tooltip: l10n.onlineReaderGrid, icon: LucideIcons.grid2x2, size: 34, onTap: onGrid),
            _TooltipIcon(tooltip: l10n.onlineReaderChapterDrawer, icon: LucideIcons.list, size: 34, onTap: onChapters),
            _TooltipIcon(tooltip: l10n.onlineReaderHelp, icon: LucideIcons.circleHelp, size: 34, onTap: onHelp),
            _TooltipIcon(
              tooltip: l10n.onlineReaderFullscreen,
              icon: LucideIcons.maximize,
              size: 34,
              onTap: onFullscreen,
            ),
            _TooltipIcon(tooltip: l10n.onlineReaderSettings, icon: LucideIcons.sliders, size: 34, onTap: onSettings),
            _GroupSep(),
            _TooltipIcon(tooltip: l10n.onlineReaderClose, icon: LucideIcons.x, size: 34, onTap: onClose),
          ] else ...[
            _LanguageSeg(state: state, onOriginal: onOriginal, onTranslated: onTranslated, height: 44, minWidth: 44),
          ],
        ],
      ),
    );
  }
}

class _ReaderTitle extends StatelessWidget {
  const _ReaderTitle({required this.state, required this.mobile});

  final OnlineReaderState state;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          state.comic.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w600, color: palette.ink),
        ),
        Text(
          l10n.onlineReaderCurrentInfo(state.chapter.title, state.sourceName, state.pageCount),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: mobile ? AppFont.px9_5 : AppFont.px10, color: palette.mut),
        ),
      ],
    );
  }
}

class _LanguageSeg extends StatelessWidget {
  const _LanguageSeg({
    required this.state,
    required this.onOriginal,
    required this.onTranslated,
    required this.height,
    required this.minWidth,
  });

  final OnlineReaderState state;
  final VoidCallback onOriginal;
  final VoidCallback onTranslated;
  final double height;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final enabled = state.canToggleTranslated;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SegButton(
            label: l10n.onlineReaderOriginal,
            active: state.showOriginal,
            onTap: onOriginal,
            height: height - 4,
            minWidth: minWidth,
          ),
          const SizedBox(width: 2),
          _SegButton(
            label: l10n.onlineReaderTranslated,
            active: !state.showOriginal,
            onTap: enabled ? onTranslated : null,
            height: height - 4,
            minWidth: minWidth,
          ),
        ],
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  const _SegButton({
    required this.label,
    required this.active,
    required this.onTap,
    required this.height,
    required this.minWidth,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;
  final double height;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: height,
        constraints: BoxConstraints(minWidth: minWidth),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? palette.acc : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppFont.px10_5,
            color: active ? palette.onBtn : (enabled ? palette.ink2 : palette.mut),
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _TooltipIcon extends StatelessWidget {
  const _TooltipIcon({required this.tooltip, required this.icon, required this.size, required this.onTap});

  final String tooltip;
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: AppButton(
        icon: icon,
        onTap: onTap,
        variant: AppButtonVariant.ghost,
        border: false,
        width: size,
        height: size,
        horizontalPadding: 0,
        fontSize: size >= 40 ? AppFont.px18 : AppFont.px15,
        color: palette.ink2,
      ),
    );
  }
}

class _GroupSep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(width: 1, height: 20, color: palette.line2, margin: const EdgeInsets.symmetric(horizontal: 2));
  }
}

/// 翻译状态条（7 态）。
class OnlineTranslationBar extends StatelessWidget {
  const OnlineTranslationBar({
    super.key,
    required this.state,
    required this.mobile,
    required this.onTranslate,
    required this.onRetry,
    required this.onOriginal,
    required this.onSettings,
  });

  final OnlineReaderState state;
  final bool mobile;
  final VoidCallback onTranslate;
  final VoidCallback onRetry;
  final VoidCallback onOriginal;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final status = state.translation;
    final (title, desc) = switch (status.state) {
      TranslationState.idle => (l10n.onlineTranslateIdle, l10n.onlineTranslateIdleDesc),
      TranslationState.queued => (l10n.onlineTranslateQueued, l10n.onlineTranslateQueuedDesc),
      TranslationState.running => (l10n.onlineTranslateRunning, l10n.onlineTranslateRunningDesc),
      TranslationState.done => (l10n.onlineTranslateDone, l10n.onlineTranslateDoneDesc(status.done, status.total)),
      TranslationState.partial => (
        l10n.onlineTranslatePartial,
        l10n.onlineTranslatePartialDesc(status.done, status.total, status.failed),
      ),
      TranslationState.failed => (l10n.onlineTranslateFailed, l10n.onlineTranslateFailedDesc),
      TranslationState.unavailable => (
        l10n.onlineTranslateUnavailable,
        mobile ? l10n.onlineTranslateUnavailableDescMobile : l10n.onlineTranslateUnavailableDesc,
      ),
    };
    final fg = switch (status.state) {
      TranslationState.running => palette.blue,
      TranslationState.done => palette.good,
      TranslationState.partial || TranslationState.unavailable => palette.warn,
      TranslationState.failed => palette.bad,
      _ => palette.ink2,
    };
    final bg = switch (status.state) {
      TranslationState.running => palette.blue.withValues(alpha: 0.09),
      TranslationState.done => palette.good.withValues(alpha: 0.09),
      TranslationState.partial || TranslationState.unavailable => palette.warn.withValues(alpha: 0.09),
      TranslationState.failed => palette.bad.withValues(alpha: 0.09),
      _ => Colors.transparent,
    };
    final actions = _actions(l10n);
    final progress = status.state == TranslationState.running
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MiniProgress(fraction: status.fraction, width: mobile ? 64 : 110),
              const SizedBox(width: 8),
              _CountText(text: l10n.onlineTranslateCount(status.done, status.total), color: palette.ink2),
            ],
          )
        : _CountText(text: l10n.onlineTranslateCount(status.done, status.total), color: palette.ink2);
    final titleText = Text(
      title,
      style: TextStyle(fontSize: AppFont.px11, height: 1.5, fontWeight: FontWeight.w600, color: fg),
    );
    final descText = Text(
      desc,
      maxLines: mobile ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: AppFont.px10_5, height: 1.5, color: palette.ink2),
    );
    final doneTag = status.state == TranslationState.done
        ? OnlineTag(l10n.onlineTranslateDoneShort, tone: OnlineTagTone.good)
        : null;

    final Widget content;
    if (mobile) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              titleText,
              const Spacer(),
              if (actions.isNotEmpty) Wrap(spacing: 8, children: actions),
            ],
          ),
          const SizedBox(height: 1),
          Row(
            children: [
              Expanded(child: descText),
              const SizedBox(width: 8),
              progress,
              if (doneTag != null) ...[const SizedBox(width: 8), doneTag],
            ],
          ),
        ],
      );
    } else {
      content = Row(
        children: [
          titleText,
          const SizedBox(width: 9),
          Flexible(child: descText),
          const Spacer(),
          progress,
          if (doneTag != null) ...[const SizedBox(width: 10), doneTag],
          if (actions.isNotEmpty) ...[const SizedBox(width: 10), Wrap(spacing: 10, children: actions)],
        ],
      );
    }
    return AnimatedContainer(
      duration: AppMotion.pageSwitch,
      curve: AppMotion.morphCurve,
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 10 : 16, vertical: mobile ? 6 : 7),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: palette.line2)),
      ),
      child: content,
    );
  }

  List<Widget> _actions(AppLocalizations l10n) {
    final state = this.state.translation.state;
    return switch (state) {
      TranslationState.idle when mobile => [
        AppButton(
          label: l10n.onlineReaderTranslationOfChapter,
          onTap: onTranslate,
          variant: AppButtonVariant.soft,
          height: 26,
          horizontalPadding: 10,
          fontSize: AppFont.px10_5,
          fontWeight: FontWeight.w600,
        ),
      ],
      TranslationState.running => [_BarTextAction(label: l10n.onlineTranslateOriginalOnly, onTap: onOriginal)],
      TranslationState.partial => [_BarButton(label: l10n.onlineTranslateRetryFailed, onTap: onRetry)],
      TranslationState.failed => [
        _BarButton(label: l10n.onlineTranslateRetry, onTap: onRetry),
        _BarTextAction(label: l10n.onlineTranslateOriginalOnly, onTap: onOriginal),
      ],
      TranslationState.unavailable => [
        _BarButton(label: l10n.onlineTranslateViewOriginal, onTap: onOriginal),
        _BarTextAction(label: l10n.onlineTranslateGoSettings, onTap: onSettings),
      ],
      _ => const [],
    };
  }
}

class _CountText extends StatelessWidget {
  const _CountText({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: AppFont.px10_5, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.fraction, required this.width});

  final double fraction;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: width,
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            Container(color: palette.hi),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0, 1),
              child: Container(color: palette.blue),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppButton(
    label: label,
    onTap: onTap,
    variant: AppButtonVariant.ghost,
    height: 26,
    horizontalPadding: 8,
    fontSize: AppFont.px10_5,
  );
}

class _BarTextAction extends StatelessWidget {
  const _BarTextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppButton(
    label: label,
    onTap: onTap,
    variant: AppButtonVariant.link,
    fontSize: AppFont.px10_5,
    horizontalPadding: 0,
  );
}

/// 自定义页码滑条（22px 拇指 / 6px 轨道）。
class OnlinePageSlider extends StatefulWidget {
  const OnlinePageSlider({super.key, required this.page, required this.pageCount, required this.onPage});

  final int page;
  final int pageCount;
  final ValueChanged<int> onPage;

  @override
  State<OnlinePageSlider> createState() => _OnlinePageSliderState();
}

class _OnlinePageSliderState extends State<OnlinePageSlider> {
  void _seek(double dx, double width) {
    if (widget.pageCount <= 1 || width <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    final page = (fraction * (widget.pageCount - 1)).round() + 1;
    if (page != widget.page) widget.onPage(page);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fraction = widget.pageCount <= 1 ? 0.0 : (widget.page - 1) / (widget.pageCount - 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _seek(details.localPosition.dx, width),
          onHorizontalDragStart: (details) => _seek(details.localPosition.dx, width),
          onHorizontalDragUpdate: (details) => _seek(details.localPosition.dx, width),
          child: SizedBox(
            height: 26,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(color: palette.hi, borderRadius: BorderRadius.circular(3)),
                ),
                FractionallySizedBox(
                  widthFactor: fraction.clamp(0, 1),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(color: palette.acc, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
                Positioned(
                  left: (width * fraction).clamp(0, width) - 11,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: palette.acc,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 桌面底栏：34px 提示条，不放任何按钮。
class OnlineReaderFootBar extends StatelessWidget {
  const OnlineReaderFootBar({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(top: BorderSide(color: palette.line2)),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Kbd('←'),
            const SizedBox(width: 10),
            _Kbd('→'),
            const SizedBox(width: 10),
            _FootText(l10n.onlineReaderFootPages),
            const SizedBox(width: 10),
            _Dot(),
            const SizedBox(width: 10),
            _FootText(l10n.onlineReaderFootEdge),
            const SizedBox(width: 10),
            _Dot(),
            const SizedBox(width: 10),
            _Kbd('T'),
            const SizedBox(width: 10),
            _FootText(l10n.onlineReaderFootLang),
            const SizedBox(width: 10),
            _Dot(),
            const SizedBox(width: 10),
            _FootText(l10n.onlineReaderFootCenter),
            const SizedBox(width: 10),
            _Dot(),
            const SizedBox(width: 10),
            _Kbd('Esc'),
            const SizedBox(width: 10),
            _FootText(l10n.onlineReaderFootExit),
          ],
        ),
      ),
    );
  }
}

class _Kbd extends StatelessWidget {
  const _Kbd(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 16,
      constraints: const BoxConstraints(minWidth: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(4),
        color: palette.card,
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: AppFont.px9, color: palette.ink2, fontFamily: 'monospace'),
      ),
    );
  }
}

class _FootText extends StatelessWidget {
  const _FootText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: AppFont.px10_5, color: AppPalette.of(context).ink2),
  );
}

class _Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 2,
    height: 2,
    decoration: BoxDecoration(color: AppPalette.of(context).line2, shape: BoxShape.circle),
  );
}

/// 移动端底栏两行：滑条行 + 动作行，带 1.5px 进度线与安全区。
class OnlineReaderMobileBottomBar extends StatelessWidget {
  const OnlineReaderMobileBottomBar({
    super.key,
    required this.state,
    required this.onPage,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onNight,
    required this.onWebtoon,
    required this.onBrightness,
    required this.onChapters,
    required this.onSettings,
  });

  final OnlineReaderState state;
  final ValueChanged<int> onPage;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final VoidCallback onNight;
  final VoidCallback onWebtoon;
  final VoidCallback onBrightness;
  final VoidCallback onChapters;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(top: BorderSide(color: palette.line2)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: state.progress.clamp(0, 1),
                child: Container(height: 1.5, color: palette.acc.withValues(alpha: 0.6)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        _ChapterArrow(
                          tooltip: l10n.onlineReaderPrevChapter,
                          icon: LucideIcons.chevronLeft,
                          enabled: state.prevChapter != null,
                          onTap: onPrevChapter,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OnlinePageSlider(page: state.page, pageCount: state.pageCount, onPage: onPage),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 56,
                          child: Text(
                            l10n.onlineReaderPageOf(state.page, state.pageCount),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: AppFont.px11,
                              color: palette.ink2,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _ChapterArrow(
                          tooltip: l10n.onlineReaderNextChapter,
                          icon: LucideIcons.chevronRight,
                          enabled: state.nextChapter != null,
                          onTap: onNextChapter,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ReaderAction(
                          icon: LucideIcons.moon,
                          label: l10n.onlineReaderNight,
                          active: state.night,
                          onTap: onNight,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ReaderAction(
                          icon: LucideIcons.rows,
                          label: l10n.onlineReaderWebtoon,
                          active: state.webtoon,
                          onTap: onWebtoon,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ReaderAction(
                          icon: LucideIcons.sun,
                          label: l10n.onlineReaderBrightness,
                          onTap: onBrightness,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ReaderAction(
                          icon: LucideIcons.list,
                          label: l10n.onlineReaderChapterShort,
                          onTap: onChapters,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ReaderAction(
                          icon: LucideIcons.sliders,
                          label: l10n.onlineReaderSettings,
                          onTap: onSettings,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterArrow extends StatelessWidget {
  const _ChapterArrow({required this.tooltip, required this.icon, required this.enabled, required this.onTap});

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: enabled ? palette.ink2 : palette.mut.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );
  }
}

class _ReaderAction extends StatelessWidget {
  const _ReaderAction({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: active ? palette.acc : palette.ink2),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: AppFont.px9_5,
                  color: active ? palette.accInk : palette.ink2,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 漫画页（合成页：四格 + 气泡 + 页码），译文中/译文后切换墨色与文案。
class OnlineMangaPage extends StatefulWidget {
  const OnlineMangaPage({
    super.key,
    required this.page,
    required this.translated,
    this.scanning = false,
    this.compact = false,
    this.showBadge = true,
    this.translating = false,
  });

  final int page;
  final bool translated;
  final bool scanning;
  final bool compact;
  final bool showBadge;
  final bool translating;

  @override
  State<OnlineMangaPage> createState() => _OnlineMangaPageState();
}

class _OnlineMangaPageState extends State<OnlineMangaPage> with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.scanning) _scan.repeat();
  }

  @override
  void didUpdateWidget(covariant OnlineMangaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scanning && !_scan.isAnimating) {
      _scan.repeat();
    } else if (!widget.scanning && _scan.isAnimating) {
      _scan.stop();
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final ink = widget.translated ? _pageTranslatedInk : _pageInk;
    final panelFill = widget.translated ? palette.blue.withValues(alpha: 0.04) : Colors.transparent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        color: _paper,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.all(widget.compact ? 18 : 26),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: ink, width: 2),
                        color: widget.translated ? palette.blue.withValues(alpha: 0.03) : null,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _Panel(
                                    index: 0,
                                    label: 'A',
                                    translated: widget.translated,
                                    ink: ink,
                                    fill: panelFill,
                                    l10n: l10n,
                                    compact: widget.compact,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _Panel(
                                    index: 1,
                                    label: 'B',
                                    translated: widget.translated,
                                    ink: ink,
                                    fill: panelFill,
                                    l10n: l10n,
                                    compact: widget.compact,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _Panel(
                                    index: 2,
                                    label: 'C',
                                    translated: widget.translated,
                                    ink: ink,
                                    fill: panelFill,
                                    l10n: l10n,
                                    compact: widget.compact,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _Panel(
                                    index: 3,
                                    label: 'D',
                                    translated: widget.translated,
                                    ink: ink,
                                    fill: panelFill,
                                    l10n: l10n,
                                    compact: widget.compact,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: widget.compact ? 26 : 34,
              left: widget.compact ? 30 : 44,
              child: _Bubble(text: widget.translated ? 'STOP!' : '"...!"', ink: ink, compact: widget.compact),
            ),
            Positioned(
              bottom: widget.compact ? 42 : 58,
              right: widget.compact ? 28 : 40,
              child: _Bubble(text: widget.translated ? 'GO!' : '"!?"', ink: ink, compact: widget.compact),
            ),
            if (widget.showBadge)
              Positioned(
                top: 8,
                left: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OnlineTag(
                      widget.translated ? l10n.onlineReaderTranslatedBadge : l10n.onlineReaderOriginalBadge,
                      tone: OnlineTagTone.acc,
                    ),
                    if (widget.translating) ...[
                      const SizedBox(width: 5),
                      OnlineTag(l10n.onlineReaderTranslatingPage, tone: OnlineTagTone.blue),
                    ],
                  ],
                ),
              ),
            Positioned(
              right: 12,
              bottom: 8,
              child: Text(
                'P ${widget.page}',
                style: TextStyle(fontSize: AppFont.px10, color: _pageInkMuted),
              ),
            ),
            if (widget.scanning)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _scan,
                    builder: (context, _) => Align(
                      alignment: Alignment(0, _scan.value * 2 - 1),
                      child: Container(
                        height: 90,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              palette.acc.withValues(alpha: 0),
                              palette.acc.withValues(alpha: 0.16),
                              palette.acc.withValues(alpha: 0.30),
                              palette.acc.withValues(alpha: 0.16),
                              palette.acc.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.index,
    required this.label,
    required this.translated,
    required this.ink,
    required this.fill,
    required this.l10n,
    required this.compact,
  });

  final int index;
  final String label;
  final bool translated;
  final Color ink;
  final Color fill;
  final AppLocalizations l10n;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: ink, width: 2),
        color: fill,
      ),
      child: Stack(
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: AppFont.px9, letterSpacing: 1, color: _pageInkMuted),
                ),
                const SizedBox(width: 5),
                Text(
                  translated ? l10n.onlineDemoTranslatedPanel('${index + 1}'.padLeft(2, '0')) : 'PANEL 0${index + 1}',
                  style: TextStyle(
                    fontSize: compact ? AppFont.px9 : AppFont.px13,
                    fontWeight: FontWeight.w600,
                    color: _pageInkSoft,
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _HatchPainter())),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.ink, required this.compact});

  final String text;
  final Color ink;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 5 : 6),
      decoration: BoxDecoration(
        color: _paper,
        border: Border.all(color: ink, width: 2),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: ink, offset: const Offset(1, 2), blurRadius: 0)],
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compact ? AppFont.px9 : AppFont.px11,
          fontWeight: FontWeight.w600,
          color: _pageInkSoft,
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _pageInk.withValues(alpha: 0.025)
      ..strokeWidth = 1;
    for (var offset = -size.height; offset < size.width; offset += 14) {
      canvas.drawLine(Offset(offset, 0), Offset(offset + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 网格总览内容。
class OnlineReaderGridContent extends StatelessWidget {
  const OnlineReaderGridContent({super.key, required this.state, required this.onPage});

  final OnlineReaderState state;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = context.isMobile ? (constraints.maxWidth - 24) / 3 : 76.0;
        return Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            for (var page = 1; page <= state.pageCount; page++)
              GestureDetector(
                onTap: () {
                  onPage(page);
                },
                child: Container(
                  width: width,
                  height: width * 4 / 3,
                  decoration: BoxDecoration(
                    color: palette.card,
                    border: Border.all(color: page == state.page ? palette.acc : palette.line2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$page',
                        style: TextStyle(
                          fontSize: AppFont.px13,
                          color: page == state.page ? palette.accInk : palette.ink2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.onlineReaderGridPage(page),
                        style: TextStyle(fontSize: AppFont.px8_5, color: palette.mut),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 章节抽屉内容。
class OnlineReaderChaptersContent extends StatelessWidget {
  const OnlineReaderChaptersContent({super.key, required this.state, required this.onChapter});

  final OnlineReaderState state;
  final ValueChanged<OnlineChapter> onChapter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    if (state.chapters.isEmpty) {
      return Text(
        l10n.onlineReaderChapterEmpty,
        style: TextStyle(fontSize: AppFont.px12, color: palette.mut),
      );
    }
    final groups = [
      (ChapterGroup.serial, l10n.onlineChapterGroupSerial),
      (ChapterGroup.extra, l10n.onlineChapterGroupExtra),
      (ChapterGroup.volume, l10n.onlineChapterGroupVolume),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (group, label) in groups)
          if (state.chapters.any((c) => c.group == group)) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4, top: 6),
              child: Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: AppFont.px11_5, fontWeight: FontWeight.w700, color: palette.ink),
                  ),
                  const SizedBox(width: 8),
                  OnlineTag('${state.chapters.where((c) => c.group == group).length}'),
                ],
              ),
            ),
            for (final chapter in state.chapters.where((c) => c.group == group))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: InkWell(
                  onTap: () => onChapter(chapter),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      color: chapter.id == state.chapter.id ? palette.accSoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFont.px11_5,
                        color: chapter.id == state.chapter.id ? palette.accInk : palette.ink2,
                        fontWeight: chapter.id == state.chapter.id ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
          ],
      ],
    );
  }
}

/// 翻译设置抽屉内容。
class OnlineReaderSettingsContent extends StatelessWidget {
  const OnlineReaderSettingsContent({
    super.key,
    required this.state,
    required this.sourceLang,
    required this.onRange,
    required this.onRetranslate,
    required this.onGoSettings,
  });

  final OnlineReaderState state;
  final String sourceLang;
  final ValueChanged<TranslationRange> onRange;
  final ValueChanged<bool> onRetranslate;
  final VoidCallback onGoSettings;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(l10n.onlineReaderLanguageSection),
        _SettingBlock(
          title: l10n.onlineReaderLanguage,
          desc: l10n.onlineReaderLanguageHint,
          control: AppButton(
            label: l10n.onlineReaderGoSettings,
            onTap: onGoSettings,
            variant: AppButtonVariant.ghost,
            height: 26,
            horizontalPadding: 10,
            fontSize: AppFont.px10_5,
          ),
        ),
        _SettingBlock(
          title: l10n.onlineReaderSourceLang,
          desc: l10n.onlineReaderSourceLangHint,
          control: OnlineTag(sourceLang),
        ),
        _SectionLabel(l10n.onlineReaderRangeSection),
        _SettingBlock(
          title: l10n.onlineReaderRange,
          desc: l10n.onlineReaderRangeHint,
          control: _RangeSeg(value: state.range, onChanged: onRange),
        ),
        _SettingBlock(
          title: l10n.onlineReaderRetranslate,
          desc: l10n.onlineReaderRetranslateHint,
          control: _ReaderSwitch(value: state.retranslate, onChanged: onRetranslate),
        ),
        _SectionLabel(l10n.onlineReaderTranslateServiceSection),
        _SettingBlock(
          title: l10n.onlineReaderServiceDesktop,
          desc: l10n.onlineReaderServiceHint,
          control: OnlineTag(l10n.onlineReaderServiceConnected, tone: OnlineTagTone.good),
        ),
        _SettingBlock(
          title: l10n.onlineReaderDegrade,
          desc: l10n.onlineReaderDegradeHint,
          control: _ReaderSwitch(value: true, onChanged: null),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: palette.acc.withValues(alpha: 0.08),
              border: Border.all(color: palette.acc.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              l10n.onlineReaderRealtimeNote,
              style: TextStyle(fontSize: AppFont.px10_5, height: 1.75, color: palette.ink2),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppFont.px10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: AppPalette.of(context).acc,
        ),
      ),
    );
  }
}

class _SettingBlock extends StatelessWidget {
  const _SettingBlock({required this.title, required this.desc, required this.control});

  final String title;
  final String desc;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w600, color: palette.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(fontSize: AppFont.px10_5, height: 1.5, color: palette.mut),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          control,
        ],
      ),
    );
  }
}

class _RangeSeg extends StatelessWidget {
  const _RangeSeg({required this.value, required this.onChanged});

  final TranslationRange value;
  final ValueChanged<TranslationRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (range, label) in [
            (TranslationRange.chapter, l10n.onlineReaderRangeChapter),
            (TranslationRange.fromCurrentPage, l10n.onlineReaderRangeCurrent),
          ])
            GestureDetector(
              onTap: () => onChanged(range),
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == range ? palette.acc : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(fontSize: AppFont.px11, color: value == range ? palette.onAcc : palette.ink2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReaderSwitch extends StatelessWidget {
  const _ReaderSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Container(
        width: 34,
        height: 18,
        decoration: BoxDecoration(color: value ? palette.acc : palette.line2, borderRadius: BorderRadius.circular(999)),
        child: AnimatedAlign(
          duration: AppMotion.pageSwitch,
          curve: AppMotion.morphCurve,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: value ? palette.onBtn : palette.ink2, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// 亮度面板内容。
class OnlineReaderBrightnessContent extends StatelessWidget {
  const OnlineReaderBrightnessContent({super.key, required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.onlineReaderBrightnessHint,
          style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(LucideIcons.sunDim, size: 16, color: palette.mut),
            Expanded(
              child: Slider(
                value: value,
                min: 0.25,
                max: 1,
                activeColor: palette.acc,
                inactiveColor: palette.hi,
                onChanged: onChanged,
              ),
            ),
            Icon(LucideIcons.sun, size: 16, color: palette.mut),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: Text(
                l10n.onlineReaderBrightnessValue((value * 100).round()),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: AppFont.px11, color: palette.ink2),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 快捷键帮助内容。
class OnlineReaderHelpContent extends StatelessWidget {
  const OnlineReaderHelpContent({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final rows = [
      ('← / →', l10n.onlineReaderHelpPages),
      ('T', l10n.onlineReaderHelpLang),
      (l10n.onlineReaderShortcutZoom, l10n.onlineReaderHelpZoom),
      ('G', l10n.onlineReaderHelpGrid),
      ('F', l10n.onlineReaderHelpFullscreen),
      ('?', l10n.onlineReaderHelpTap),
      ('Esc', l10n.onlineReaderHelpExit),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (key, label) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: palette.line2),
                    borderRadius: BorderRadius.circular(5),
                    color: palette.card,
                  ),
                  child: Text(
                    key,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: AppFont.px10, color: palette.ink2, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(fontSize: AppFont.px11_5, color: palette.ink2),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 阅读器舞台空白占位（加载 / 错误）。
class OnlineReaderStageStatus extends StatelessWidget {
  const OnlineReaderStageStatus({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.code,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String? hint;
  final String? code;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(
      color: _stageBlack,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: palette.ink2),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w600, color: palette.ink),
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
              ),
            ],
            if (code != null) ...[
              const SizedBox(height: 6),
              Text(
                code!,
                style: TextStyle(fontSize: AppFont.px10, color: palette.bad, fontFamily: 'monospace'),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// 扇形加载 spinner（1.6s 匀速）。
class OnlineReaderSpinner extends StatefulWidget {
  const OnlineReaderSpinner({super.key, this.size = 28});

  final double size;

  @override
  State<OnlineReaderSpinner> createState() => _OnlineReaderSpinnerState();
}

class _OnlineReaderSpinnerState extends State<OnlineReaderSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppMotion.spinner)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RotationTransition(
        turns: _controller,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(palette.acc),
          backgroundColor: palette.line2,
        ),
      ),
    );
  }
}

/// 舞台黑色（设计稿 `--stage-bg` 独立于主题）。
Color onlineReaderStageColor() => _stageBlack;

/// 页面纸张色（供外部尺寸占位使用）。
Color onlineReaderPaperColor() => _paper;

/// 平移手势阈值辅助（移动端横滑翻页用）。
int pageFromSwipe({required double dx, required int page, required int pageCount, required double width}) {
  if (width <= 0) return page;
  final threshold = math.max(28.0, width * 0.08);
  if (dx.abs() < threshold) return page;
  final next = dx < 0 ? page + 1 : page - 1;
  return next.clamp(1, math.max(pageCount, 1));
}
