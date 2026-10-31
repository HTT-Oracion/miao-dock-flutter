import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'manga_task.dart';

/// 任务状态的展示语义：标签与状态色（设计稿 H Note 09 色表）。
///
/// 标签走 ARB：`domain` 层不能持有 `BuildContext`，故由调用方传入 [AppLocalizations]。
extension MangaTaskStatusX on MangaTaskStatus {
  /// 状态文案。
  String label(AppLocalizations l10n) => switch (this) {
    MangaTaskStatus.translating => l10n.statusTranslating,
    MangaTaskStatus.queued => l10n.statusQueued,
    MangaTaskStatus.done => l10n.statusDone,
    MangaTaskStatus.partialFailed => l10n.statusPartialFailed,
    MangaTaskStatus.failed => l10n.statusFailed,
    MangaTaskStatus.cancelled => l10n.statusCancelled,
  };

  /// 状态色 —— 色相只由圆点 / 徽标承载，文字保持中性（design.html §02 色相纪律）。
  Color get color => switch (this) {
    MangaTaskStatus.translating => const Color(0xFF7BA7CE),
    MangaTaskStatus.queued => AppTokens.textSecondary,
    MangaTaskStatus.done => AppTokens.success,
    MangaTaskStatus.partialFailed => const Color(0xFFD9A441),
    MangaTaskStatus.failed => const Color(0xFFD98C84),
    MangaTaskStatus.cancelled => AppTokens.textSecondary,
  };
}

/// 任务来源的展示语义。
extension MangaTaskSourceX on MangaTaskSource {
  String label(AppLocalizations l10n) => switch (this) {
    MangaTaskSource.desktop => l10n.queueSourceLocal,
    MangaTaskSource.extension => l10n.sourceExtension,
    MangaTaskSource.unknown => l10n.sourceUnknown,
  };
}
