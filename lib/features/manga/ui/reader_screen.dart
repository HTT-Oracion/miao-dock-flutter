import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:protocol/protocol.dart' show jsNumStr;

import '../../../core/storage/shell_prefs.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/buttons.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';

/// 完整阅读器（B.6）。
///
/// - 桌面：左右方向键 / 点击两侧翻页，滚轮与拖拽缩放；
/// - 移动端：左右滑动翻页、双指缩放（[InteractiveViewer] + [PageView]）。
/// - 页面内容：**有译文显示译文，没有译文回退原图**（miao-dock `viewer.tsx` 同语义），
///   所以「未翻译完也能点查看」。
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _controller = PageController();
  int _index = 0;

  /// 是否显示原图。**默认 false = 看译文**；用户切换后持久化。
  late bool _showOriginal = readReaderShowOriginal();

  void _toggleOriginal() {
    setState(() => _showOriginal = !_showOriginal);
    persistReaderShowOriginal(_showOriginal);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta, int total) {
    final next = (_index + delta).clamp(0, total - 1);
    if (next == _index) return;
    _controller.animateToPage(next, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(readerSessionProvider);

    if (session == null || session.pages <= 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.shelfEmpty, style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => context.go('/manga/library'),
              child: Text(l10n.readerClose, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    final total = session.pages;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _go(1, total);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _go(-1, total);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          _ReaderBar(
            title: session.chapterNo == null
                ? session.key
                : '${session.key} · ${l10n.chapterTitle(jsNumStr(session.chapterNo!))}',
            pageText: l10n.readerPage(_index + 1, total),
            // 按钮文案随状态切换：当前看译文 → 按钮写「显示原图」，反之亦然。
            toggleLabel: _showOriginal ? l10n.readerShowTranslated : l10n.readerShowOriginal,
            onToggle: _toggleOriginal,
            onClose: _close,
          ),
          Expanded(
            child: Stack(
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: total,
                  onPageChanged: (i) => setState(() => _index = i),
                  // key 里带上 showOriginal：切换模式时强制重建该页，确保重新取图。
                  itemBuilder: (context, i) => _ReaderPage(
                    key: ValueKey('p-$i-$_showOriginal'),
                    session: session,
                    seq: i + 1,
                    showOriginal: _showOriginal,
                  ),
                ),
                // 桌面端点击两侧翻页（移动端用滑动，不挡手势区）。
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 56,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _go(-1, total),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(left: 12),
                        child: Icon(LucideIcons.chevronLeft, size: 20, color: palette.textSecondary),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 56,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _go(1, total),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Icon(LucideIcons.chevronRight, size: 20, color: palette.textSecondary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _close() {
    ref.read(readerSessionProvider.notifier).close();
    if (context.mounted) context.go('/manga/library');
  }
}

class _ReaderBar extends StatelessWidget {
  const _ReaderBar({
    required this.title,
    required this.pageText,
    required this.toggleLabel,
    required this.onToggle,
    required this.onClose,
  });

  final String title;
  final String pageText;
  final String toggleLabel;
  final VoidCallback onToggle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.navBg,
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onClose,
            child: Row(
              children: [
                Icon(LucideIcons.chevronLeft, size: 14, color: palette.textSecondary),
                SizedBox(width: 2),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: palette.textPrimary),
            ),
          ),
          AppButton(
            label: toggleLabel,
            onTap: onToggle,
            variant: AppButtonVariant.ghost,
            border: true,
            height: 24,
            horizontalPadding: 9,
            fontSize: 10.5,
          ),
          const SizedBox(width: 10),
          Text(pageText, style: TextStyle(fontSize: 11.5, color: palette.textSecondary)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onClose,
            child: Icon(LucideIcons.x, size: 15, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 单页：先取译文（服务端缺译文自动回退原图），失败再直接取原图。
class _ReaderPage extends ConsumerStatefulWidget {
  const _ReaderPage({super.key, required this.session, required this.seq, required this.showOriginal});

  final ReaderSession session;
  final int seq;

  /// true = 取原图；false = 取译文（缺译文时服务端自动回退原图）。
  final bool showOriginal;

  @override
  ConsumerState<_ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<_ReaderPage> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换原图/译文后必须重新取图，否则画面不变。
    if (oldWidget.showOriginal != widget.showOriginal) {
      setState(() => _future = _load());
    }
  }

  Future<Uint8List?> _load() async {
    final client = ref.read(mangaSvcClientProvider);
    final s = widget.session;
    // 🔴 显示原图时**不请求译文**；显示译文时按该页是否有译文取。
    final wantTranslated = !widget.showOriginal && s.translated.contains(widget.seq);
    try {
      final bytes = s.chapterNo == null
          ? await client.getBookFile(s.key, widget.seq, translated: wantTranslated)
          : await client.getChapterFile(s.key, s.chapterNo!, widget.seq, translated: wantTranslated);
      if (bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
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
          return Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: palette.textSecondary),
            ),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return Center(
            child: Text(
              AppLocalizations.of(context).shelfNoMatch,
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          );
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)),
        );
      },
    );
  }
}
