import 'package:flutter/material.dart';

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
  ///
  /// 🔴 领域层不依赖 BuildContext：这里给的是**深色档**色相。
  /// 需要跟随浅色主题时，调用方用 `MangaTaskStatusColor.of(context, status)`（见 ui 层）。
  Color get color => switch (this) {
    MangaTaskStatus.translating => const Color(0xFF7BA7CE),
    MangaTaskStatus.queued => const Color(0xFFA3B0BC),
    MangaTaskStatus.done => const Color(0xFF7FB58A),
    MangaTaskStatus.partialFailed => const Color(0xFFD9A441),
    MangaTaskStatus.failed => const Color(0xFFD98C84),
    MangaTaskStatus.cancelled => const Color(0xFFA3B0BC),
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
