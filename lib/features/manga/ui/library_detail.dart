import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:protocol/protocol.dart' show BookMeta, jsNumStr;

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/toast.dart';
import '../../../core/utils/format.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';
import '../domain/lib_book.dart';
import '../domain/manga_status.dart';
import '../domain/manga_task.dart';
import 'library_search_results.dart';
import 'chapter_menu.dart';
import 'shelf_menu.dart';

/// 详情主区（设计稿 G Main）：
/// 头部（本地漫画库 + 刷新 + 新建）→ Hero（封面 + 标题 + 元信息 + 动作）→
/// 章节区（卡片 / 简易胶囊，`.view-seg` 切换）。
class LibraryDetail extends ConsumerWidget {
  const LibraryDetail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
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
          // 「返回书架」（ver1.0 `#bk`）：清掉选中即回到默认态。
          Row(
            children: [
              _BackToShelf(onTap: () => ref.read(selectedBookProvider.notifier).select(null)),
              const Spacer(),
              const LibraryHeaderActions(),
            ],
          ),
          Expanded(
            child: Center(
              child: Text(
                AppLocalizations.of(context).shelfEmpty,
                style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
              ),
            ),
          ),
        ],
      );
    }
    final selected = ref.watch(selectedBookProvider);
    // 🔴 不兜底 `books.first`：进库未选中时应停在网格（由 LibraryScreen 决定），
    // 这里只在**确实选中**时渲染详情。
    final book = books.where((b) => b.key == selected).firstOrNull;
    if (book == null) {
      return const SizedBox.shrink();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      children: [
        // 「返回书架」（ver1.0 `#bk`）：清掉选中即回到默认态。
        Row(
          children: [
            _BackToShelf(onTap: () => ref.read(selectedBookProvider.notifier).select(null)),
            const Spacer(),
            const LibraryHeaderActions(),
          ],
        ),
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
                  style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
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
class LibraryHeaderActions extends ConsumerWidget {
  const LibraryHeaderActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      // 右侧留出边距：按钮不贴窗口边缘。
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
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
      ),
    );
  }
}

/// 头部动作（刷新 / 新建漫画）：统一走 [AppButton]。
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.label, this.primary = false, required this.onTap});

  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      icon: icon,
      onTap: onTap,
      variant: primary ? AppButtonVariant.primary : AppButtonVariant.ghost,
      border: !primary,
      height: 26,
      horizontalPadding: 10,
      fontSize: 10.5,
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    // ver1.0 `.detail-hero`：纯排版（无卡片底），封面 96×126。
    return Row(
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: palette.textPrimary),
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
                        final r = await _EditBookDialog.show(context, book: book);
                        if (r == null || !context.mounted) return;
                        final client = ref.read(mangaSvcClientProvider);
                        try {
                          // 封面与文字**同一次保存**（miao-dock：拆开会有半落盘状态）。
                          switch (r.cover) {
                            case CoverIntent.keep:
                              break;
                            case CoverIntent.first:
                              await client.setBookCoverFromFirstChapter(book.key);
                            case CoverIntent.remove:
                              await client.deleteBookCover(book.key);
                            case CoverIntent.local:
                              await client.setBookCover(
                                book.key,
                                bytes: r.coverBytes!,
                                filename: r.coverFileName ?? 'cover.png',
                              );
                          }
                          await client.setBookMeta(book.key, r.meta);
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
                              ReaderSession(key: book.key, pages: book.directPages, translated: book.directTranslated),
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
                    label: l10n.actionOpenDir,
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
    final palette = AppPalette.of(context);
    final book = widget.book;
    return Container(
      width: 96,
      height: 112,
      decoration: BoxDecoration(color: palette.cardCover, borderRadius: BorderRadius.circular(8)),
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
              color: palette.textSecondary,
            );
          }
          return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover, width: 96, height: 112);
        },
      ),
    );
  }
}

/// Hero 动作（继续翻译 / 编辑信息 / 归并 / 打开目录）：统一走 [AppButton]。
class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.icon, required this.label, this.primary = false, required this.onTap});

  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      icon: icon,
      onTap: onTap,
      variant: primary ? AppButtonVariant.primary : AppButtonVariant.ghost,
      border: !primary,
      height: 26,
      horizontalPadding: 10,
      fontSize: 12.5,
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: palette.navBg, borderRadius: BorderRadius.circular(5)),
      child: Text(text, style: TextStyle(fontSize: 11.5, color: palette.textSecondary)),
    );
  }
}

