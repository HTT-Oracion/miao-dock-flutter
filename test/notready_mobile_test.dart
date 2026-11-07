import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/domain/not_ready_state.dart';
import 'package:miao_dock_flutter/features/manga/ui/notready/not_ready_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/spinning_icon.dart';

/// D-138：窄屏引导页只留「结论 + 一个按钮」。
///
/// 桌面端保持原状（分层状态 / 三步教程都在），移动端必须消失 ——
/// 否则手机上是一屏排查信息，用户不知道点哪。
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  NotReadyScreen screen({String? probeDetail, VoidCallback? onVerify, VoidCallback? onSettings}) => NotReadyScreen(
    view: NotReadyView(
      state: NotReadyState.installed,
      engine: EngineRuntimeState.off,
      source: TranslateSource.remote,
      remoteVerification: RemoteVerificationState.failed,
      remoteFailure: (kind: RemoteVerifyIssue.probeFailed, detail: probeDetail),
    ),
    onPrimary: () {},
    onSecondary: () {},
    onRetryService: () {},
    onTogglePause: () {},
    paused: false,
    downloadEntries: const [],
    onExportLogs: null,
    onImportLocal: null,
    onBrowseLibrary: () {},
    onVerifyRemote: onVerify,
    onOpenRemoteSettings: onSettings,
  );

  testWidgets('窄屏：不显示三步教程与分层状态，主按钮占满整行', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(screen(probeDetail: '令牌无效')));
    await tester.pumpAndSettle();

    // 破坏点：窄屏仍渲染三步流程 → 一屏全是排查信息。
    expect(find.text('填写远程地址与访问令牌'), findsNothing);
    expect(find.text('校验连接与对面引擎'), findsNothing);
    // 两个按钮各司其职（D-139：原来合成一个，点了既不校验也不跳转）。
    expect(find.text('校验远程配置'), findsOneWidget);
    expect(find.text('去设置远程配置'), findsOneWidget);
    // 校验失败原因必须显示（用户要知道错在哪）。
    expect(find.textContaining('令牌无效'), findsOneWidget);
  });

  testWidgets('宽屏：保留三步教程（桌面端保持原状）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(screen()));
    await tester.pumpAndSettle();

    // 破坏点：删过头把桌面端的三步也去掉了。
    // 远程来源下三步文案是 `remoteGateStep*`，不是 `nrStep*`。
    expect(find.text('填写远程地址与访问令牌'), findsOneWidget);
    expect(find.text('校验连接与对面引擎'), findsOneWidget);
  });

  /// 校验中的 loader 必须转：静止的 `loader` 字形看起来就是「卡住了」。
  ///
  /// 破坏点：`SpinningIcon` 不 repeat（或头部退回裸 `Icon`）→ 两轮角度读数相同，
  /// 第一条用例失败。
  group('校验中图标旋转', () {
    NotReadyScreen checking() => NotReadyScreen(
      view: const NotReadyView(
        state: NotReadyState.installed,
        engine: EngineRuntimeState.off,
        source: TranslateSource.remote,
        remoteVerification: RemoteVerificationState.checking,
      ),
      onPrimary: () {},
      onSecondary: () {},
      onRetryService: () {},
      onVerifyRemote: () {},
      onOpenRemoteSettings: () {},
      onBrowseLibrary: () {},
    );

    /// 只能定点 pump：校验中同时有脉冲点与旋转两个无限动画，`pumpAndSettle` 不收敛。
    Future<double> turnAfterPump(WidgetTester tester, {required bool wide}) async {
      tester.view.physicalSize = wide ? const Size(1440, 900) : const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(checking()));
      await tester.pump();
      expect(find.text('正在校验远程配置'), findsOneWidget);
      final turns = tester
          .widget<RotationTransition>(
            find.descendant(of: find.byType(SpinningIcon), matching: find.byType(RotationTransition)),
          )
          .turns;
      final before = turns.value;
      await tester.pump(const Duration(milliseconds: 300));
      expect(turns.value, isNot(before));
      return turns.value;
    }

    testWidgets('窄屏：标题左侧 loader 持续旋转', (tester) async {
      expect(await turnAfterPump(tester, wide: false), greaterThan(0));
    });

    testWidgets('桌面：头部 loader 持续旋转', (tester) async {
      expect(await turnAfterPump(tester, wide: true), greaterThan(0));
    });

    testWidgets('失败态：图标停转（不空转）', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(screen()));
      await tester.pump();

      final turns = tester
          .widget<RotationTransition>(
            find.descendant(of: find.byType(SpinningIcon), matching: find.byType(RotationTransition)),
          )
          .turns;
      await tester.pump(const Duration(milliseconds: 300));
      expect(turns.value, 0);
    });
  });
}
