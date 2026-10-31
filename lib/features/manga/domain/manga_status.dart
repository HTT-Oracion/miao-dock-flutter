import 'package:flutter/material.dart';

import 'manga_task.dart';

import '../../../core/theme/tokens.dart';

/// 任务状态的展示语义：标签与状态色（设计稿 H Note 09 色表）。
extension MangaTaskStatusX on MangaTaskStatus {
  String get label => switch (this) {
    MangaTaskStatus.translating => '翻译中',
    MangaTaskStatus.queued => '排队中',
    MangaTaskStatus.done => '已完成',
    MangaTaskStatus.partialFailed => '部分失败',
    MangaTaskStatus.failed => '失败',
    MangaTaskStatus.cancelled => '已取消',
  };

  Color get color => switch (this) {
    MangaTaskStatus.translating => const Color(0xFF7BA7CE),
    MangaTaskStatus.queued => AppTokens.textSecondary,
    MangaTaskStatus.done => AppTokens.success,
    MangaTaskStatus.partialFailed => const Color(0xFFD9A441),
    MangaTaskStatus.failed => const Color(0xFFD98C84),
    MangaTaskStatus.cancelled => AppTokens.textSecondary,
  };
}
