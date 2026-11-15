import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:miao_dock_flutter/features/music/ui/widgets/music_source_manager.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/state_box.dart';

/// 两个「数据源」页（漫画源 / 音乐源）在**都没导入源**时，空态必须一致。
///
/// 破坏点：音乐源用纯文本空态（旧实现）→ 切页时布局高度、图标、层级全变，
/// 用户观感是两张不同的页面；本测试锁定「同一组件 + 同结构」。
void main() {
  Widget host(Widget child) => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  testWidgets('音乐源无源：渲染与漫画源同款 OnlineStateBox（compact）', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const MusicSourcePanel()));
    await tester.pumpAndSettle();

    // 空态用共用组件，而不是自己拼的 Text。
    final box = tester.widget<OnlineStateBox>(find.byType(OnlineStateBox));
    expect(box.compact, isTrue);
    expect(box.icon, LucideIcons.inbox);
    // 破坏点：文案回退成旧的长句 → 与漫画源「还没有 X 源」标题形态不一致。
    expect(box.title, '还没有音乐源');
    expect(box.description, contains('导入源后即可'));
  });

  testWidgets('音乐源无源：不渲染「已导入的源」标题与计数', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const MusicSourcePanel()));
    await tester.pumpAndSettle();

    // 破坏点：无源时仍渲染标题 → 与漫画源（无源不渲染标题）不一致，
    // 且标题下面紧跟空态，视觉上多出一层级。
    expect(find.text('已导入的源'), findsNothing);
    expect(find.byType(OnlineTag), findsNothing);
  });

  testWidgets('音乐源无源：底部合规提示与漫画源同位同款', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const MusicSourcePanel()));
    await tester.pumpAndSettle();

    // 破坏点：漏掉合规提示 → 与漫画源页面底部结构不一致。
    expect(find.text('音乐源由第三方提供，内容与可用性由源作者负责。'), findsOneWidget);
  });
}