/// 单话的「页面」区头：标题 + 页数 + 图例 + 卡片/简易切换（与章节区同一套控件）。
class _PageSectionHeader extends ConsumerWidget {
  const _PageSectionHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(libModeProvider);
    return Row(
      children: [
        Text(
          l10n.readerPagesTitle,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.textPrimary),
        ),
        const SizedBox(width: 10),
        if (mode == 'capsule')
          Text(l10n.libCapsuleLegend, style: TextStyle(fontSize: 9.5, color: palette.textSecondary)),
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
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(libModeProvider);
    return Row(
      children: [
        Text(
          l10n.bookChapters,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.textPrimary),
        ),
        const SizedBox(width: 8),
        Text(l10n.bookChapterCount(book.chapterCount), style: TextStyle(fontSize: 12, color: palette.textSecondary)),
        const SizedBox(width: 10),
        if (mode == 'capsule')
          Text(l10n.libCapsuleLegend, style: TextStyle(fontSize: 9.5, color: palette.textSecondary)),
        const Spacer(),
        _ViewSeg(mode: mode, onSelect: (m) => ref.read(libModeProvider.notifier).set(m)),
      ],
    );
  }
}

/// 单话「页面」区（卡片态）：每页一格，点开阅读器定位到该页。
class _PageGrid extends StatelessWidget {
  const _PageGrid({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context) {
    final total = book.directPages;
    // 与「漫画库右侧的单本卡片」同一套网格参数（maxExtent 170 / 比例 0.62）。
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.62,
      ),
      itemCount: total,
      itemBuilder: (context, i) => _PageCard(book: book, seq: i + 1, total: total),
    );
  }
}

/// 单页卡片：**以该页原图作封面**，左上角页码胶囊（与单本卡片的「N 话」同位）。
class _PageCard extends ConsumerStatefulWidget {
  const _PageCard({required this.book, required this.seq, required this.total});

  final LibBook book;
  final int seq;
  final int total;

  @override
  ConsumerState<_PageCard> createState() => _PageCardState();
}

class _PageCardState extends ConsumerState<_PageCard> {
  bool _hover = false;
  Future<List<int>?>? _image;

  @override
  void initState() {
    super.initState();
    // 原图取封面（不带 variant），缺图时回退占位图标。
    _image = ref
        .read(mangaSvcClientProvider)
        .getBookFile(widget.book.key, widget.seq)
        .then<List<int>?>((v) => v)
        .catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final seq = widget.seq;
    final done = widget.book.directTranslated.contains(seq);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () {
          ref
              .read(readerSessionProvider.notifier)
              .open(ReaderSession(key: widget.book.key, pages: widget.total, translated: widget.book.directTranslated));
          context.go('/manga/reader');
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _hover ? palette.accent : Colors.transparent),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [palette.accent, palette.coverEndDeep],
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FutureBuilder<List<int>?>(
                      future: _image,
                      builder: (context, snap) {
                        final bytes = snap.data;
                        if (bytes == null || bytes.isEmpty) {
                          return Center(child: Icon(LucideIcons.fileImage, size: 18, color: palette.textSecondary));
                        }
                        return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover);
                      },
                    ),
                    // 页码胶囊在**左上角**（与单本卡片的「N 话」同位）。
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(kPillRadius),
                        ),
                        child: Text('$seq', style: const TextStyle(fontSize: 9, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              AppLocalizations.of(context).readerPage(seq, widget.total),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: palette.textPrimary),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: done ? palette.success : palette.accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  done
                      ? AppLocalizations.of(context).libChapterStatusDone
                      : AppLocalizations.of(context).libChapterStatusPending,
                  style: TextStyle(fontSize: 9, color: palette.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单话「页面」区（简易态）：页码胶囊 + 状态圆点。
class _PageCapsules extends StatelessWidget {
  const _PageCapsules({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var seq = 1; seq <= book.directPages; seq++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$seq', style: TextStyle(fontSize: 11.5, color: palette.textPrimary)),
                if (!book.directTranslated.contains(seq)) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: palette.accent, shape: BoxShape.circle),
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
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 100,
      ),
      itemCount: book.chapters.length,
      itemBuilder: (context, i) => _ChapterCard(book: book, chapter: book.chapters[i]),
    );
  }
}

class _ChapterCard extends ConsumerStatefulWidget {
  const _ChapterCard({required this.book, required this.chapter});

  final LibBook book;
  final LibChapter chapter;

  @override
  ConsumerState<_ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends ConsumerState<_ChapterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final book = widget.book;
    final chapter = widget.chapter;
    final color = chapter.done ? MangaTaskStatus.done.color : MangaTaskStatus.translating.color;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
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
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _hover ? palette.accent : Colors.transparent),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 64,
                    decoration: BoxDecoration(color: palette.cardCover, borderRadius: BorderRadius.circular(6)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context).chapterTitle(jsNumStr(chapter.no)),
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: palette.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          AppLocalizations.of(context).chapterMeta(chapter.pageCount, chapter.donePages),
                          style: TextStyle(fontSize: 8.5, color: palette.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            height: 4,
                            child: LinearProgressIndicator(
                              value: chapter.ratio,
                              backgroundColor: palette.progressTrack,
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
            // 悬浮菜单：点它不能顺带打开阅读器（miao-dock：stopPropagation）。
            Positioned(
              right: 0,
              top: 0,
              child: ChapterMenuButton(book: book, chapter: chapter),
            ),
          ],
        ),
      ),
    );
  }
}

