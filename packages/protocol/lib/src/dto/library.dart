/// 漫画库契约 —— 逐字对齐原项目 `src/types/index.ts` 的
/// `ComicEntry` / `BookEntry` / `ChapterEntry` / `LibraryResponse`。
///
/// ## 「本 → 话 → 页」三层与两套视图
/// 原项目同时存在两套视图，**不是冗余**：
///   · [ComicEntry] 是**目录级平铺**（一目录一条），删除 / 定位 / 返工仍按它；
///   · [BookEntry] 只对有 `manifest.json` 的大类目录产出，并把内部话目录展开成 [ChapterEntry]。
/// 迁移时两套都要保留，否则「队列查看定位到库」这类既有动作会失效。
library;

/// 目录级平铺条目。
class ComicEntry {
  const ComicEntry({
    required this.comicName,
    required this.dirName,
    required this.outputDir,
    required this.imageCount,
    required this.translatedCount,
    required this.byteSize,
    required this.seqMax,
    required this.nextSeq,
    required this.translatedSeqs,
    required this.missingSeqs,
    this.modifiedAt,
  });

  final String comicName;
  final String dirName;
  final String outputDir;
  final int imageCount;
  final int translatedCount;
  final int byteSize;
  final int seqMax;
  final int nextSeq;

  /// 已译页码（升序）。
  ///
  /// 🔴 判定「哪一页已译」**必须**用它，不能用 `translatedCount`：
  /// 缺页落在中间时（如 seq=3 失败），`seq <= translatedCount` 会把后面每一页
  /// 整体前移一位，把没译文的页标成「已译」。
  final List<int> translatedSeqs;

  /// 1..seqMax 内没有原图的页码；正常为空。
  final List<int> missingSeqs;

  final DateTime? modifiedAt;

  /// 第 [seq] 页是否已译。
  bool isTranslated(int seq) => translatedSeqs.contains(seq);
}

/// 大类（本）。
class BookEntry {
  const BookEntry({
    required this.bookName,
    required this.dirName,
    required this.outputDir,
    required this.title,
    required this.author,
    required this.chapterCount,
    required this.totalPages,
    required this.byteSize,
    required this.chapters,
    this.coverPath,
    this.modifiedAt,
  });

  final String bookName;
  final String dirName;
  final String outputDir;
  final String title;

  /// 空串 = 未署名（UI 显示「未署名」）。
  final String author;

  /// 封面在书籍目录内的**文件名**，无封面为 null。
  ///
  /// ⚠️ 不是可渲染 URL：取字节要走 `GET /library/{book}/cover`。
  final String? coverPath;

  final int chapterCount;
  final int totalPages;
  final int byteSize;
  final DateTime? modifiedAt;

  /// 全部话（服务端已按话号升序）。
  final List<ChapterEntry> chapters;

  bool get hasCover => coverPath != null && coverPath!.isNotEmpty;
  bool get hasAuthor => author.isNotEmpty;
}

/// 话。
///
/// 同一形状服务两种来源：
/// - **已归并**：大类下的 `01_第1话` 子目录 ⇒ [no] 有值、[merged] 为 true；
/// - **未归并单话**：库根下普通目录 ⇒ [no] 为 null、[merged] 为 false。
class ChapterEntry {
  const ChapterEntry({
    required this.dirName,
    required this.absDir,
    required this.imageCount,
    required this.translatedCount,
    required this.seqMax,
    required this.translatedSeqs,
    required this.missingSeqs,
    required this.merged,
    this.no,
    this.mergedTo,
    this.modifiedAt,
  });

  /// 已归并：话号；未归并：null。
  final int? no;

  final String dirName;
  final String absDir;
  final int imageCount;
  final int translatedCount;
  final int seqMax;

  /// 已译页码（升序）。逐页判定必须用集合，**禁用** `seq <= translatedCount`。
  final List<int> translatedSeqs;

  final List<int> missingSeqs;

  /// 是否已被归并 —— 决定它能否被单独删除（已归并的只能从所属漫画里删）。
  final bool merged;

  /// 已归并时的归属；未归并为 null。
  final MergedTo? mergedTo;

  final DateTime? modifiedAt;

  bool isTranslated(int seq) => translatedSeqs.contains(seq);

  /// 翻译进度 0–1。
  double get ratio => seqMax <= 0 ? 0 : translatedCount / seqMax;
}

