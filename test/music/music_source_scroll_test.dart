import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';
import 'package:miao_dock_flutter/features/music/domain/js_music_source.dart';
import 'package:miao_dock_flutter/features/music/domain/music_source_manifest.dart';
import 'package:miao_dock_flutter/features/music/ui/widgets/music_source_manager.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/state_box.dart';

/// 固定内容的注册表替身：`build()` 直接返回注入的源列表。
class _FakeRegistry extends JsMusicSourceRegistry {
  _FakeRegistry(this._items);

  final List<JsMusicSource> _items;

  @override
  List<JsMusicSource> build() => _items;
}

/// 数据源弹窗「已导入的源」滚动行为。
///
/// 规则：桌面弹窗里超过 [kSourceListMaxVisible] 条 → 列表区自身滚动；
/// 不足/等于 → 直铺不撑高。移动端不做内层滚动（抽屉已有整页滚动）。
///
/// 破坏点：把限高去掉 → 弹窗随源数量无限变长，撑出屏幕无法操作；
/// 或移动端也套内层滚动 → 抽屉里出现双滚动、手势打架。
void main() {
  Widget host(Widget child, {Size size = const Size(1280, 900)}) => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );

  group('桌面弹窗列表限高', () {
    /// 造 n 个已装源（同构最小清单，只为填满列表）。
    List<JsMusicSource> makeSources(int n) => [
      for (var i = 0; i < n; i++)
        JsMusicSource(
          manifest: MusicSourceManifest(
            specVersion: 1,
            id: 'src$i',
            platform: 'netease',
            name: '源 $i',
            version: '1.0.0',
            baseUrl: 'https://music.163.com',
            entryClass: 'SrcSource$i',
            sourceFile: 'src$i.js',
            hosts: const ['music.163.com'],
          ),
          capabilities: const {'searchSongs'},
        ),
    ];

    Widget hostWith(int count, {int? limit}) => ProviderScope(
      overrides: [
        // 覆盖注册表 provider，直接注入已装源列表。
        jsMusicSourceRegistryProvider.overrideWith(() => _FakeRegistry(makeSources(count))),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 1280,
            height: 1200,
            child: SingleChildScrollView(child: MusicSourcePanel(maxVisibleSources: limit)),
          ),
        ),
      ),
    );

    testWidgets('已装源 5 条 > 4：列表区出现内层滚动', (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(hostWith(5, limit: kSourceListMaxVisible));
      await tester.pumpAndSettle();

      // host 外层 1 个 + 列表内层 1 个。
      // 破坏点：去掉 ConstrainedBox 限高 → 内层滚动消失，弹窗被撑长。
      expect(find.byType(SingleChildScrollView), findsNWidgets(2));
      expect(find.text('已导入的源'), findsOneWidget);
    });

    testWidgets('已装源 4 条 = 4：不出现内层滚动（不撑高）', (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(hostWith(4, limit: kSourceListMaxVisible));
      await tester.pumpAndSettle();

      // 破坏点：判据写成 >= → 恰好 4 条时也白套一层滚动。
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('已装源 ≤ 4 条：列表不出现内层滚动', (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(const MusicSourcePanel(maxVisibleSources: kSourceListMaxVisible)));
      await tester.pumpAndSettle();

      // 无源时空态占位，同样不该有内层滚动。
      expect(find.byType(SingleChildScrollView), findsOneWidget); // 仅 host 外层
    });

    testWidgets('limited 参数为 null（设置页）：永不加内层滚动', (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(const MusicSourcePanel()));
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
