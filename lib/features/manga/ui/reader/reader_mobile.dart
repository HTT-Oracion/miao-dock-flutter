import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/buttons.dart';
import 'reader_prefs.dart';
import 'reader_slider.dart';

/// 移动端阅读器专属部件（重设计稿 mobile.html）：
/// ReaderBottomBar（底栏）/ PageSlider（页码滑条）/ ReaderOsd（页码气泡）/
/// BrightOsd（亮度气泡）/ TapZoneHint（点按分区可视化）/ PageBadge（未翻译角标）/
/// ReaderClock（沉浸式自绘时钟）/ ReaderEndCard（章末衔接卡）。
///
/// 桌面端不引用本文件（`desgin/manga-viewer/desktop.html` 无底栏与 OSD）。

/// 舞台背景（页间留白）——设置抽屉四色。
Color readerStageColor(ReaderStageBg bg) => switch (bg) {
  ReaderStageBg.black => const Color(0xFF000000),
  ReaderStageBg.dark => const Color(0xFF1A1D21),
  ReaderStageBg.paper => const Color(0xFFEFECE4),
  ReaderStageBg.cream => const Color(0xFFF7EFDD),
};

/// 毛玻璃底（`.rbot` / `.rtop` 的 backdrop-filter 等价物）。
BoxDecoration glassDecoration(BuildContext context, {bool top = true}) {
  final palette = AppPalette.of(context);
  return BoxDecoration(
    color: palette.panel.withValues(alpha: 0.92),
    border: Border(
      top: top ? BorderSide(color: palette.line2.withValues(alpha: 0.7)) : BorderSide.none,
      bottom: top ? BorderSide.none : BorderSide(color: palette.line2.withValues(alpha: 0.7)),
    ),
  );
}

/// 移动端顶栏（设计稿 `.rtop`）：返回 + 标题/话名 + 原文⇄译文 chip。
///
/// 页码滑条与设置都挪到底栏 —— 顶栏在手机上只承载「我在看什么」。
class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.toggleLabel,
    this.onToggle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final String toggleLabel;
  final VoidCallback? onToggle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: glassDecoration(context, top: false),
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 10),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: SizedBox(width: 34, height: 34, child: Icon(LucideIcons.chevronLeft, size: 20, color: palette.ink)),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (onToggle != null)
            GestureDetector(
              onTap: onToggle!,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.accSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: palette.acc.withValues(alpha: 0.45)),
                ),
                child: Text(
                  toggleLabel,
                  style: TextStyle(fontSize: AppFont.px10_5, fontWeight: FontWeight.w600, color: palette.acc),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 设置抽屉里的一行：标题 + 副注 + 右侧控件（设计稿 `.setrow`）。
class ReaderSettingRow extends StatelessWidget {
  const ReaderSettingRow({super.key, required this.label, this.hint, required this.child});

  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: AppFont.px12, color: palette.ink),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: TextStyle(fontSize: AppFont.px9_5, height: 1.4, color: palette.mut),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          child,
        ],
      ),
    );
  }
}

/// 移动端底栏：`上一话 / 页码滑条 / 页码 / 下一话` + 动作行
/// `夜间 · 条漫 · 亮度 · 章节 · 设置`。上缘带 3s 自动隐藏进度线。
class ReaderBottomBar extends StatefulWidget {
  const ReaderBottomBar({
    super.key,
    required this.pageValue,
    required this.pageCount,
    required this.onPageChanged,
    required this.mode,
    required this.onToggleMode,
    required this.night,
    required this.onNight,
    required this.brightness,
    required this.onBrightness,
    required this.onChapters,
    this.onSettings,
    required this.hideProgress,
    this.onPrevChapter,
    this.onNextChapter,
    this.onInteract,
  });

  final int pageValue;
  final int pageCount;
  final ValueChanged<int> onPageChanged;
  final ReaderMode mode;
  final VoidCallback onToggleMode;
  final ReaderNight night;
  final ValueChanged<ReaderNight> onNight;
  final double brightness;
  final ValueChanged<double> onBrightness;

  /// 章节目录入口；null = 这本没有目录层级（未归并单话 / 书架未加载）→ 置灰。
  final VoidCallback? onChapters;
  final VoidCallback? onSettings;

