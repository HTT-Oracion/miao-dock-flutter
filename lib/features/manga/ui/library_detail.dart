import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:protocol/protocol.dart' show BookMeta, jsNumStr;

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/toast.dart';
import '../../../core/utils/format.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';
import '../domain/lib_book.dart';
import '../domain/manga_status.dart';
import '../domain/manga_task.dart';
import 'library_search_results.dart';
import 'shelf_menu.dart';

/// 详情主区（设计稿 G Main）：
/// 头部（本地漫画库 + 刷新 + 新建）→ Hero（封面 + 标题 + 元信息 + 动作）→
/// 章节区（卡片 / 简易胶囊，`.view-seg` 切换）。
class LibraryDetail extends ConsumerWidget {
  const LibraryDetail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(shelfQueryProvider).trim();
    if (query.isNotEmpty) {
      return LibrarySearchResults(query: query);
    }
    final state = ref.watch(libraryProvider);
    final books = state.value ?? ref.read(libraryProvider.notifier).lastGood;

    if (books.isEmpty && state.hasError) {
      return ErrorState(error: state.error, onRetry: () => ref.read(libraryProvider.notifier).refresh());
    }
    if (books.isEmpty) {
      return Column(
        children: [
          _LibHeader(count: 0),
          Expanded(
            child: Center(
              child: Text(
                AppLocalizations.of(context).shelfEmpty,
                style: const TextStyle(fontSize: 12.5, color: AppTokens.textSecondary),
              ),
            ),
          ),
        ],
      );
    }
    final selected = ref.watch(selectedBookProvider);
    final book = books.where((b) => b.key == selected).firstOrNull ?? books.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        _LibHeader(count: books.length),
        const SizedBox(height: 12),
        _Hero(book: book),
        if (!book.isBook) ...[
          const SizedBox(height: 16),
          const _PageSectionHeader(),
          const SizedBox(height: 10),
          ref.watch(libModeProvider) == 'capsule' ? _PageCapsules(book: book) : _PageGrid(book: book),
        ],
        if (book.isBook) ...[
          const SizedBox(height: 16),
          _SectionHeader(book: book),
          const SizedBox(height: 10),
          if (book.chapters.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  AppLocalizations.of(context).shelfEmpty,
                  style: const TextStyle(fontSize: 12.5, color: AppTokens.textSecondary),
                ),
              ),
            )
          else
            ref.watch(libModeProvider) == 'capsule' ? _ChapterCapsules(book: book) : _ChapterGrid(book: book),
        ],
      ],
    );
  }
}

