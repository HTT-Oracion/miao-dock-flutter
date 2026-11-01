import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:miao_dock_flutter/core/storage/shell_prefs.dart';
import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// D-122：阅读器「显示原图 / 显示翻译」切换。
///
/// - 进阅读器**默认看译文**（按钮文案是「显示原图」）；
/// - 点一次 → 切到原图，按钮变「显示翻译」，且**状态持久化**。
void main() {
  testWidgets('默认显示译文，点击后切原图并持久化', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    // 持久化落的是真实文件，先把状态重置为默认（译文），避免被其他用例/本机历史影响。
    persistReaderShowOriginal(false);
    final client = _C();
    final container = ProviderContainer(overrides: [mangaSvcClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
    container.read(readerSessionProvider.notifier).open(const ReaderSession(key: '单话A', pages: 2, translated: {1}));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            initialLocation: '/r',
            routes: [
              GoRoute(
                path: '/r',
                builder: (_, _) => const Scaffold(body: ReaderScreen()),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 默认看译文 → 按钮应写着「显示原图」。
    expect(find.text('显示原图'), findsOneWidget);
    // 默认取译文：首次取图请求里 translated 必须为 true。
    expect(
      client.translatedFlags.where((f) => f).isNotEmpty,
      isTrue,
      reason: '默认应请求译文，实际请求记录=${client.translatedFlags}',
    );

    await tester.tap(find.text('显示原图'));
    await tester.pumpAndSettle();

    expect(find.text('显示翻译'), findsOneWidget);
    // 破坏点：切换后不重新取图 → 画面仍是译文。
    expect(client.translatedFlags.last, isFalse);
    // 破坏点：不落盘 → 下次进阅读器又回译文。
    expect(readReaderShowOriginal(), isTrue);
  });
}

class _C extends FakeMangaSvcClient {
  final translatedFlags = <bool>[];

  @override
  Future<List<int>> getBookFile(String bookName, int seq, {bool translated = false}) async {
    translatedFlags.add(translated);
    return const [];
  }
}
