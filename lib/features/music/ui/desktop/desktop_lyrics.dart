import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../controller/music_player.dart';
import '../../controller/music_providers.dart';
import '../../controller/music_session.dart';

/// 桌面歌词偏好（N19）：字号 16–40（默认 24）/ 高亮色 / 未唱色 / 1–2 行。
///
/// 定义在本文件是因为 music_session.dart 不允许改动（任务约束）；
/// Color 属内容色板（演示色板常量），不是 UI 文案，允许进 provider 值对象。
@immutable
class DesktopLyricsPrefs {
  const DesktopLyricsPrefs({this.fontSize = 24, this.lines = 2, required this.highlight, required this.unsing});

  final double fontSize;
  final int lines;
  final Color highlight;
  final Color unsing;

  DesktopLyricsPrefs copyWith({double? fontSize, int? lines, Color? highlight, Color? unsing}) => DesktopLyricsPrefs(
    fontSize: fontSize ?? this.fontSize,
    lines: lines ?? this.lines,
    highlight: highlight ?? this.highlight,
    unsing: unsing ?? this.unsing,
  );
}

/// 演示色板（设计稿 dlset 弹层 swatches；内容色常量，不随主题）。
const List<Color> kDesktopLyricsSwatches = [
  Color(0xFFE8A44C),
  Color(0xFF7FB58A),
  Color(0xFF7BA7CE),
  Color(0xFFD98C84),
  Color(0xFFC9B5FF),
  Color(0xFFF5F2FF),
];

class _DesktopLyricsPrefsNotifier extends Notifier<DesktopLyricsPrefs> {
  @override
  DesktopLyricsPrefs build() => const DesktopLyricsPrefs(highlight: Color(0xFFE8A44C), unsing: Color(0xFFC9B5FF));

  void set(DesktopLyricsPrefs prefs) => state = prefs;
}

final desktopLyricsPrefsProvider = NotifierProvider<_DesktopLyricsPrefsNotifier, DesktopLyricsPrefs>(
  _DesktopLyricsPrefsNotifier.new,
);

/// 桌面歌词浮层（N19）：底部悬浮条（当前句 + 下一句），**整层 IgnorePointer**
/// （不挡桌面操作）；沉浸播放器打开时自动隐藏（避免两层歌词打架）。
class DesktopLyricsOverlay extends ConsumerWidget {
  const DesktopLyricsOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(musicUiProvider);
    // 沉浸播放器打开时自动隐藏（N19 边界）。
    if (!ui.desktopLyricsOn || ui.immersiveOpen) return const SizedBox.shrink();
    final player = ref.watch(playerProvider);
    final song = player.current;
    if (song == null) return const SizedBox.shrink();
    final prefs = ref.watch(desktopLyricsPrefsProvider);
    final palette = AppPalette.of(context);

    final lyrics = ref.watch(currentLyricsProvider);
    var idx = 0;
    for (final (k, line) in lyrics.lines.indexed) {
      if (player.positionMs >= line.t) idx = k;
    }
    final next = lyrics.lines[(idx + 1) % lyrics.lines.length];

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          // 悬浮在播放条上方（播放条 56 + 20 边距）。
          padding: const EdgeInsets.only(bottom: 76),
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: palette.bg.withValues(alpha: 0.86),
              border: Border.all(color: palette.line2),
              borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
              boxShadow: [
                BoxShadow(color: palette.shadow.withValues(alpha: 0.6), blurRadius: 28, offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lyrics.lines[idx].text,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: prefs.fontSize,
                    fontWeight: FontWeight.w700,
                    color: prefs.highlight,
                    height: 1.4,
                  ),
                ),
                if (prefs.lines > 1)
                  Text(
                    next.text,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: prefs.fontSize * 0.8,
                      color: prefs.unsing.withValues(alpha: 0.82),
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 桌面歌词设置弹窗（N19）：字号 / 高亮色 / 未唱色 / 行数；改动即时反映（所见即所得）。
class DesktopLyricsSettingsModal extends ConsumerWidget {
  const DesktopLyricsSettingsModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(desktopLyricsPrefsProvider);
    void set(DesktopLyricsPrefs p) => ref.read(desktopLyricsPrefsProvider.notifier).set(p);

    Widget swatches(Color current, ValueChanged<Color> onPick) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in kDesktopLyricsSwatches)
          GestureDetector(
            onTap: () => onPick(c),
            child: Container(
              width: 30,
              height: 22,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c == current ? palette.ink : Colors.transparent, width: 2),
              ),
            ),
          ),
      ],
    );

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: AppFont.px11_5, fontWeight: FontWeight.w600, color: palette.ink),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(musicUiProvider.notifier).setLyricsSettings(false),
      child: Center(
        child: GestureDetector(
          onTap: () {},
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 440,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: palette.panel,
                border: Border.all(color: palette.line2),
                borderRadius: BorderRadius.circular(AppMetrics.radiusModal),
                boxShadow: [
                  BoxShadow(color: palette.shadow.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 12)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.musicDlTitle,
                        style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w800, color: palette.ink),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => ref.read(musicUiProvider.notifier).setLyricsSettings(false),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: Icon(LucideIcons.x, size: 15, color: palette.ink2),
                        ),
                      ),
                    ],
                  ),
                  label(l10n.musicDlFontSize),
                  Row(
                    children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 4,
                            activeTrackColor: palette.acc,
                            inactiveTrackColor: palette.hi,
                            thumbColor: palette.acc,
                            overlayColor: palette.acc.withValues(alpha: 0.16),
                          ),
                          child: Slider(
                            value: prefs.fontSize,
                            min: 16,
                            max: 40,
                            divisions: 24,
                            onChanged: (v) => set(prefs.copyWith(fontSize: v)),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${prefs.fontSize.round()}px',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: AppFont.px11, color: palette.accInk, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  label(l10n.musicDlHighlight),
                  swatches(prefs.highlight, (c) => set(prefs.copyWith(highlight: c))),
                  label(l10n.musicDlUnsing),
                  swatches(prefs.unsing, (c) => set(prefs.copyWith(unsing: c))),
                  label(l10n.musicDlLines),
                  Row(
                    children: [
                      for (final (i, labelText) in [l10n.musicDlLine1, l10n.musicDlLine2].indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => set(prefs.copyWith(lines: i + 1)),
                          child: Container(
                            height: 28,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: prefs.lines == i + 1 ? palette.acc : palette.card,
                              borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              labelText,
                              style: TextStyle(
                                fontSize: AppFont.px11_5,
                                fontWeight: prefs.lines == i + 1 ? FontWeight.w600 : FontWeight.w400,
                                color: prefs.lines == i + 1 ? palette.onAcc : palette.ink2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
