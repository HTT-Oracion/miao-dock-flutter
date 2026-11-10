import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../controller/library_controller.dart';
import '../../controller/queue_controller.dart';
import 'reader_image_cache.dart';
import 'reader_webtoon_stage.dart';
import 'reader_widgets.dart';

/// 条漫（webtoon）连续滚动视图：数据侧适配 [ReaderSession]，交互交给共享
/// [ReaderWebtoonStage]，与在线阅读器保持同一套滚动 / 点按 / 自动滚动语义。
class ReaderWebtoonView extends StatelessWidget {
  const ReaderWebtoonView({
    super.key,
    required this.session,
    required this.showOriginal,
    required this.onCenterTap,
    this.endCard,
  });

  final ReaderSession session;
  final bool showOriginal;
  final VoidCallback onCenterTap;

  /// 末尾衔接卡（由屏幕装配：文案与去向要跟翻页模式一致）。
  final Widget? endCard;

  @override
  Widget build(BuildContext context) {
    return ReaderWebtoonStage(
      pageCount: session.pages,
      onCenterTap: onCenterTap,
      endCard: endCard,
      pageBuilder: (context, seq) => _WebtoonPage(session: session, seq: seq, showOriginal: showOriginal),
    );
  }
}

/// 条漫页：整宽自适应高度（与翻页模式的 contain 不同——条漫页要无缝相接）。
class _WebtoonPage extends ConsumerStatefulWidget {
  const _WebtoonPage({required this.session, required this.seq, required this.showOriginal});

  final ReaderSession session;
  final int seq;
  final bool showOriginal;

  @override
  ConsumerState<_WebtoonPage> createState() => _WebtoonPageState();
}

class _WebtoonPageState extends ConsumerState<_WebtoonPage> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _WebtoonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showOriginal != widget.showOriginal) {
      setState(() => _future = _load());
    }
  }

  Future<Uint8List?> _load() async {
    final client = ref.read(mangaSvcClientProvider);
    final s = widget.session;
    // 🔴 显示原图时不请求译文；显示译文时按该页是否有译文取（与翻页模式同语义）。
    final wantTranslated = !widget.showOriginal && s.translated.contains(widget.seq);
    final key = readerImageKey(bookKey: s.key, chapterNo: s.chapterNo, seq: widget.seq, translated: wantTranslated);
    final cached = ReaderImageCache.get(key);
    if (cached != null) return cached;
    try {
      final bytes = s.chapterNo == null
          ? await client.getBookFile(s.key, widget.seq, translated: wantTranslated)
          : await client.getChapterFile(s.key, s.chapterNo!, widget.seq, translated: wantTranslated);
      if (bytes.isEmpty) return null;
      final data = Uint8List.fromList(bytes);
      ReaderImageCache.put(key, data);
      return data;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            height: 420,
            color: palette.card,
            alignment: Alignment.center,
            child: ReaderSpinner(color: palette.textSecondary),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return Container(
            height: 120,
            color: palette.card,
            alignment: Alignment.center,
            child: Text(
              AppLocalizations.of(context).shelfNoMatch,
              style: TextStyle(fontSize: AppFont.px11, color: palette.textSecondary),
            ),
          );
        }
        return ReaderPageImage(bytes: bytes, fit: BoxFit.fitWidth, width: double.infinity);
      },
    );
  }
}
