import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:miao_dock_flutter/features/manga/ui/library_screen.dart';
import 'package:miao_dock_flutter/shared/widgets/buttons.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';
import 'package:protocol/protocol.dart';

/// 单话详情 Hero 动作（用户实测回归钉）：**桌面一行、归并在最后**。
void main() {
  final client = _SingleChapterClient();

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [mangaSvcClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
    // 桌面宽屏（isMobile 断点是 768 逻辑像素）。
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 选中单话 → 详情态。
    container.read(selectedBookProvider.notifier).select('单话甲');
    await tester.pumpAndSettle();
    return container;
  }

  Rect rectOf(WidgetTester tester, String label) {
    final btn = find.ancestor(of: find.text(label), matching: find.byType(AppButton));
    return tester.getRect(btn.first);
  }

  testWidgets('桌面单话详情：三个动作按钮同一行且归并在最后', (tester) async {
    await pump(tester);

    final view = rectOf(tester, '查看漫画');
    final dir = rectOf(tester, '打开目录');
    final merge = rectOf(tester, '归并');

    // 一行：三者同一 y。
    expect(view.top, dir.top);
    expect(view.top, merge.top);
    // 顺序：查看漫画 → 打开目录 → 归并（归并在最后）。
    expect(view.left, lessThan(dir.left));
    expect(dir.left, lessThan(merge.left));
    // 内容尺寸而非整行（用户实测整行 = 与代码不符的信号）。
    expect(view.width, lessThan(400), reason: '查看漫画按钮宽度 ${view.width}');
    expect(merge.width, lessThan(400), reason: '归并按钮宽度 ${merge.width}');
  });
}

class _SingleChapterClient extends FakeMangaSvcClient {
  @override
  Future<List<int>?> getBookCover(String bookName) async => null;

  @override
  // 合法的 1×1 PNG：非法字节会让图片解码抛异常干扰测试。
  Future<List<int>> getBookFile(String bookName, int seq, {bool translated = false}) async =>
      base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

  @override
  Future<LibraryResponse> listLibrary() async => LibraryResponse(
    root: '/tmp',
    count: 1,
    totalImages: 2,
    totalBytes: 80,
    comics: const [],
    books: const [],
    others: [
      const ChapterEntry(
        dirName: '单话甲',
        absDir: '/tmp/单话甲',
        imageCount: 2,
        translatedCount: 1,
        seqMax: 2,
        translatedSeqs: [1],
        missingSeqs: [2],
        merged: false,
      ),
    ],
    hidden: const [],
    hiddenCount: 0,
    updatedAt: DateTime(2026, 1, 1),
  );
}
