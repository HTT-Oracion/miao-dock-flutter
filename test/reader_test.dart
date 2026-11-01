import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/reader_screen.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// 阅读器交互断言（D-092）。
void main() {
  Widget harness({required ReaderSession session, MangaSvcClient? client}) => ProviderScope(
    overrides: [if (client != null) mangaSvcClientProvider.overrideWithValue(client)],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer(
        builder: (context, ref, _) {
          // 会话由测试预置（等价于章节卡点击后的状态）。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ref.read(readerSessionProvider) == null) {
              ref.read(readerSessionProvider.notifier).open(session);
            }
          });
          return const Scaffold(body: ReaderScreen());
        },
      ),
    ),
  );

  testWidgets('无会话：给出空态与返回入口（不白屏）', (tester) async {
    await tester.pumpWidget(
      harness(
        session: const ReaderSession(key: 'x', pages: 0, translated: {}),
      ),
    );
    await tester.pumpAndSettle();
    // 破坏点：pages<=0 直接渲染 PageView → itemCount 0，用户看到纯黑屏。
    expect(find.text('关闭'), findsOneWidget);
  });

  testWidgets('顶栏显示页码 cur/total，且从第 1 页开始', (tester) async {
    await tester.pumpWidget(
      harness(
        session: const ReaderSession(key: '某书', chapterNo: 1, pages: 3, translated: {1}),
        client: _StubClient(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.textContaining('第 1 话'), findsOneWidget);
  });

  testWidgets('点右侧翻页区 → 页码前进', (tester) async {
    await tester.pumpWidget(
      harness(
        session: const ReaderSession(key: '某书', chapterNo: 1, pages: 3, translated: {}),
        client: _StubClient(),
      ),
    );
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(ReaderScreen));
    // 右侧 56px 是翻页热区。
    await tester.tapAt(Offset(size.width - 20, size.height / 2));
    await tester.pumpAndSettle();
    // 破坏点：热区失效 → 桌面端只能靠键盘，鼠标用户翻不了页。
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('小数话号在标题里显示为 1.5（不是 1.0）', (tester) async {
    await tester.pumpWidget(
      harness(
        session: const ReaderSession(key: '某书', chapterNo: 1.5, pages: 2, translated: {}),
        client: _StubClient(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1.5 话'), findsOneWidget);
  });
}

/// 取图恒失败 → 阅读器应显示占位而不是崩溃。
class _StubClient extends FakeMangaSvcClient {
  @override
  Future<List<int>> getChapterFile(String bookName, double chapterNo, int seq, {bool translated = false}) async =>
      Uint8List(0);

  @override
  Future<List<int>> getBookFile(String bookName, int seq, {bool translated = false}) async => Uint8List(0);
}
