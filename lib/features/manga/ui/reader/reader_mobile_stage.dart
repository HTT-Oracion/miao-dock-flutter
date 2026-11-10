import 'package:flutter/material.dart';

import '../../controller/library_controller.dart';
import 'reader_prefs.dart';
import 'reader_stage.dart';
import 'reader_widgets.dart';

/// 漫画库移动端舞台：数据侧适配 [ReaderSession]，交互全部交给 [ReaderStage]。
///
/// 在线阅读器也复用同一个 [ReaderStage]，只替换页面内容与数据源；
/// 手势、缩放、翻页、点击分区、亮度边缘、自动隐藏工具栏的行为以这里为唯一基准。
class MobileReaderStage extends StatelessWidget {
  const MobileReaderStage({
    super.key,
    required this.session,
    required this.index,
    required this.showOriginal,
    required this.prefs,
    required this.onPage,
    required this.onToggleBar,
    required this.onBrightnessDelta,
    required this.onEndReached,
  });

  final ReaderSession session;

  /// 0 基当前页。
  final int index;
  final bool showOriginal;
  final ReaderPrefs prefs;

  /// 提交翻页（绝对页码，0 基）。
  final ValueChanged<int> onPage;
  final VoidCallback onToggleBar;
  final ValueChanged<double> onBrightnessDelta;

  /// 末页继续往后拖（出章末衔接卡）。
  final VoidCallback onEndReached;

  @override
  Widget build(BuildContext context) {
    return ReaderStage(
      pageCount: session.pages,
      index: index,
      showOriginal: showOriginal,
      prefs: prefs,
      onPage: onPage,
      onToggleBar: onToggleBar,
      onBrightnessDelta: onBrightnessDelta,
      onEndReached: onEndReached,
      isTranslated: session.translated.contains,
      showPageBadge: true,
      pageBuilder: (context, seq, showOriginal) => ReaderPage(session: session, seq: seq, showOriginal: showOriginal),
    );
  }
}
