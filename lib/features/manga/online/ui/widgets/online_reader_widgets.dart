import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/theme/tokens.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/widgets/buttons.dart';
import '../../domain/online_download.dart';
import '../../domain/online_models.dart';
import '../../controller/online_reader_controller.dart';
import 'online_common.dart';
import '../../../../../shared/responsive.dart';

const Color _stageBlack = Color(0xFF000000);

/// 阅读器顶栏（桌面 48 / 移动 52）。
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
      TranslationState.idle => [
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

/// 平移手势阈值辅助（移动端横滑翻页用）。
int pageFromSwipe({required double dx, required int page, required int pageCount, required double width}) {
  if (width <= 0) return page;
  final threshold = math.max(28.0, width * 0.08);
  if (dx.abs() < threshold) return page;
  final next = dx < 0 ? page + 1 : page - 1;
  return next.clamp(1, math.max(pageCount, 1));
}