/// 简易（胶囊）态：名字 + 状态圆点（待译 蓝 · 缺页 黄 · 已译完不显示）。
class _ChapterCapsules extends ConsumerWidget {
  const _ChapterCapsules({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in book.chapters)
          _Capsule(
            label: l10n.chapterTitle(jsNumStr(c.no)),
            pending: !c.done,
            pendingColor: c.translatedSeqs.isEmpty
                ? MangaTaskStatus.translating.color
                : MangaTaskStatus.partialFailed.color,
            onTap: () {
              // 简易态与卡片态**同样能点开阅读器**（此前胶囊不可点，是缺陷）。
              ref
                  .read(readerSessionProvider.notifier)
                  .open(
                    ReaderSession(key: book.key, chapterNo: c.no, pages: c.pageCount, translated: c.translatedSeqs),
                  );
              context.go('/manga/reader');
            },
          ),
      ],
    );
  }
}

/// 单个胶囊（ver1.0 `.chapcap`：92×32、999 圆角、panel 底、hover 描边变主色）。
class _Capsule extends StatefulWidget {
  const _Capsule({required this.label, required this.onTap, this.pending = false, this.pendingColor});

  final String label;
  final VoidCallback onTap;
  final bool pending;
  final Color? pendingColor;

  @override
  State<_Capsule> createState() => _CapsuleState();
}

class _CapsuleState extends State<_Capsule> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: palette.navBg,
            borderRadius: BorderRadius.circular(kPillRadius),
            border: Border.all(color: _hover ? palette.accent : palette.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.label, style: TextStyle(fontSize: 11, color: palette.textMuted)),
              if (widget.pending) ...[
                const SizedBox(width: 6),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: widget.pendingColor, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: palette.card,
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

class _EditBookDialog extends ConsumerStatefulWidget {
  const _EditBookDialog({required this.book});

  final LibBook book;

  static Future<EditBookResult?> show(BuildContext context, {required LibBook book}) => showDialog<EditBookResult>(
    context: context,
    builder: (_) => _EditBookDialog(book: book),
  );

  @override
  ConsumerState<_EditBookDialog> createState() => _EditBookDialogState();
}

/// 封面意图（miao-dock `CoverSource`）：保留 / 本地图片 / 第 1 话首图 / 移除。
enum CoverIntent { keep, local, first, remove }

/// 编辑结果：文字与封面**一次提交**。
class EditBookResult {
  const EditBookResult({required this.meta, required this.cover, this.coverBytes, this.coverFileName});

  final BookMeta meta;
  final CoverIntent cover;
  final Uint8List? coverBytes;
  final String? coverFileName;
}

class _EditBookDialogState extends ConsumerState<_EditBookDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.book.name);
  late final TextEditingController _author = TextEditingController(text: widget.book.author);
  CoverIntent _cover = CoverIntent.keep;
  Uint8List? _bytes;
  String? _fileName;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _pickLocal() async {
    const typeGroup = XTypeGroup(label: 'image', extensions: ['png', 'jpg', 'jpeg', 'webp']);
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _bytes = bytes;
      _fileName = file.name;
      _cover = CoverIntent.local;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final hasCover = widget.book.hasCover;
    return Dialog(
      backgroundColor: palette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.libEditInfoTitle,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.textPrimary),
            ),
            const SizedBox(height: 14),
            // 封面区（ver1.0 `.cover-box`：预览 96×128 在左，操作竖排在右）
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 96,
                  height: 128,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: palette.cardCover,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: palette.divider),
                  ),
                  child: _preview(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CoverChoice(
                        icon: LucideIcons.imagePlus,
                        label: l10n.libCoverPickLocal,
                        active: _cover == CoverIntent.local,
                        onTap: _pickLocal,
                      ),
                      const SizedBox(height: 6),
                      _CoverChoice(
                        icon: LucideIcons.fileImage,
                        label: l10n.libCoverFromFirst,
                        active: _cover == CoverIntent.first,
                        enabled: widget.book.isBook ? widget.book.chapters.isNotEmpty : widget.book.directPages > 0,
                        onTap: () => setState(() => _cover = CoverIntent.first),
                      ),
                      const SizedBox(height: 6),
                      _CoverChoice(
                        icon: LucideIcons.trash2,
                        label: l10n.libCoverRemove,
                        active: _cover == CoverIntent.remove,
                        enabled: hasCover || _cover == CoverIntent.local || _cover == CoverIntent.first,
                        onTap: () => setState(() {
                          _cover = CoverIntent.remove;
                          _bytes = null;
                        }),
                      ),
                      if (_cover == CoverIntent.local) ...[
                        const SizedBox(height: 8),
                        Text(
                          _fileName == null ? l10n.libCoverPickHint : l10n.libCoverPicked(_fileName!),
                          style: TextStyle(fontSize: 10.5, color: palette.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 文字信息
            Text(l10n.libCreateBookNameHint, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
            const SizedBox(height: 5),
            _DialogField(controller: _title),
            const SizedBox(height: 12),
            Text(l10n.bookAuthorLabel(''), style: TextStyle(fontSize: 11, color: palette.textSecondary)),
            const SizedBox(height: 5),
            _DialogField(controller: _author),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _DialogButton(label: l10n.actionCancel, onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 8),
                _DialogButton(
                  label: l10n.libEditInfoOk,
                  primary: true,
                  enabled: !(_cover == CoverIntent.local && _bytes == null),
                  onTap: () => Navigator.of(context).pop(
                    EditBookResult(
                      meta: BookMeta(
                        title: _title.text.trim().isEmpty ? widget.book.name : _title.text.trim(),
                        author: _author.text.trim(),
                      ),
                      cover: _cover,
                      coverBytes: _bytes,
                      coverFileName: _fileName,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 封面预览（ver1.0 `.cover-preview`）：本地图即时预览；无封面显示占位。
  Widget _preview() {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    if (_cover == CoverIntent.remove) {
      return Center(
        child: Text(l10n.libCoverNone, style: TextStyle(fontSize: 10.5, color: palette.textSecondary)),
      );
    }
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: BoxFit.cover);
    }
    return FutureBuilder<List<int>?>(
      future: ref.read(mangaSvcClientProvider).getBookCover(widget.book.key),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return Center(
            child: Text(l10n.libCoverNone, style: TextStyle(fontSize: 10.5, color: palette.textSecondary)),
          );
        }
        return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover);
      },
    );
  }
}

/// 弹窗内输入框（统一 8 圆角、深底、无下划线）。
class _DialogField extends StatelessWidget {
  const _DialogField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      height: 32,
      child: TextField(
        controller: controller,
        style: TextStyle(fontSize: 12, color: palette.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: palette.navBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: palette.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: palette.accent),
          ),
        ),
      ),
    );
  }
}

