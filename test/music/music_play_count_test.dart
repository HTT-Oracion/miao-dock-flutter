import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';
import 'package:miao_dock_flutter/features/music/ui/views/discover_view.dart';
import 'package:miao_dock_flutter/features/music/ui/widgets/music_shared.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

void main() {
  testWidgets('中文播放次数按原数值、万、亿三档格式化', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(formatMusicPlayCount(l10n, 9999), '9,999');
    expect(formatMusicPlayCount(l10n, 8520), '8,520');
    expect(formatMusicPlayCount(l10n, 12000), '1.2万');
    expect(formatMusicPlayCount(l10n, 100000), '10万');
    expect(formatMusicPlayCount(l10n, 99999000), '9999.9万');
    expect(formatMusicPlayCount(l10n, 100000000), '1亿');
    expect(formatMusicPlayCount(l10n, 120000000), '1.2亿');
    expect(formatMusicPlayCount(l10n, 1050000000), '10.5亿');
  });

  testWidgets('歌单瓦片：有数值才显示角标，并按万/亿格式化（不出现原始长数字）', (tester) async {
    Future<void> pump(MusicPlaylist p) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(width: 200, child: MusicPlaylistTile(playlist: p)),
          ),
        ),
      );
      await tester.pump();
    }

    // 破坏点：直接显示接口原始数值（1234567）而不是 123.5万 → 断言失败。
    await pump(const MusicPlaylist(id: 'a', name: 'A', trackCount: 1, seed: 'a', playCountValue: 1234567));
    expect(find.text('123.5万'), findsOneWidget);
    expect(find.text('1234567'), findsNothing);

    await pump(const MusicPlaylist(id: 'b', name: 'B', trackCount: 1, seed: 'b', playCountValue: 9800));
    expect(find.text('9,800'), findsOneWidget);

    // 接口没给数值 → 不画角标（不是画 0，也不是画曲目数）。
    await pump(const MusicPlaylist(id: 'c', name: 'C', trackCount: 42, seed: 'c'));
    expect(find.text('42'), findsNothing);
    expect(find.byIcon(LucideIcons.headphones), findsNothing);
  });
}
