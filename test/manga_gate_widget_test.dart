import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/engine_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/engine_ready_controller.dart';
import 'package:miao_dock_flutter/features/manga/domain/not_ready_state.dart';
import 'package:miao_dock_flutter/features/manga/ui/manga_gate.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

class _LocalSource extends TranslateSourceNotifier {
  @override
  TranslateSource build() => TranslateSource.local;
}

class _RemoteSource extends TranslateSourceNotifier {
  @override
  TranslateSource build() => TranslateSource.remote;
}

void main() {
  Widget host(MangaGateState state, {String path = '/manga/drop', bool remote = false}) => ProviderScope(
    overrides: [
      mangaGateProvider.overrideWithValue(state),
      translateSourceProvider.overrideWith(remote ? _RemoteSource.new : _LocalSource.new),
    ],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MangaGate(
        enabled: true,
        path: path,
        child: const Text('目标页面', textDirection: TextDirection.ltr),
      ),
    ),
  );

  testWidgets('投放/队列未就绪时显示 NotReadyScreen，不渲染目标页', (tester) async {
    await tester.pumpWidget(host(MangaGateState.installed));
    await tester.pumpAndSettle();

    // 破坏点：门禁只算状态却仍返回 child → 用户能继续投放和操作队列。
    expect(find.text('引擎已就绪，尚未启动'), findsOneWidget);
    expect(find.text('目标页面'), findsNothing);
  });

  testWidgets('引擎与 LLM 就绪时渲染目标页', (tester) async {
    await tester.pumpWidget(host(MangaGateState.ready, path: '/manga/queue'));
    await tester.pumpAndSettle();

    expect(find.text('目标页面'), findsOneWidget);
  });

  testWidgets('漫画库绕过门禁，仍可阅读已落盘作品', (tester) async {
    await tester.pumpWidget(host(MangaGateState.installed, path: '/manga/library'));
    await tester.pumpAndSettle();

    expect(find.text('目标页面'), findsOneWidget);
  });

  testWidgets('远程未校验时显示远程门禁，不渲染投放页', (tester) async {
    await tester.pumpWidget(host(MangaGateState.remoteBlocked, remote: true));
    await tester.pumpAndSettle();

    expect(find.text('请先校验远程配置'), findsOneWidget);
    expect(find.text('校验远程配置'), findsOneWidget);
    expect(find.text('目标页面'), findsNothing);
  });
}
