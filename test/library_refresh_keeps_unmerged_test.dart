import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/manga/controller/library_controller.dart';
import 'package:miao_dock_flutter/features/manga/controller/queue_controller.dart';
import 'package:protocol/protocol.dart';

/// D-096：**刷新后「未归并单话」不能消失**。
///
/// 背景：`refresh()` 算出了 all（books + others）却 `return books`，
/// 于是任务完成触发 refresh 后，刚翻完的漫画从书架蒸发 —— 用户看到「翻译完成但库里没有」。
void main() {
  test('refresh 返回 books + others', () async {
    final container = ProviderContainer(overrides: [mangaSvcClientProvider.overrideWithValue(_StubClient())]);
    addTearDown(container.dispose);

    // 先等 build 完成
    await container.read(libraryProvider.future);
    await container.read(libraryProvider.notifier).refresh();
    final list = container.read(libraryProvider).value ?? const <dynamic>[];

    // 破坏点：只返回 books → 只剩 1 条（书），单话丢失。
    expect(list.length, 2);
    expect(list.map((e) => e.name).toList(), containsAll(['某书', '某单话']));
  });
}

class _StubClient extends FakeMangaSvcClient {
  @override
  Future<LibraryResponse> listLibrary() async => LibraryResponse(
    root: '/tmp',
    count: 1,
    totalImages: 4,
    totalBytes: 100,
    comics: const [],
    books: [
      const BookEntry(
        bookName: '某书',
        dirName: '某书',
        outputDir: '/tmp/某书',
        title: '某书',
        author: '',
        chapterCount: 1,
        totalPages: 2,
        byteSize: 50,
        chapters: [],
      ),
    ],
    others: [
      const ChapterEntry(
        dirName: '某单话',
        absDir: '/tmp/某单话',
        imageCount: 2,
        translatedCount: 2,
        seqMax: 2,
        translatedSeqs: [1, 2],
        missingSeqs: [],
        merged: false,
      ),
    ],
    hidden: const [],
    hiddenCount: 0,
    updatedAt: DateTime(2026, 1, 1),
  );
}