/// 主区头部（ver1.0 `.lib-main` 头）：本地漫画库 + 计数 + 刷新 + 新建漫画。
class _LibHeader extends ConsumerWidget {
  const _LibHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        const Icon(LucideIcons.libraryBig, size: 15, color: AppTokens.textSecondary),
        const SizedBox(width: 8),
        Text(
          l10n.libLocalLibrary,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
        ),
        const SizedBox(width: 8),
        Text('$count', style: const TextStyle(fontSize: 11, color: AppTokens.textSecondary)),
        const Spacer(),
        _HeaderAction(
          icon: LucideIcons.refreshCw,
          label: l10n.libRefresh,
          onTap: () async {
            await ref.read(libraryProvider.notifier).refresh();
          },
        ),
        const SizedBox(width: 8),
        _HeaderAction(
          icon: LucideIcons.folderPlus,
          label: l10n.libCreateBook,
          primary: true,
          onTap: () async {
            final name = await _CreateBookDialog.show(context);
            if (name == null || !context.mounted) return;
            try {
              await ref.read(mangaSvcClientProvider).createBook(name);
              await ref.read(libraryProvider.notifier).refresh();
              if (context.mounted) showAppToast(context, l10n.libCreateBookOk(name), tone: ToastTone.good);
            } catch (e) {
              if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
            }
          },
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.label, this.primary = false, required this.onTap});

  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: primary ? AppTokens.accent : AppTokens.card,
          borderRadius: BorderRadius.circular(6),
          border: primary ? null : Border.all(color: AppTokens.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: primary ? AppTokens.pageBg : AppTokens.textSecondary),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 10.5, color: primary ? AppTokens.pageBg : AppTokens.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Cover(book: book),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.textPrimary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (!book.isBook) _MetaChip(l10n.libUnmerged),
                    if (book.isBook) _MetaChip(l10n.bookAuthorLabel(book.author)),
                    _MetaChip(
                      book.isBook ? l10n.bookChapterCount(book.chapterCount) : l10n.bookPageCount(book.pageCount),
                    ),
                    if (book.isBook) _MetaChip(l10n.bookPageCount(book.pageCount)),
                    _MetaChip(formatBytes(book.totalBytes)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (book.isBook) ...[
                      _HeroButton(
                        icon: LucideIcons.play,
                        label: l10n.bookContinueTranslate,
                        primary: true,
                        onTap: () async {
                          final client = ref.read(mangaSvcClientProvider);
                          try {
                            final plan = await client.getResumePlan(book.key);
                            if (plan.pendingCount == 0) {
                              if (context.mounted) {
                                showAppToast(context, l10n.libAllTranslated, tone: ToastTone.info);
                              }
                              return;
                            }
                            await client.resumeBook(book.key);
                            if (context.mounted) {
                              showAppToast(context, l10n.libResumeSubmitted, tone: ToastTone.good);
                            }
                          } catch (e) {
                            if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      _HeroButton(
                        icon: LucideIcons.pencil,
                        label: l10n.libEditInfo,
                        onTap: () async {
                          final meta = await _EditBookDialog.show(context, book: book);
                          if (meta == null || !context.mounted) return;
                          try {
                            await ref.read(mangaSvcClientProvider).setBookMeta(book.key, meta);
                            await ref.read(libraryProvider.notifier).refresh();
                            if (context.mounted) showAppToast(context, l10n.libEditInfoOk, tone: ToastTone.good);
                          } catch (e) {
                            if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
                          }
                        },
                      ),
                    ] else ...[
                      _HeroButton(
                        icon: LucideIcons.bookOpen,
                        label: l10n.libViewComic,
                        onTap: () {
                          ref
                              .read(readerSessionProvider.notifier)
                              .open(
                                ReaderSession(
                                  key: book.key,
                                  pages: book.directPages,
                                  translated: book.directTranslated,
                                ),
                              );
                          context.go('/manga/reader');
                        },
                      ),
                      const SizedBox(width: 8),
                      _HeroButton(
                        icon: LucideIcons.gitMerge,
                        label: l10n.libMerge,
                        primary: true,
                        onTap: () async {
                          final result = await showMergeDialog(context, src: book.key);
                          if (result == null || !context.mounted) return;
                          try {
                            await ref
                                .read(mangaSvcClientProvider)
                                .mergeChapter(book.key, targetBook: result.$1, no: result.$2);
                            await ref.read(libraryProvider.notifier).refresh();
                            if (context.mounted) showAppToast(context, l10n.libMergeOk, tone: ToastTone.good);
                          } catch (e) {
                            if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
                          }
                        },
                      ),
                    ],
                    const SizedBox(width: 8),
                    _HeroButton(
                      icon: LucideIcons.folderOpen,
                      label: l10n.actionOpenNav,
                      onTap: () async {
                        await ref.read(mangaSvcClientProvider).revealBook(book.key);
                        if (context.mounted) showAppToast(context, l10n.libRevealDone, tone: ToastTone.info);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 封面：走 `/library/{name}/cover`；单话默认第一页（服务端回退）。
class _Cover extends ConsumerStatefulWidget {
  const _Cover({required this.book});

  final LibBook book;

  @override
  ConsumerState<_Cover> createState() => _CoverState();
}

class _CoverState extends ConsumerState<_Cover> {
  Future<List<int>?>? _future;

  @override
  void initState() {
    super.initState();
    final client = ref.read(mangaSvcClientProvider);
    _future = client.getBookCover(widget.book.key).then<List<int>?>((v) => v).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return Container(
      width: 96,
      height: 112,
      decoration: BoxDecoration(color: AppTokens.cardCover, borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: FutureBuilder<List<int>?>(
        future: _future,
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes == null || bytes.isEmpty) {
            return Icon(
              book.isBook ? LucideIcons.bookOpen : LucideIcons.folder,
              size: 24,
              color: AppTokens.textSecondary,
            );
          }
          return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover, width: 96, height: 112);
        },
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.icon, required this.label, this.primary = false, required this.onTap});

  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = primary
        ? FilledButton.styleFrom(backgroundColor: AppTokens.accent, foregroundColor: AppTokens.pageBg)
        : OutlinedButton.styleFrom(
            foregroundColor: AppTokens.textPrimary,
            side: const BorderSide(color: AppTokens.progressTrack),
          );
    return (primary
        ? FilledButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 13),
            label: Text(label, style: const TextStyle(fontSize: 12.5)),
            style: style,
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 13),
            label: Text(label, style: const TextStyle(fontSize: 12.5)),
            style: style,
          ));
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppTokens.navBg, borderRadius: BorderRadius.circular(5)),
      child: Text(text, style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary)),
    );
  }
}

