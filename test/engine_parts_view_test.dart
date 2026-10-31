import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import 'package:miao_dock_flutter/core/storage/engine_inspect.dart';
import 'package:miao_dock_flutter/features/settings/controller/engine_dir_controller.dart';
import 'package:miao_dock_flutter/features/settings/ui/engine_parts_view.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:miao_dock_flutter/shared/widgets/log_box.dart';

/// D-027 部件表断言。
class FakeInspection extends EngineInspectionNotifier {
  FakeInspection(this._value);

  final EngineInspection? _value;

  @override
  Future<EngineInspection?> build() async => _value;
}

void main() {
  EngineInspection inspectionWith({required List<PartCheck> checks}) =>
      EngineInspection(engineDir: '/tmp/engine', checks: checks, manifestMissing: true);

  Widget host(Widget child, {EngineInspection? inspection}) => ProviderScope(
    overrides: [if (inspection != null) engineInspectionProvider.overrideWith(() => FakeInspection(inspection))],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  testWidgets('未校验时必须显示「尚未校验」，不能画成通过', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const EnginePartsSection()));
    await tester.pumpAndSettle();

    // 破坏点：把「没检查过」渲染成通过 → 用户以为没问题，本条失败。
    expect(find.text('尚未校验'), findsOneWidget);
    expect(find.text('校验通过'), findsNothing);
  });

  testWidgets('校验失败 → 显示部件、日志块与重新下载按钮', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final r = inspectionWith(
      checks: const [
        PartCheck(part: EnginePart.python, ok: true, detail: 'Python 3.11.10'),
        PartCheck(part: EnginePart.source, ok: true),
        PartCheck(part: EnginePart.deps, ok: true),
        PartCheck(part: EnginePart.llama, ok: true),
        PartCheck(part: EnginePart.modelsVisual, ok: true),
        PartCheck(part: EnginePart.llm, ok: false, logs: ['  没有找到 .gguf 权重：/tmp/engine/llm']),
        PartCheck(part: EnginePart.modelsNllb, ok: false, detail: '未安装（按需）'),
      ],
    );

    await tester.pumpWidget(host(const EnginePartsSection(), inspection: r));
    await tester.pumpAndSettle();

    // 破坏点：失败时把失败项藏起来 → 用户不知道该补什么，本条失败。
    expect(find.textContaining('校验失败'), findsOneWidget);
    // 日志只在失败时出现（D-013 复用）
    expect(find.byType(LogBox), findsOneWidget);
    expect(find.textContaining('重新下载缺失部件'), findsOneWidget);
  });

  testWidgets('校验通过 → 不出日志块（避免刷屏）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final r = inspectionWith(
      checks: const [
        PartCheck(part: EnginePart.python, ok: true),
        PartCheck(part: EnginePart.source, ok: true),
        PartCheck(part: EnginePart.deps, ok: true),
        PartCheck(part: EnginePart.llama, ok: true),
        PartCheck(part: EnginePart.modelsVisual, ok: true),
        PartCheck(part: EnginePart.llm, ok: true),
        PartCheck(part: EnginePart.modelsNllb, ok: false),
      ],
    );

    await tester.pumpWidget(host(const EnginePartsSection(), inspection: r));
    await tester.pumpAndSettle();

    // 破坏点：成功也展开日志 → 面板被技术输出淹掉，本条失败。
    expect(find.text('校验通过'), findsOneWidget);
    expect(find.byType(LogBox), findsNothing);
  });
}
