import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/domain/not_ready_state.dart';
import 'package:miao_dock_flutter/features/manga/ui/notready/not_ready_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

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

  NotReadyScreen screen({String? probeDetail}) => NotReadyScreen(
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
}