  /// 0→1 的自动隐藏倒计时（设计稿 `.hidebar`）。
  final double hideProgress;

  /// 上一话 / 下一话；null = 没有（单话直读或已是首/末话）。
  final VoidCallback? onPrevChapter;
  final VoidCallback? onNextChapter;

  /// 任何交互都重置 3s 自动隐藏计时。
  final VoidCallback? onInteract;

  @override
  State<ReaderBottomBar> createState() => _ReaderBottomBarState();
}

class _ReaderBottomBarState extends State<ReaderBottomBar> {
  bool _brightOpen = false;
  bool _nightOpen = false;

  void _closePops() {
    if (!_brightOpen && !_nightOpen) return;
    setState(() {
      _brightOpen = false;
      _nightOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: glassDecoration(context),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // `.hidebar`：上缘 1.5px 自动隐藏进度线。
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: widget.hideProgress.clamp(0.0, 1.0),
                minHeight: 1.5,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(palette.acc.withValues(alpha: 0.6)),
              ),
            ),
          ),
          if (_brightOpen) ...[
            Row(
              children: [
                Icon(LucideIcons.sun, size: 14, color: palette.acc),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: palette.acc,
                      inactiveTrackColor: palette.progressTrack,
                      thumbColor: palette.acc,
                    ),
                    child: Slider(
                      value: widget.brightness,
                      min: 0.2,
                      max: 1,
                      onChanged: (v) {
                        widget.onInteract?.call();
                        widget.onBrightness(v);
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    l10n.readerPercent('${(widget.brightness * 100).round()}'),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: AppFont.px9_5,
                      color: palette.ink2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          if (_nightOpen) ...[
            Row(
              children: [
                for (final (mode, label) in [
                  (ReaderNight.off, l10n.readerNightOff),
                  (ReaderNight.warm, l10n.readerNightWarm),
                  (ReaderNight.black, l10n.readerNightBlack),
                  (ReaderNight.red, l10n.readerNightRed),
                ]) ...[
                  Expanded(
                    child: AppButton(
                      label: label,
                      onTap: () {
                        widget.onInteract?.call();
                        widget.onNight(mode);
                        setState(() => _nightOpen = false);
                      },
                      variant: widget.night == mode ? AppButtonVariant.primary : AppButtonVariant.secondary,
                      height: 28,
                      fontSize: AppFont.px10_5,
                    ),
                  ),
                  if (mode != ReaderNight.red) const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              _ChapterStep(icon: LucideIcons.chevronsLeft, label: l10n.readerPrevChapter, onTap: widget.onPrevChapter),
              const SizedBox(width: 4),
              Expanded(
                child: PageSlider(
                  value: widget.pageValue,
                  count: widget.pageCount,
                  onChanged: (p) {
                    widget.onInteract?.call();
                    widget.onPageChanged(p);
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                child: Text(
                  l10n.readerPage(widget.pageValue + 1, widget.pageCount),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppFont.px11,
                    color: palette.ink2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _ChapterStep(icon: LucideIcons.chevronsRight, label: l10n.readerNextChapter, onTap: widget.onNextChapter),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _BarAction(
                icon: LucideIcons.moon,
                label: l10n.readerActionNight,
                active: widget.night != ReaderNight.off || _nightOpen,
                onTap: () {
                  widget.onInteract?.call();
                  setState(() {
                    _nightOpen = !_nightOpen;
                    _brightOpen = false;
                  });
                },
              ),
              _BarAction(
                icon: LucideIcons.bookOpen,
                label: widget.mode == ReaderMode.webtoon ? l10n.readerActionPaged : l10n.readerActionMode,
                active: widget.mode == ReaderMode.webtoon,
                onTap: () {
                  widget.onInteract?.call();
                  _closePops();
                  widget.onToggleMode();
                },
              ),
              _BarAction(
                icon: LucideIcons.sun,
                label: l10n.readerActionBrightness,
                active: _brightOpen,
                onTap: () {
                  widget.onInteract?.call();
                  setState(() {
                    _brightOpen = !_brightOpen;
                    _nightOpen = false;
                  });
                },
              ),
              _BarAction(
                icon: LucideIcons.listOrdered,
                label: l10n.readerActionChapters,
                onTap: widget.onChapters == null
                    ? null
                    : () {
                        widget.onInteract?.call();
                        _closePops();
                        widget.onChapters!();
                      },
              ),
              if (widget.onSettings != null)
                _BarAction(
                  icon: LucideIcons.settings,
                  label: l10n.readerActionSettings,
                  onTap: () {
                    widget.onInteract?.call();
                    _closePops();
                    widget.onSettings!();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChapterStep extends StatelessWidget {
  const _ChapterStep({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: enabled ? palette.ink2 : palette.mut.withValues(alpha: 0.4)),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: AppFont.px9_5,
                color: enabled ? palette.ink2 : palette.mut.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // 置灰只在「确实没有这个能力」时用（例如单话没有目录）；
    // 有功能但点了没反应，比灰着更让人困惑。
    final enabled = onTap != null;
    final fg = !enabled ? palette.mut.withValues(alpha: 0.4) : (active ? palette.acc : palette.ink2);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: SizedBox(
        width: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: fg),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: AppFont.px9_5, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 跳页 / 换话的页码气泡（设计稿 `.osd`，900ms 自动消失）。
class ReaderOsd extends StatelessWidget {
  const ReaderOsd({super.key, required this.main, this.sub, required this.visible});

  final String main;
  final String? sub;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.fast,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: palette.panel.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.line2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                main,
                style: TextStyle(
                  fontSize: AppFont.px13,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (sub != null)
                Text(
                  sub!,
                  style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 亮度气泡（设计稿 `.osd.bright`：左缘居中，太阳 + 百分比 + 进度条）。
class BrightOsd extends StatelessWidget {
  const BrightOsd({super.key, required this.value, required this.visible});

  final double value;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.fast,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: palette.panel.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.line2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.sun, size: 12, color: palette.acc),
                  const SizedBox(width: 4),
                  Text(
                    l10n.readerPercent('${(value * 100).round()}'),
                    style: TextStyle(
                      fontSize: AppFont.px11,
                      color: palette.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: ((value - 0.2) / 0.8).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: palette.progressTrack,
                    valueColor: AlwaysStoppedAnimation(palette.acc),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 点按分区可视化（首次进入展示 2s）：左/中/右三段虚线框 + 竖排文案。
class TapZoneHint extends StatelessWidget {
  const TapZoneHint({super.key, required this.rtl, required this.visible, required this.opacity});

  final bool rtl;
  final bool visible;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!visible) return const SizedBox.shrink();
    final left = rtl ? l10n.readerTapHintNext : l10n.readerTapHintPrev;
    final right = rtl ? l10n.readerTapHintPrev : l10n.readerTapHintNext;
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Row(
          children: [
            _zone(context, left, vertical: true),
            _zone(context, l10n.readerTapHintCenter, vertical: false),
            _zone(context, right, vertical: true),
          ],
        ),
      ),
    );
  }

  Widget _zone(BuildContext context, String text, {required bool vertical}) {
    final palette = AppPalette.of(context);
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: palette.acc.withValues(alpha: 0.05),
          border: Border.all(color: palette.acc.withValues(alpha: 0.55)),
        ),
        alignment: Alignment.center,
        child: RotatedBox(
          quarterTurns: vertical ? 1 : 0,
          child: Text(
            text,
            style: TextStyle(fontSize: AppFont.px10_5, letterSpacing: 2, color: vertical ? palette.acc : palette.ink2),
          ),
        ),
      ),
    );
  }
}

/// 未翻译角标（设计稿 `.pbadge`：缺译文回退原图，不是错误态）。
class PageBadge extends StatelessWidget {
  const PageBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.warn.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: palette.warn, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            AppLocalizations.of(context).readerUntranslated,
            style: TextStyle(fontSize: AppFont.px10, color: palette.warn),
          ),
        ],
      ),
    );
  }
}

/// 沉浸式自绘时钟（系统状态栏被隐藏时由阅读器画）。
class ReaderClock extends StatelessWidget {
  const ReaderClock({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: AppFont.px11,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.85),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
