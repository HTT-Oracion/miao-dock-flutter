import 'dart:math';

import 'dto/lib_book.dart';
import 'dto/manga_task.dart';
import 'mangasvc_client.dart';

/// A 级替身（third-party-packages / AGENTS §2）：内存假队列，
/// UI 日常开发与热重载用，不需要任何服务进程。
class FakeMangasvcClient implements MangasvcClient {
  FakeMangasvcClient() {
    _seed();
  }

  final List<MangaTask> _tasks = [];
  int _seq = 0;

  void _seed() {
    const names = [
      ('未来回归', '已翻译 12 话 · 288 页'),
      ('星海航路', '已翻译 8 话 · 196 页'),
      ('深夜食堂 · 外传', '已翻译 5 话 · 120 页'),
      ('雾都侦探', '已翻译 3 话 · 74 页'),
      ('南国之夏', '已翻译 9 话 · 214 页'),
      ('机械之心', '已翻译 2 话 · 48 页'),
      ('古书店的谜题', '已翻译 6 话 · 150 页'),
      ('北境之歌', '已翻译 4 话 · 96 页'),
      ('城市猎人 2025', '已翻译 7 话 · 168 页'),
      ('银翼快枪', '已翻译 1 话 · 22 页'),
      ('时间旅行者的妻子', '已翻译 10 话 · 240 页'),
      ('红发安妮 · 续', '已翻译 3 话 · 66 页'),
      ('深海列车', '已翻译 5 话 · 118 页'),
      ('纸飞机与晚风', '已翻译 2 话 · 44 页'),
      ('季风花园', '已翻译 8 话 · 190 页'),
      (' Lost · 拾遗', '已翻译 6 话 · 132 页'),
    ];
    final statuses = [
      MangaTaskStatus.translating,
      MangaTaskStatus.queued,
      MangaTaskStatus.done,
      MangaTaskStatus.done,
      MangaTaskStatus.done,
      MangaTaskStatus.partialFailed,
      MangaTaskStatus.done,
      MangaTaskStatus.failed,
      MangaTaskStatus.done,
      MangaTaskStatus.cancelled,
      MangaTaskStatus.done,
      MangaTaskStatus.done,
      MangaTaskStatus.done,
      MangaTaskStatus.done,
      MangaTaskStatus.done,
      MangaTaskStatus.done,
    ];
    final now = DateTime.now();
    for (final (i, name) in names.indexed) {
      final status = statuses[i];
      final pages = 16 + Random(i).nextInt(32);
      _tasks.add(
        MangaTask(
          id: 't-${++_seq}',
          name: name.$1,
          subtitle: name.$2,
          source: i % 3 == 0 ? '本机投放' : '喵译插件',
          status: status,
          pageCount: pages,
          donePages: switch (status) {
            MangaTaskStatus.done => pages,
            MangaTaskStatus.partialFailed => pages - 3,
            MangaTaskStatus.translating => pages ~/ 3,
            MangaTaskStatus.queued => 0,
            _ => pages,
          },
          batchNo: i % 4 + 1,
          createdAt: now.subtract(Duration(hours: 16 - i)),
          completedAt: switch (status) {
            MangaTaskStatus.done ||
            MangaTaskStatus.partialFailed ||
            MangaTaskStatus.failed ||
            MangaTaskStatus.cancelled => now.subtract(Duration(hours: 16 - i - 1)),
            _ => null,
          },
        ),
      );
    }
  }

  @override
  Future<List<MangaTask>> listTasks() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return List.of(_tasks);
  }

  @override
  Future<List<LibBook>> listLibrary() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final books = <LibBook>[];
    final rand = Random(7);
    for (final t in _tasks.where((t) => t.status == MangaTaskStatus.done)) {
      final chapters = <LibChapter>[];
      final count = 2 + rand.nextInt(4);
      for (var c = 1; c <= count; c++) {
        final pages = 12 + rand.nextInt(24);
        chapters.add(LibChapter(no: c, pageCount: pages, donePages: rand.nextBool() ? pages : pages - rand.nextInt(6)));
      }
      books.add(
        LibBook(
          key: t.id,
          name: t.name,
          author: '佚名',
          chapters: chapters,
          totalBytes: chapters.fold(0, (s, c) => s + c.pageCount) * 1024 * 380,
        ),
      );
    }
    return books;
  }

  @override
  Future<SubmitResult> submit({required String comicName, required List<String> imagePaths}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final position = _tasks.where((t) => !t.deletable).length + 1;
    _tasks.insert(
      0,
      MangaTask(
        id: 't-${++_seq}',
        name: comicName,
        subtitle: '第 1 话 · ${imagePaths.length} 页',
        source: '本机投放',
        status: MangaTaskStatus.queued,
        pageCount: imagePaths.length,
        donePages: 0,
        batchNo: (imagePaths.length / 20).ceil(),
        createdAt: DateTime.now(),
      ),
    );
    return SubmitResult(submitted: imagePaths.length, position: position);
  }

  @override
  Future<void> deleteTasks(Set<String>? taskIds) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _tasks.removeWhere((t) => t.deletable && (taskIds == null || taskIds.contains(t.id)));
  }

  @override
  Future<void> cancelTask(String taskId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i >= 0) {
      _tasks[i] = _tasks[i].copyWith(status: MangaTaskStatus.cancelled);
    }
  }
}
