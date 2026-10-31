import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 国际化约束断言（D-006）。
///
/// 当前阶段只出中文、**不做语言切换**；这些断言锁住三件事：
///   1. supportedLocales 只有 zh —— 多一个就会让系统按其他语言渲染半成品界面；
///   2. 词条可正常解析（delegate 挂得上）；
///   3. 关键壳层词条非空。
void main() {
  testWidgets('supportedLocales 只有 zh（当前不做语言切换）', (tester) async {
    // 破坏点：给 supportedLocales 加 en 等语言，本条失败。
    expect(AppLocalizations.supportedLocales.length, 1);
    expect(AppLocalizations.supportedLocales.first.languageCode, 'zh');
  });

  testWidgets('delegate 可解析出中文词条', (tester) async {
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
    // 破坏点：ARB 词条被删或 key 改名，取值处会编译失败或命中空串。
    expect(l10n.appName, '喵坞 MiaoDock');
    expect(l10n.navManga, '漫画翻译');
    expect(l10n.navMusic, '音乐');
    expect(l10n.navAnime, '番剧');
    expect(l10n.navSettings, '设置');
    expect(l10n.brandTagline, isNotEmpty);
  });

  testWidgets('视图词条与侧栏一致（不得出现英文占位）', (tester) async {
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
    for (final s in [l10n.viewDrop, l10n.viewQueue, l10n.viewLibrary, l10n.viewDiscover, l10n.viewLocal]) {
      // 破坏点：把词条改成 "Drop" 之类英文占位，本条失败（设计稿 §08 文案纪律）。
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(s), isTrue, reason: '「$s」应为中文');
    }
  });
}
