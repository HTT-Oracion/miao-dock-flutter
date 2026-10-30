/// 漫画库作品（书架行与详情 Hero）。
class LibBook {
  const LibBook({
    required this.key,
    required this.name,
    required this.author,
    required this.chapters,
    required this.totalBytes,
  });

  final String key;
  final String name;
  final String author;
  final List<LibChapter> chapters;
  final int totalBytes;

  int get chapterCount => chapters.length;
  int get pageCount => chapters.fold(0, (sum, c) => sum + c.pageCount);
}

/// 库内一话：页数与翻译进度（颜色语义与队列状态一致）。
class LibChapter {
  const LibChapter({required this.no, required this.pageCount, required this.donePages});

  final int no;
  final int pageCount;
  final int donePages;

  bool get done => donePages >= pageCount;
  double get ratio => pageCount == 0 ? 0 : donePages / pageCount;
}
