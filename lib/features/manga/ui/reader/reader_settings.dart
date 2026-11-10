import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../shared/responsive.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/app_switch.dart';
import 'reader_mobile.dart';
import 'reader_prefs.dart';

/// 漫画库与在线阅读器共用的阅读设置抽屉。
///
/// 在线阅读器把「翻译设置」作为 [extra] 追加在同一个抽屉里；阅读设置本身
/// 只有这一份实现，避免后续新增阅读项时漏改在线侧。
class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({super.key, this.extra});

  /// 数据侧扩展（在线阅读器传翻译设置）；null = 纯阅读设置。
  final Widget? extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(readerPrefsProvider);
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final notifier = ref.read(readerPrefsProvider.notifier);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: palette.acc,
        inactiveTrackColor: palette.progressTrack,
        thumbColor: palette.acc,
      ),
      child: AppSheet(
        title: l10n.readerSettingsTitle,
        onClose: () => Navigator.of(context).pop(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReaderSettingRow(
              label: l10n.readerModeTitle,
              child: ReaderSeg<ReaderMode>(
                value: p.mode,
                options: [(ReaderMode.paged, l10n.readerModePaged), (ReaderMode.webtoon, l10n.readerModeWebtoon)],
                onChanged: notifier.setMode,
              ),
            ),
            ReaderSettingRow(
              label: l10n.readerRtl,
              child: ReaderSeg<bool>(
                value: p.rtl,
                options: const [(false, 'LTR'), (true, 'RTL')],
                onChanged: (_) => notifier.toggleRtl(),
              ),
            ),
            ReaderSettingRow(
              label: l10n.readerTurnAnimTitle,
              child: ReaderSeg<ReaderTurnAnim>(
                value: p.turnAnim,
                options: [
                  (ReaderTurnAnim.push, l10n.readerTurnAnimPush),
                  (ReaderTurnAnim.fade, l10n.readerTurnAnimFade),
                  (ReaderTurnAnim.none, l10n.readerTurnAnimNone),
                ],
                onChanged: notifier.setTurnAnim,
              ),
            ),
            ReaderSettingRow(
              label: l10n.readerTapTurn,
              hint: l10n.readerTapTurnHint,
              child: AppSwitch(value: p.tapTurn, onChanged: (_) => notifier.toggleTapTurn()),
            ),
            ReaderSettingRow(
              label: l10n.readerNightTitle,
              child: ReaderSeg<ReaderNight>(
                value: p.night,
                options: [
                  (ReaderNight.off, l10n.readerNightOff),
                  (ReaderNight.warm, l10n.readerNightWarm),
                  (ReaderNight.black, l10n.readerNightBlack),
                  (ReaderNight.red, l10n.readerNightRed),
                ],
                onChanged: notifier.setNight,
              ),
            ),
            ReaderSettingRow(
              label: l10n.readerNightIntensity,
              hint: l10n.readerPercent('${(p.nightIntensity * 100).round()}'),
              child: SizedBox(
                width: 132,
                child: Slider(value: p.nightIntensity, min: 0.2, max: 1, onChanged: notifier.setNightIntensity),
              ),
            ),
            ReaderSettingRow(
              label: l10n.readerStageBg,
              hint: l10n.readerStageBgHint,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final bg in ReaderStageBg.values) ...[
                    GestureDetector(
                      onTap: () => notifier.setStageBg(bg),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: readerStageColor(bg),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: p.stageBg == bg ? palette.acc : palette.line2,
                            width: p.stageBg == bg ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                    if (bg != ReaderStageBg.values.last) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            ReaderSettingRow(
              label: l10n.readerPageNum,
              hint: l10n.readerPageNumHint,
              child: AppSwitch(value: p.pageNum, onChanged: (_) => notifier.togglePageNum()),
            ),
            if (context.isMobile)
              ReaderSettingRow(
                label: l10n.readerImmersive,
                hint: l10n.readerImmersiveHint,
                child: AppSwitch(value: p.immersive, onChanged: (_) => notifier.toggleImmersive()),
              ),
            ReaderSettingRow(
              label: l10n.readerPreload,
              hint: l10n.readerPreloadUnit(p.preload),
              child: SizedBox(
                width: 132,
                child: Slider(
                  value: p.preload.toDouble(),
                  min: 1,
                  max: 6,
                  divisions: 5,
                  onChanged: (v) => notifier.setPreload(v.round()),
                ),
              ),
            ),
            if (defaultTargetPlatform == TargetPlatform.android)
              ReaderSettingRow(
                label: l10n.readerVolumeKeys,
                hint: l10n.readerVolumeKeysHint,
                child: AppSwitch(value: p.volumeKeys, onChanged: (_) => notifier.toggleVolumeKeys()),
              ),
            if (p.mode == ReaderMode.webtoon)
              ReaderSettingRow(
                label: l10n.readerAutoScroll,
                hint: l10n.readerAutoScrollHint,
                child: AppSwitch(value: p.autoScroll, onChanged: (_) => notifier.toggleAutoScroll()),
              ),
            if (context.isMobile)
              ReaderSettingRow(
                label: l10n.readerAwake,
                hint: l10n.readerAwakeHint,
                child: AppSwitch(value: p.awake, onChanged: (_) => notifier.toggleAwake()),
              ),
            if (extra != null) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: palette.line2),
              const SizedBox(height: 8),
              extra!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 设置抽屉里的分段控件；与漫画库旧实现同构，抽到共享层。
class ReaderSeg<T> extends StatelessWidget {
  const ReaderSeg({super.key, required this.value, required this.options, required this.onChanged});

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.line2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in options) ...[
            GestureDetector(
              onTap: () => onChanged(v),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: v == value ? palette.acc : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: AppFont.px10_5,
                    fontWeight: v == value ? FontWeight.w700 : FontWeight.w500,
                    color: v == value ? palette.onAcc : palette.ink2,
                  ),
                ),
              ),
            ),
            if (v != options.last.$1) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}