/// 归并归属。
class MergedTo {
  const MergedTo({required this.bookName, required this.no});

  final String bookName;
  final int no;
}

/// `GET /api/v1/library` 的响应。
class LibraryResponse {
  const LibraryResponse({
    required this.root,
    required this.count,
    required this.totalImages,
    required this.totalBytes,
    required this.comics,
    required this.updatedAt,
    this.books,
    this.others,
    this.hidden,
    this.hiddenCount,
  });

  final String root;
  final int count;
  final int totalImages;
  final int totalBytes;

  /// 目录级平铺视图（含大类目录与未归并单话）。
  final List<ComicEntry> comics;

  /// 大类；**可选**（旧服务端不返回）。
  final List<BookEntry>? books;

  /// 未归并的单话（左栏「其它」分组）；**可选**。
  final List<ChapterEntry>? others;

  /// 被「只从库里移除、不删本地文件」的漫画名（服务端持久化）。
  final List<String>? hidden;

  final int? hiddenCount;
  final DateTime updatedAt;

  /// 有效的本列表：新服务端用 [books]，旧服务端退回从 [comics] 推导。
  List<BookEntry> get effectiveBooks => books ?? const [];
}

/// `POST /api/v1/library/{name}/delete` 的响应。
class LibraryDeleteResponse {
  const LibraryDeleteResponse({
    required this.comicName,
    required this.deletedFiles,
    this.outputDir,
    this.hidden,
    this.hiddenCount,
  });

  final String comicName;

  /// true = 连本地目录一起删了；false = 只从库里隐藏。
  final bool deletedFiles;

  final String? outputDir;
  final List<String>? hidden;
  final int? hiddenCount;
}

/// 续做（补页）计划 —— 对应 `GET /library/{name|book}/resume`。
///
/// 与 [RetranslatePlan] 是**两种不同的计划**，不可合并：
///   · resume 只含「有原图、缺译文」的页（[pendings]）；
///   · retranslate 含「所有有原图」的页（[RetranslatePlan.candidates]），并报覆盖数。
class ResumePlan {
  const ResumePlan({
    required this.comicName,
    required this.dirName,
    required this.outputDir,
    required this.imageCount,
    required this.translatedCount,
    required this.pendingCount,
    required this.pendings,
    required this.translatedSeqs,
    this.reworking = false,
  });

  final String comicName;
  final String dirName;
  final String outputDir;

  /// 有原图的页数。
  final int imageCount;

  /// 已有译文的页数。
  final int translatedCount;

  /// 待补页数（= [pendings].length）。
  final int pendingCount;

  /// 待补页明细（有原图、缺译文）。
  final List<ResumePending> pendings;

  /// 已译页码（升序）。
  final List<int> translatedSeqs;

  /// 该漫画是否已有任务在队列中（前端补的字段，非服务端返回）。
  final bool reworking;

  /// 无事可做 —— 全部页都已译。
  bool get isComplete => pendingCount == 0;
}

/// 待补页。
class ResumePending {
  const ResumePending({required this.seq, required this.ext, required this.byteSize, required this.originalFile});

  final int seq;
  final String ext;
  final int byteSize;
  final String originalFile;
}

/// `GET /api/v1/library/{comicName}/retranslate` 的返工计划。
class RetranslatePlan {
  const RetranslatePlan({
    required this.comicName,
    required this.dirName,
    required this.outputDir,
    required this.imageCount,
    required this.translatedCount,
    required this.retranslateCount,
    required this.overwriteCount,
    required this.candidates,
    this.reworking = false,
  });

  final String comicName;
  final String dirName;
  final String outputDir;
  final int imageCount;
  final int translatedCount;

  /// 有原图的页数 = 本次默认返工范围。
  final int retranslateCount;

  /// 其中已有译文的页数 = 会被覆盖的页数（**不可逆，UI 必须提示**）。
  final int overwriteCount;

  final List<RetranslateCandidate> candidates;

  /// 该漫画是否已有任务在队列中（前端补的字段，非服务端返回）。
  final bool reworking;

  bool get hasOverwrite => overwriteCount > 0;
}

/// 返工候选页。
class RetranslateCandidate {
  const RetranslateCandidate({
    required this.seq,
    required this.ext,
    required this.byteSize,
    required this.originalFile,
    required this.hadTranslation,
  });

  final int seq;
  final String ext;
  final int byteSize;
  final String originalFile;
  final bool hadTranslation;
}