/// 单话的「页面」区头：标题 + 页数 + 图例 + 卡片/简易切换（与章节区同一套控件）。
class _PageSectionHeader extends ConsumerWidget {
  const _PageSectionHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(libModeProvider);
    return Row(
      children: [
        Text(
          l10n.readerPagesTitle,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
        ),
        const SizedBox(width: 10),
        if (mode == 'capsule')
          Text(l10n.libCapsuleLegend, style: const TextStyle(fontSize: 9.5, color: AppTokens.textSecondary)),
        const Spacer(),
        _ViewSeg(mode: mode, onSelect: (m) => ref.read(libModeProvider.notifier).set(m)),
      ],
    );
  }
}

class _SectionHeader extends ConsumerWidget {
  const _SectionHeader({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(libModeProvider);
    return Row(
      children: [
        Text(
          l10n.bookChapters,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
        ),
        const SizedBox(width: 8),
        Text(
          l10n.bookChapterCount(book.chapterCount),
          style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
        ),
        const SizedBox(width: 10),
        if (mode == 'capsule')
          Text(l10n.libCapsuleLegend, style: const TextStyle(fontSize: 9.5, color: AppTokens.textSecondary)),
        const Spacer(),
        _ViewSeg(mode: mode, onSelect: (m) => ref.read(libModeProvider.notifier).set(m)),
      ],
    );
  }
}

/// 单话「页面」区（卡片态）：每页一格，点开阅读器定位到该页。
class _PageGrid extends ConsumerWidget {
  const _PageGrid({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = book.directPages;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 96,
      ),
      itemCount: total,
      itemBuilder: (context, i) {
        final seq = i + 1;
        final done = book.directTranslated.contains(seq);
        return GestureDetector(
          onTap: () {
            ref
                .read(readerSessionProvider.notifier)
                .open(ReaderSession(key: book.key, pages: total, translated: book.directTranslated));
            context.go('/manga/reader');
          },
          child: Container(
            decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.fileImage, size: 16, color: AppTokens.textSecondary),
                const SizedBox(height: 4),
                Text('$seq', style: const TextStyle(fontSize: 10.5, color: AppTokens.textPrimary)),
                const SizedBox(height: 2),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: done ? AppTokens.success : AppTokens.accent, shape: BoxShape.circle),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 单话「页面」区（简易态）：页码胶囊 + 状态圆点。
class _PageCapsules extends StatelessWidget {
  const _PageCapsules({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var seq = 1; seq <= book.directPages; seq++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$seq', style: const TextStyle(fontSize: 11.5, color: AppTokens.textPrimary)),
                if (!book.directTranslated.contains(seq)) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: AppTokens.accent, shape: BoxShape.circle),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ChapterGrid extends StatelessWidget {
  const _ChapterGrid({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 100,
      ),
      itemCount: book.chapters.length,
      itemBuilder: (context, i) => _ChapterCard(book: book, chapter: book.chapters[i]),
    );
  }
}

class _ChapterCard extends ConsumerWidget {
  const _ChapterCard({required this.book, required this.chapter});

  final LibBook book;
  final LibChapter chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = chapter.done ? MangaTaskStatus.done.color : MangaTaskStatus.translating.color;
    return GestureDetector(
      onTap: () {
        // 查看逻辑同 miao-dock：**未翻译完也能点进**（缺译文的页回退原图）。
        ref
            .read(readerSessionProvider.notifier)
            .open(
              ReaderSession(
                key: book.key,
                chapterNo: chapter.no,
                pages: chapter.pageCount,
                translated: chapter.translatedSeqs,
              ),
            );
        context.go('/manga/reader');
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 64,
              decoration: BoxDecoration(color: AppTokens.cardCover, borderRadius: BorderRadius.circular(6)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).chapterTitle(jsNumStr(chapter.no)),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTokens.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    AppLocalizations.of(context).chapterMeta(chapter.pageCount, chapter.donePages),
                    style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 4,
                      child: LinearProgressIndicator(
                        value: chapter.ratio,
                        backgroundColor: AppTokens.progressTrack,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 简易（胶囊）态：名字 + 状态圆点（待译 蓝 · 缺页 黄 · 已译完不显示）。
class _ChapterCapsules extends StatelessWidget {
  const _ChapterCapsules({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in book.chapters)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: AppTokens.card, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.chapterTitle(jsNumStr(c.no)),
                  style: const TextStyle(fontSize: 11.5, color: AppTokens.textPrimary),
                ),
                if (!c.done) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: c.translatedSeqs.isEmpty
                          ? MangaTaskStatus.translating.color
                          : MangaTaskStatus.partialFailed.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// ── 对话框 ────────────────────────────────────────────────────────────────

class _CreateBookDialog extends StatefulWidget {
  const _CreateBookDialog();

  static Future<String?> show(BuildContext context) =>
      showDialog<String>(context: context, builder: (_) => const _CreateBookDialog());

  @override
  State<_CreateBookDialog> createState() => _CreateBookDialogState();
}

class _CreateBookDialogState extends State<_CreateBookDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: AppTokens.card,
      title: Text(l10n.libCreateBook, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 300,
        child: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(hintText: l10n.libCreateBookNameHint, isDense: true),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel, style: const TextStyle(fontSize: 11.5)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.libCreateBook, style: const TextStyle(fontSize: 11.5)),
        ),
      ],
    );
  }
}

class _EditBookDialog extends StatefulWidget {
  const _EditBookDialog({required this.book});

  final LibBook book;

  static Future<BookMeta?> show(BuildContext context, {required LibBook book}) => showDialog<BookMeta>(
    context: context,
    builder: (_) => _EditBookDialog(book: book),
  );

  @override
  State<_EditBookDialog> createState() => _EditBookDialogState();
}

class _EditBookDialogState extends State<_EditBookDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.book.name);
  late final TextEditingController _author = TextEditingController(text: widget.book.author);

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: AppTokens.card,
      title: Text(l10n.libEditInfoTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(labelText: l10n.libCreateBookNameHint, isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _author,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(labelText: l10n.bookAuthorLabel(''), isDense: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel, style: const TextStyle(fontSize: 11.5)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            BookMeta(
              title: _title.text.trim().isEmpty ? widget.book.name : _title.text.trim(),
              author: _author.text.trim(),
            ),
          ),
          child: Text(l10n.libEditInfoOk, style: const TextStyle(fontSize: 11.5)),
        ),
      ],
    );
  }
}

/// ver1.0 `.view-seg`：卡片 / 简易 切换（章节区与页面区共用）。
class _ViewSeg extends StatelessWidget {
  const _ViewSeg({required this.mode, required this.onSelect});

  final String mode;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: AppTokens.navBg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          for (final m in const ['card', 'capsule'])
            GestureDetector(
              onTap: () => onSelect(m),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: mode == m ? AppTokens.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  m == 'card' ? l10n.libViewCard : l10n.libViewCapsule,
                  style: TextStyle(fontSize: 10.5, color: mode == m ? AppTokens.textPrimary : AppTokens.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
