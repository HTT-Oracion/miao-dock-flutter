/// 漫画库作品 —— 书架行与详情 Hero 使用的 UI 模型。
class LibBook {
  const LibBook({
    required this.key,
    required this.name,
    required this.author,
    required this.chapters,
    required this.totalBytes,
    this.hasCover = false,
    this.modifiedAt,
    this.isBook = true,
    this.directPages = 0,
    this.directTranslated = const {},
  });

  /// 归并键（= 服务端 `dirName`）。
  final String key;

  /// 展示名（优先 `title`，回落到目录名）。
  final String name;

  /// 作者；空串 = 未署名。
  final String author;

  final List<LibChapter> chapters;
  final int totalBytes;

  /// 是否有封面（判定用；取字节要走 `/library/{book}/cover`）。
  final bool hasCover;

  final DateTime? modifiedAt;

  /// 是否单本（true）/未归并单话（false）。单话没有 manifest，话数恒 0。
  final bool isBook;

  /// 单话直读页数（无话层时阅读器用）。
  final int directPages;

  /// 单话直读已译页码。
  final Set<int> directTranslated;

  int get chapterCount => chapters.length;

  /// 总页数：单本按话汇总；单话用直读页数。
  int get pageCount => isBook ? chapters.fold(0, (sum, c) => sum + c.pageCount) : directPages;

  /// 未署名时 UI 显示「未署名」。
  bool get hasAuthor => author.isNotEmpty;
}

/// 库内一话：页数与翻译进度（颜色语义与队列状态一致）。
class LibChapter {
  const LibChapter({
    required this.no,
    required this.pageCount,
    required this.donePages,
    this.dirName = '',
    this.translatedSeqs = const {},
    this.missingSeqs = const {},
    this.merged = false,
  });

  final double no;
  final int pageCount;
  final int donePages;

  /// 目录名（删除 / 归并等操作要用）。
  final String dirName;

  /// 已译页码集合。
  ///
  /// 🔴 逐页判定必须用它，**不能用** `seq <= donePages`：中间缺页时后者会把
  /// 后面每一页整体前移一位，把没译文的页标成「已译」。
  final Set<int> translatedSeqs;

  /// 缺原图的页码。
  final Set<int> missingSeqs;

  /// 是否已归并（已归并的不能单独删，只能从所属漫画里删）。
  final bool merged;

  bool get done => donePages >= pageCount;
  double get ratio => pageCount == 0 ? 0 : donePages / pageCount;

  /// 第 [seq] 页是否已译（逐页判定，走集合）。
  bool isTranslated(int seq) => translatedSeqs.contains(seq);

  /// 第 [seq] 页是否缺原图。
  bool isMissing(int seq) => missingSeqs.contains(seq);
}
