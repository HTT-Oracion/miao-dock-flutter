import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/process/service_controller.dart';
import 'package:miao_dock_flutter/core/process/service_launch.dart';
import 'package:miao_dock_flutter/core/process/service_supervisor.dart';
import 'package:miao_dock_flutter/features/settings/ui/settings_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 「服务与配对」配对令牌行：monospace 展示 + 一键复制。
void main() {
  const token = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

  Widget host({ServiceSupervisor? supervisor}) => ProviderScope(
    overrides: [if (supervisor != null) serviceSupervisorProvider.overrideWithValue(supervisor)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SettingsScreen()),
    ),
  );

  Future<void> openTranslateTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('翻译服务'));
    await tester.pumpAndSettle();
  }

  testWidgets('服务未由应用拉起（无 supervisor）→ 如实说明，无复制按钮', (tester) async {
    await tester.pumpWidget(host());
    await openTranslateTab(tester);

    expect(find.text('配对令牌'), findsOneWidget);
    expect(find.text('无法获取（服务未由应用启动）'), findsOneWidget);
    expect(find.text('复制'), findsNothing);
  });

  testWidgets('有 supervisor → monospace 显示令牌，点击复制进剪贴板并有吐司', (tester) async {
    final supervisor = ServiceSupervisor(
      plan: const ServiceLaunchPlan(executable: '/dev/null', args: [], workingDirectory: '/', origin: 'dev-source'),
    )..token = token;

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(host(supervisor: supervisor));
    await openTranslateTab(tester);

    // 令牌完整可见（monospace 行），且带复制按钮。
    expect(find.text(token), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);

    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    expect(copied, token);
    expect(find.text('令牌已复制到剪贴板'), findsOneWidget);

    // 吐司驻留 3200ms（D-070）；不推过这个时间，退出时会有挂起 Timer。
    await tester.pump(const Duration(milliseconds: 3300));
  });
}