/// 弹窗按钮：统一走 [AppButton]。
class _DialogButton extends StatelessWidget {
  const _DialogButton({required this.label, required this.onTap, this.primary = false, this.enabled = true});

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onTap: enabled ? onTap : null,
      clickable: enabled,
      variant: primary ? AppButtonVariant.primary : AppButtonVariant.ghost,
      border: !primary,
      height: 26,
      horizontalPadding: 12,
      fontSize: 10.5,
    );
  }
}

/// 封面选择（本地图片 / 取首图 / 移除）：统一走 [AppButton]，选中态用 primary。
class _CoverChoice extends StatelessWidget {
  const _CoverChoice({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      icon: icon,
      onTap: enabled ? onTap : null,
      clickable: enabled,
      variant: active ? AppButtonVariant.primary : AppButtonVariant.secondary,
      height: 26,
      horizontalPadding: 8,
      fontSize: 10.5,
    );
  }
}

class _ViewSeg extends StatelessWidget {
  const _ViewSeg({required this.mode, required this.onSelect});

  final String mode;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: palette.navBg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          for (final m in const ['card', 'capsule'])
            _HoverTap(
              onTap: () => onSelect(m),
              builder: (hover) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: mode == m ? palette.card : (hover ? palette.card.withValues(alpha: 0.5) : Colors.transparent),
                  borderRadius: BorderRadius.circular(kButtonRadius),
                ),
                child: Text(
                  m == 'card' ? l10n.libViewCard : l10n.libViewCapsule,
                  style: TextStyle(fontSize: 10.5, color: mode == m ? palette.textPrimary : palette.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 「返回书架」：统一走 [AppButton]。
class _BackToShelf extends StatelessWidget {
  const _BackToShelf({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: AppLocalizations.of(context).shelfBack,
      icon: LucideIcons.chevronLeft,
      onTap: onTap,
      variant: AppButtonVariant.ghost,
      border: true,
      height: 26,
      horizontalPadding: 10,
      fontSize: 10.5,
    );
  }
}

class _HoverTap extends StatefulWidget {
  const _HoverTap({required this.onTap, required this.builder});

  final VoidCallback onTap;
  final Widget Function(bool hover) builder;

  @override
  State<_HoverTap> createState() => _HoverTapState();
}

class _HoverTapState extends State<_HoverTap> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: widget.builder(_hover)),
    );
  }
}
