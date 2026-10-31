/// 续做（补页）与返工计划 —— 对应 B7/B8。
///
/// ## 两种计划不能合并
/// - **resume**：只列「有原图、缺译文」的页（要补的）；
/// - **retranslate**：列「所有有原图」的页（要重做的），并报「其中已有译文」的覆盖数。
///
/// 原项目 `store.rs` 的 `resume_plan` / `retranslate_plan` 就是两套结构。
/// 混成一个会让 UI 分不清「补几页」与「覆盖几页」。
library;

import 'dart:io';

import '../server/http.dart';

/// 目录扫描出的页信息。
class ScannedPage {
  const ScannedPage({required this.seq, required this.ext, required this.byteSize, required this.originalFile});

  final int seq;
  final String ext;
  final int byteSize;
  final String originalFile;
}

/// 扫描结果：原图页 + 已译页码。
class DirScan {
  const DirScan({required this.originals, required this.translatedSeqs});

  final List<ScannedPage> originals;

  /// 已译页码（升序、去重）。
  final List<int> translatedSeqs;

  bool hasTranslation(int seq) => translatedSeqs.contains(seq);
}

/// 扫描一个话目录：区分原图与译文。
///
/// 约定：`001.png` 是原图，`001_translated.png` 是译文。
/// **不维护第二份索引** —— 直接读目录（原项目 §5.8 同口径）。
DirScan scanChapterDir(Directory dir) {
  if (!dir.existsSync()) {
    throw ServiceError('TASK_NOT_FOUND', '目录不存在', details: {'dir': dir.path}, status: 404);
  }
  final originals = <ScannedPage>[];
  final translated = <int>[];
  for (final e in dir.listSync(followLinks: false)) {
    if (e is! File) continue;
    final name = e.path.split(Platform.pathSeparator).last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (!_imageExts.contains(ext)) continue;
    final seq = _seqOf(name);
    if (seq == null) continue;
    if (name.contains('_translated')) {
      translated.add(seq);
      continue;
    }
    originals.add(ScannedPage(seq: seq, ext: ext, byteSize: _sizeOf(e), originalFile: name));
  }
  originals.sort((a, b) => a.seq.compareTo(b.seq));
  translated.sort();
  return DirScan(originals: originals, translatedSeqs: translated.toSet().toList());
}

/// 续做计划。
Map<String, dynamic> buildResumePlan(String dirName, Directory dir) {
  final scan = scanChapterDir(dir);
  final pendings = scan.originals.where((p) => !scan.hasTranslation(p.seq)).toList();
  return {
    'comicName': dirName,
    'dirName': dirName,
    'outputDir': dir.path,
    'imageCount': scan.originals.length,
    'translatedCount': scan.translatedSeqs.length,
    'pendingCount': pendings.length,
    'translatedSeqs': scan.translatedSeqs,
    'pendings': [
      for (final p in pendings) {'seq': p.seq, 'ext': p.ext, 'byteSize': p.byteSize, 'originalFile': p.originalFile},
    ],
  };
}

/// 返工计划。
Map<String, dynamic> buildRetranslatePlan(String dirName, Directory dir) {
  final scan = scanChapterDir(dir);
  final candidates = [
    for (final p in scan.originals)
      {
        'seq': p.seq,
        'ext': p.ext,
        'byteSize': p.byteSize,
        'originalFile': p.originalFile,
        'hadTranslation': scan.hasTranslation(p.seq),
      },
  ];
  final overwrite = candidates.where((c) => c['hadTranslation'] == true).length;
  return {
    'comicName': dirName,
    'dirName': dirName,
    'outputDir': dir.path,
    'imageCount': scan.originals.length,
    'translatedCount': scan.translatedSeqs.length,
    'retranslateCount': candidates.length,
    'overwriteCount': overwrite,
    'candidates': candidates,
  };
}

/// 话号校验 —— 与原项目同口径：1–999，最多一位小数。
///
/// 拒绝 `0`、`1000`、`1.25`、`1.0`（`1.0` 归一化成 `1`）。
/// 非法话号直接报错，**不静默当成 1**。
double parseChapterNo(String raw) {
  final m = RegExp(r'^(\d{1,3})(?:\.([1-9]))?$').firstMatch(raw);
  if (m == null) {
    throw ServiceError('TASK_NOT_FOUND', '话号必须是 1–999 的整数或一位小数', details: {'chapterNo': raw});
  }
  final no = double.parse(raw);
  if (no < 1 || no > 999) {
    throw ServiceError('TASK_NOT_FOUND', '话号必须在 1–999 之间', details: {'chapterNo': raw});
  }
  return no;
}

const Set<String> _imageExts = {'png', 'jpg', 'jpeg', 'webp'};

int? _seqOf(String name) {
  final m = RegExp(r'^(\d+)').firstMatch(name);
  return m == null ? null : int.tryParse(m.group(1)!);
}

int _sizeOf(File f) {
  try {
    return f.lengthSync();
  } catch (_) {
    return 0;
  }
}
