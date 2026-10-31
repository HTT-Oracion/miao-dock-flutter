library;

import 'package:protocol/protocol.dart';

import '../domain/lib_book.dart';
import '../domain/manga_task.dart';

/// 契约 DTO → domain 模型（AGENTS §3：DTO 不直接上 UI）。
///
/// 转换集中在这一处：契约字段变动时只改这里，业务屏不受影响。
/// `TaskRow` → [MangaTask]。
///
/// 只做**结构转换**，不拼任何展示文案：文案属 UI 层，经 ARB 取
/// （[MangaTaskSource] / [MangaTaskStatus] 都是语义枚举）。
MangaTask toMangaTask(TaskRow row) => MangaTask(
  id: row.taskId,
  name: row.comicName,
  source: _sourceOf(row.source),
  status: _statusOf(row.status),
  pageCount: row.progress.total,
  donePages: row.progress.done,
  batchNo: batchOf(row.progress.total),
  createdAt: row.createdAt,
  completedAt: row.finishedAt,
  failedReason: row.failedItems.isEmpty ? null : row.failedItems.first.reason,
);

/// `BookEntry` → [LibBook]。
LibBook toLibBook(BookEntry book) => LibBook(
  key: book.dirName,
  name: book.title.isEmpty ? book.bookName : book.title,
  author: book.author,
  chapters: book.chapters.map(toLibChapter).toList(),
  totalBytes: book.byteSize,
  hasCover: book.hasCover,
  modifiedAt: book.modifiedAt,
);

/// `ChapterEntry` → [LibChapter]。
LibChapter toLibChapter(ChapterEntry chapter) => LibChapter(
  no: (chapter.no ?? 0).toDouble(),
  pageCount: chapter.seqMax,
  donePages: chapter.translatedCount,
  dirName: chapter.dirName,
  translatedSeqs: chapter.translatedSeqs.toSet(),
  missingSeqs: chapter.missingSeqs.toSet(),
  merged: chapter.merged,
);

/// 每批 20 张（服务端规格）。
int batchOf(int pages) => pages <= 0 ? 1 : (pages / 20).ceil();

MangaTaskSource _sourceOf(TaskSource source) => switch (source) {
  TaskSource.extension => MangaTaskSource.extension,
  TaskSource.desktop => MangaTaskSource.desktop,
  TaskSource.unknown => MangaTaskSource.unknown,
};

MangaTaskStatus _statusOf(TaskStatus status) => switch (status) {
  TaskStatus.queued => MangaTaskStatus.queued,
  TaskStatus.running => MangaTaskStatus.translating,
  TaskStatus.done => MangaTaskStatus.done,
  TaskStatus.partialFailed => MangaTaskStatus.partialFailed,
  TaskStatus.failed => MangaTaskStatus.failed,
  TaskStatus.canceled => MangaTaskStatus.cancelled,
};

/// `ChapterEntry`（未归并单话）→ [LibBook]：无话层、无封面状态沿用，`isBook=false`。
LibBook toLibBookFromChapter(ChapterEntry c) => LibBook(
  key: c.dirName,
  name: c.dirName,
  author: '',
  chapters: const [],
  totalBytes: 0,
  hasCover: false,
  modifiedAt: c.modifiedAt,
  isBook: false,
);
