import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:protocol/protocol.dart' show BookMeta, jsNumStr;

import '../../../core/theme/tokens.dart';
import '../../../shared/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/toast.dart';
import '../controller/library_controller.dart';
import '../controller/queue_controller.dart';
import '../controller/remote_guard.dart';
import '../domain/lib_book.dart';
import 'library_search_results.dart';
import 'chapter_menu.dart';
import 'shelf_menu.dart';

/// 详情主区（设计稿 `.lib-main`）：工具栏（标题 + 章节）+ 可滚动区
/// （Hero → 章节区 / 页面区）。
///
/// 宽屏：书架常驻左侧，点行只换这里的 book，**没有「返回书架」**；
/// 窄屏：整屏从右侧滑入（`.mdetail`），头部是「‹ + 标题 + 刷新 + 视图切换」。
class LibraryDetail extends ConsumerWidget {
  const LibraryDetail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final query = ref.watch(shelfQueryProvider).trim();
    // 桌面：搜索态接管右栏（设计稿 `renderSearch`）。
    if (query.isNotEmpty && !context.isMobile) {
      return LibrarySearchResults(query: query);
    }
    final state = ref.watch(libraryProvider);
    final books = state.value ?? ref.read(libraryProvider.notifier).lastGood;

    if (books.isEmpty && state.hasError) {
      return ErrorState(error: state.error, onRetry: () => ref.read(libraryProvider.notifier).refresh());
    }
    if (books.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).shelfEmpty,
          style: TextStyle(fontSize: AppFont.px12_5, color: palette.textSecondary),
        ),
      );
    }

    final selected = ref.watch(selectedBookProvider);
    final book = books.where((b) => b.key == selected).firstOrNull;
    if (book == null) {
      // 未选中（书架空态 / 手动取消）：右栏给一句引导，不留白屏。
      return Center(
        child: Text(
          AppLocalizations.of(context).libPickBookHint,
          style: TextStyle(fontSize: AppFont.px12, color: palette.mut),
        ),
      );
    }
    return context.isMobile ? _MobileDetail(book: book) : _DesktopDetail(book: book);
  }
}

/// 桌面详情：`.lib-toolbar`（标题 + `章节`）+ `.lib-scroll`（Hero → 章节 / 页面）。
class _DesktopDetail extends ConsumerWidget {
  const _DesktopDetail({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(libModeProvider);
    final openNo = ref.watch(libChapterOpenProvider);
    // 设计稿 `showSingles()`：脚注入口 → 未归并单话陈列页（选中即退出）。
    if (ref.watch(libSinglesViewProvider)) {
      return const _SinglesPage();
    }
    final chapter = openNo == null ? null : book.chapters.where((c) => c.no == openNo).firstOrNull;

    // `.lib-toolbar`：详情 = 标题 + `章节`；页网格 = `‹` + `第 N 话` + 计数 + 动作。
    final toolbar = chapter == null
        ? _LibToolbar(
            title: book.name,
            trailing: [
              AppButton(
                label: AppLocalizations.of(context).bookChapters,
                // 设计稿 `openChapter(-2)`：回到章节列表（从页网格返回的兜底入口）。
                onTap: () => ref.read(libChapterOpenProvider.notifier).open(null),
                variant: AppButtonVariant.ghost,
                height: 26,
                horizontalPadding: 10,
                fontSize: AppFont.px11,
              ),
            ],
          )
        : _ChapterPageToolbar(book: book, chapter: chapter);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        Expanded(
          child: chapter != null
              ? _ChapterPageView(book: book, chapter: chapter)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  children: [
                    _Hero(book: book),
                    if (book.isBook) ...[
                      const SizedBox(height: 2),
                      _SectionHeader(book: book),
                      const SizedBox(height: 10),
                      if (book.chapters.isEmpty)
                        _EmptyHint(text: AppLocalizations.of(context).shelfEmpty)
                      else
                        mode == 'capsule' ? _ChapterCapsules(book: book) : _ChapterGrid(book: book),
                    ] else ...[
                      const SizedBox(height: 16),
                      _PageSectionHeader(),
                      const SizedBox(height: 10),
                      mode == 'capsule' ? _PageCapsules(book: book) : _PageGrid(book: book),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// 页网格工具栏（设计稿 `renderPages`）：`‹` + `第 N 话` + `N / N 页` tag
/// + `续做本话`（有待译才显示）+ `重译本话`（有已译才显示）。
class _ChapterPageToolbar extends ConsumerWidget {
  const _ChapterPageToolbar({required this.book, required this.chapter});

  final LibBook book;
  final LibChapter chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final pending = chapter.pageCount - chapter.donePages;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          _IconAction(icon: LucideIcons.chevronLeft, onTap: () => ref.read(libChapterOpenProvider.notifier).open(null)),
          const SizedBox(width: 8),
          Text(
            l10n.chapterTitle(jsNumStr(chapter.no)),
            style: TextStyle(fontSize: AppFont.px14, fontWeight: FontWeight.w700, color: palette.ink),
          ),
          const SizedBox(width: 8),
          _Tag(text: l10n.chapterProgress(chapter.donePages, chapter.pageCount)),
          const Spacer(),
          if (pending > 0) ...[
            AppButton(
              label: l10n.libResumeChapter,
              onTap: () => _resumeChapter(context, ref, book, chapter),
              variant: AppButtonVariant.primary,
              height: 26,
              horizontalPadding: 10,
              fontSize: AppFont.px11,
            ),
            const SizedBox(width: 8),
          ],
          if (chapter.donePages > 0)
            AppButton(
              label: l10n.libRetranslateChapter,
              onTap: () => _retranslateChapter(context, ref, book, chapter),
              variant: AppButtonVariant.ghost,
              height: 26,
              horizontalPadding: 10,
              fontSize: AppFont.px11,
            ),
        ],
      ),
    );
  }
}

Future<void> _resumeChapter(BuildContext context, WidgetRef ref, LibBook book, LibChapter chapter) async {
  final l10n = AppLocalizations.of(context);
  final guard = await ref.remoteGuard(l10n);
  if (guard != null) {
    if (context.mounted) showAppToast(context, guard, tone: ToastTone.bad);
    return;
  }
  try {
    await ref.read(mangaSvcClientProvider).resumeChapter(book.key, chapter.no);
    if (context.mounted) showAppToast(context, l10n.chapterResumeOk(book.name), tone: ToastTone.good);
  } catch (e) {
    if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
  }
}

Future<void> _retranslateChapter(BuildContext context, WidgetRef ref, LibBook book, LibChapter chapter) async {
  final l10n = AppLocalizations.of(context);
  final guard = await ref.remoteGuard(l10n);
  if (guard != null) {
    if (context.mounted) showAppToast(context, guard, tone: ToastTone.bad);
    return;
  }
  try {
    await ref.read(mangaSvcClientProvider).retranslateChapter(book.key, chapter.no);
    if (context.mounted) showAppToast(context, l10n.chapterRetranslateOk(book.name), tone: ToastTone.good);
  } catch (e) {
    if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
  }
}

/// 页网格（设计稿 `renderPages`）：minmax(104) / gap 10，底部脚注。
class _ChapterPageView extends StatelessWidget {
  const _ChapterPageView({required this.book, required this.chapter});

  final LibBook book;
  final LibChapter chapter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        _PageCells(book: book, chapter: chapter),
        const SizedBox(height: 12),
        _FootHint(text: l10n.libPageFootHint(chapter.pageCount)),
      ],
    );
  }
}

/// 桌面「未归并单话」陈列页（设计稿 `renderSingles`）：
/// 每行 = 34×46 虚线橙封面 + 名 + 进度说明 + `待归并` 徽标 + `归并` / `阅读`。
class _SinglesPage extends ConsumerWidget {
  const _SinglesPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final singles = ref.watch(libraryProvider).value?.where((b) => !b.isBook).toList() ?? const <LibBook>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Text(
                l10n.libUnmergedSingles,
                style: TextStyle(fontSize: AppFont.px14, fontWeight: FontWeight.w700, color: palette.ink),
              ),
              const SizedBox(width: 8),
              _Tag(text: '${singles.length}', tone: _TagTone.warn),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.libUnmergedSinglesHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            children: [
              for (final s in singles)
                _SingleRow(
                  single: s,
                  onTap: () {
                    // 选中即退出陈列页（设计稿 openSingleDetail 置 singlesView=false）。
                    ref.read(libSinglesViewProvider.notifier).close();
                    ref.read(selectedBookProvider.notifier).select(s.key);
                  },
                ),
              const SizedBox(height: 12),
              _FootHint(text: l10n.libSinglesFootHint),
            ],
          ),
        ),
      ],
    );
  }
}

class _SingleRow extends ConsumerWidget {
  const _SingleRow({required this.single, required this.onTap});

  final LibBook single;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          // 34×46 虚线橙封面（第 1 页）。
          Container(
            width: 34,
            height: 46,
            decoration: BoxDecoration(
              color: palette.cardCover,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: palette.accent.withValues(alpha: 0.55), width: 1.5),
            ),
            alignment: Alignment.center,
            child: Icon(LucideIcons.fileText, size: 14, color: palette.ink2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  single.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w600, color: palette.ink),
                ),
                Text(
                  l10n.libSingleNote(single.pageCount, single.directTranslated.length, single.pageCount),
                  style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Tag(text: l10n.libPendingMerge, tone: _TagTone.warn),
          const SizedBox(width: 8),
          AppButton(
            label: l10n.libMerge,
            onTap: () => _mergeBook(context, ref, single),
            variant: AppButtonVariant.ghost,
            height: 26,
            horizontalPadding: 10,
            fontSize: AppFont.px11,
          ),
          const SizedBox(width: 6),
          AppButton(
            label: l10n.libRead,
            onTap: () => _openReader(context, ref, single),
            variant: AppButtonVariant.ghost,
            height: 26,
            horizontalPadding: 10,
            fontSize: AppFont.px11,
          ),
        ],
      ),
    );
  }
}

/// 窄屏详情（设计稿 `.mdetail`）：整屏从右侧滑入（380ms `c-morph` 曲线），
/// 头部 = `‹` + 标题 + 刷新 + `卡片/简易` 切换；正文 = Hero 摘要 + 章节 / 页面区。
///
/// 卡片/简易是**跨详情保持**的全局状态（设计稿 `mDetailMode` 不在关闭时重置）。
class _MobileDetail extends ConsumerStatefulWidget {
  const _MobileDetail({required this.book});

  final LibBook book;

  @override
  ConsumerState<_MobileDetail> createState() => _MobileDetailState();
}

class _MobileDetailState extends ConsumerState<_MobileDetail> {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final book = widget.book;
    final mode = ref.watch(libModeProvider);

    return TweenAnimationBuilder<double>(
      key: ValueKey('mdetail-${book.key}'),
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => FractionalTranslation(translation: Offset(value, 0), child: child),
      child: ColoredBox(
        color: palette.bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // `.mdetail .mh`：10/12 内距、底部 `line` 分隔。
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.line)),
              ),
              child: Row(
                children: [
                  _IconAction(
                    icon: LucideIcons.chevronLeft,
                    onTap: () => ref.read(selectedBookProvider.notifier).select(null),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      book.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                  ),
                  _IconAction(icon: LucideIcons.refreshCw, onTap: () => _refresh(context, ref)),
                  const SizedBox(width: 8),
                  _ViewSeg(mode: mode, onSelect: (m) => ref.read(libModeProvider.notifier).set(m)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _MobileHero(book: book),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        book.isBook
                            ? (mode == 'capsule' ? l10n.libChaptersSimple : l10n.bookChapters)
                            : (mode == 'capsule' ? l10n.libPagesSimple : l10n.readerPagesTitle),
                        style: TextStyle(
                          fontSize: AppFont.px10_5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: palette.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (book.isBook)
                    // 卡片模式与桌面同一套 `_ChapterCard`（用户口径：窄屏话卡样式跟桌面一致），
                    // 只是格子更宽、窄屏两列。
                    mode == 'capsule' ? _ChapterCapsules(book: book) : _ChapterGrid(book: book)
                  else
                    mode == 'capsule' ? _PageCapsules(book: book) : _MobilePageGrid(book: book),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.mdetail` Hero 摘要：单本 = 92 宽封面 + 标题 / 作者 / tag + `继续翻译` `阅读`；
/// 单话 = 84 宽封面 + 标题 / 未归并说明 + `归并` `阅读`。
class _MobileHero extends ConsumerWidget {
  const _MobileHero({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final coverWidth = book.isBook ? 92.0 : 84.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: coverWidth,
          child: AspectRatio(
            aspectRatio: 3 / 4.1,
            child: _Cover(book: book),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w800, color: palette.ink),
              ),
              const SizedBox(height: 4),
              Text(
                book.isBook
                    ? l10n.shelfBookMeta(
                        book.hasAuthor ? book.author : l10n.bookUnnamedAuthor,
                        book.chapterCount,
                        book.pageCount,
                      )
                    : l10n.libSingleMobileNote(book.pageCount),
                style: TextStyle(fontSize: AppFont.px10_5, height: 1.7, color: palette.mut),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (book.isBook) ...[
                    _Tag(
                      text: l10n.libTranslatedPercent(_translatedPercent(book)),
                      tone: _translatedPercent(book) >= 100 ? _TagTone.good : _TagTone.normal,
                    ),
                    _Tag(text: l10n.libOnShelf),
                  ] else
                    _Tag(text: l10n.libUnmergedTag, tone: _TagTone.warn),
                ],
              ),
              const SizedBox(height: 8),
              // `.actions .btn{flex:1}`：两个按钮等分铺满。
              Row(
                children: [
                  if (book.isBook) ...[
                    Expanded(
                      child: _HeroButton(
                        label: l10n.bookContinueTranslate,
                        primary: true,
                        onTap: () => _resume(context, ref, book),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 头部已有刷新图标，这里让位给「阅读」（直达第一话第一页）。
                    if (book.chapters.isNotEmpty)
                      Expanded(
                        child: _HeroButton(label: l10n.libRead, onTap: () => _openBookReader(context, ref, book)),
                      ),
                  ] else ...[
                    Expanded(
                      child: _HeroButton(
                        label: l10n.libMerge,
                        primary: true,
                        onTap: () => _mergeBook(context, ref, book),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroButton(label: l10n.libRead, onTap: () => _openReader(context, ref, book)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 窄屏页网格：minmax(88,1fr) / gap 10。
class _MobilePageGrid extends StatelessWidget {
  const _MobilePageGrid({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 3 / 4,
      ),
      itemCount: book.directPages,
      itemBuilder: (context, i) => _PageCard(book: book, seq: i + 1),
    );
  }
}

/// `.mdetail .mh` 里的图标按钮（`ibtn`：34×34 / 8 圆角 / hover 变 hi）。
class _IconAction extends StatefulWidget {
  const _IconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<_IconAction> {
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
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hover ? palette.hi : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(widget.icon, size: 17, color: palette.ink2),
        ),
      ),
    );
  }
}

/// `.lib-toolbar`：12/20/8 内距、gap 8；标题 15 号 700，右侧 `章节` 小 ghost。
class _LibToolbar extends StatelessWidget {
  const _LibToolbar({required this.title, this.trailing = const []});

  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w700, color: palette.ink),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

/// 漫画库视图级动作（设计稿 `.apptool` 右端 / 移动 `.vtabs .acts`）：
/// 桌面 = ghost「新建漫画」，移动 = 纯加号图标。由壳层按当前视图注入顶栏。
class LibraryHeaderActions extends ConsumerWidget {
  const LibraryHeaderActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    Future<void> createOnTap() async {
      final name = await _CreateBookDialog.show(context);
      if (name == null || !context.mounted) return;
      try {
        await ref.read(mangaSvcClientProvider).createBook(name);
        await ref.read(libraryProvider.notifier).refresh();
        // 设计稿「创建成功后关弹窗 + 清搜索 + 选中」：清搜索避免新书被旧关键词过滤掉。
        ref.read(shelfQueryProvider.notifier).set('');
        ref.read(selectedBookProvider.notifier).select(name);
        if (context.mounted) showAppToast(context, l10n.libCreateBookOk(name), tone: ToastTone.good);
      } catch (e) {
        if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
      }
    }

    if (context.isMobile) {
      return Tooltip(
        message: l10n.libCreateBook,
        child: AppButton(
          icon: LucideIcons.plus,
          onTap: createOnTap,
          variant: AppButtonVariant.ghost,
          border: false,
          width: 30,
          height: 30,
          fontSize: AppFont.px14,
        ),
      );
    }
    return _HeaderAction(icon: LucideIcons.folderPlus, label: l10n.libCreateBook, onTap: createOnTap);
  }
}

/// 头部动作（新建漫画）：统一走 [AppButton] 的 ghost 变体（设计稿 `.btn.ghost.sm`）。
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      icon: icon,
      onTap: onTap,
      variant: AppButtonVariant.ghost,
      height: 26,
      horizontalPadding: 10,
      fontSize: AppFont.px10_5,
    );
  }
}

/// `.bhero`：8/0/14 内距、gap 18；封面 clamp(96..118) × 3:4.1（含书脊竖排 4 字）
/// + `.kicker`（9 号 2px 字距）→ 17px/800 标题 → 作者 → tag 胶囊行 → 路径 → 动作。
class _Hero extends ConsumerWidget {
  const _Hero({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final translated = _translatedPercent(book);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Cover(book: book),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.isBook ? 'BOOK / ${book.name.toUpperCase()}' : l10n.libSingleKicker,
                  style: TextStyle(
                    fontSize: AppFont.px9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: palette.mut,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  book.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFont.px17, fontWeight: FontWeight.w800, color: palette.ink),
                ),
                Text(
                  book.isBook
                      ? '${book.hasAuthor ? book.author : l10n.bookUnnamedAuthor} · ${l10n.libUpdatedRecently}'
                      : l10n.libSingleNote(book.pageCount, book.directTranslated.length, book.pageCount),
                  style: TextStyle(fontSize: AppFont.px11, color: palette.ink2),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (book.isBook) ...[
                      _Tag(text: l10n.bookChapterCount(book.chapterCount)),
                      _Tag(text: l10n.bookPageCount(book.pageCount)),
                      _Tag(
                        text: l10n.libTranslatedPercent(translated),
                        tone: translated >= 100 ? _TagTone.good : _TagTone.normal,
                      ),
                      _Tag(text: l10n.libOnShelf),
                    ] else
                      _Tag(text: l10n.libUnmergedTag, tone: _TagTone.warn),
                  ],
                ),
                const SizedBox(height: 8),
                if (book.isBook)
                  Text(
                    _bookPath(book.key),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut, fontFamily: 'monospace'),
                  ),
                const SizedBox(height: 10),
                _HeroActions(book: book),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero 动作：`继续翻译`（32 高主按钮）+ `编辑信息` / `刷新`；
/// 单话：`归并`（主）+ `阅读` + `打开目录`（设计稿 `.bactions`）。
class _HeroActions extends ConsumerWidget {
  const _HeroActions({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (!book.isBook) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _HeroButton(label: l10n.libMerge, primary: true, onTap: () => _mergeBook(context, ref, book)),
          _HeroButton(label: l10n.libRead, onTap: () => _openReader(context, ref, book)),
          if (!context.isMobile) _HeroButton(label: l10n.actionOpenDir, onTap: () => _reveal(context, ref, book)),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _HeroButton(label: l10n.bookContinueTranslate, primary: true, onTap: () => _resume(context, ref, book)),
        // 单本「阅读」直达第一话第一页（用户裁定：不做续读）。
        if (book.chapters.isNotEmpty)
          _HeroButton(label: l10n.libRead, onTap: () => _openBookReader(context, ref, book)),
        _HeroButton(label: l10n.libEditInfo, onTap: () => _edit(context, ref, book)),
        _HeroButton(label: l10n.libRefresh, onTap: () => _refresh(context, ref)),
        // 打开目录 = 桌面端 reveal；移动端不显示（目录在桌面机器上）。
        if (!context.isMobile) _HeroButton(label: l10n.actionOpenDir, onTap: () => _reveal(context, ref, book)),
      ],
    );
  }
}

String _bookPath(String key) => 'D:\\MiaoDock\\Mangas\\$key';

int _translatedPercent(LibBook book) {
  if (book.pageCount == 0) return 0;
  final done = book.isBook ? book.chapters.fold<int>(0, (s, c) => s + c.donePages) : book.directTranslated.length;
  return (done / book.pageCount * 100).round();
}

Future<void> _refresh(BuildContext context, WidgetRef ref) async {
  await ref.read(libraryProvider.notifier).refresh();
}

Future<void> _resume(BuildContext context, WidgetRef ref, LibBook book) async {
  final l10n = AppLocalizations.of(context);
  final client = ref.read(mangaSvcClientProvider);
  try {
    final plan = await client.getResumePlan(book.key);
    if (plan.pendingCount == 0) {
      if (context.mounted) showAppToast(context, l10n.libAllTranslated, tone: ToastTone.info);
      return;
    }
    final guardRes = await ref.remoteGuard(l10n);
    if (guardRes != null) {
      if (context.mounted) showAppToast(context, guardRes, tone: ToastTone.bad);
      return;
    }
    await client.resumeBook(book.key);
    if (context.mounted) showAppToast(context, l10n.libResumeSubmitted, tone: ToastTone.good);
  } catch (e) {
    if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
  }
}

Future<void> _reveal(BuildContext context, WidgetRef ref, LibBook book) async {
  final l10n = AppLocalizations.of(context);
  await ref.read(mangaSvcClientProvider).revealBook(book.key);
  if (context.mounted) showAppToast(context, l10n.libRevealDone, tone: ToastTone.info);
}

/// 单话「阅读」：无话层（`chapterNo` 留空），从第一页开始。
void _openReader(BuildContext context, WidgetRef ref, LibBook book) {
  ref
      .read(readerSessionProvider.notifier)
      .open(ReaderSession(key: book.key, pages: book.directPages, translated: book.directTranslated));
  context.go('/manga/reader');
}

/// 单本「阅读」：直接进**第一话第一页**，不做续读、不恢复上次页内位置。
/// 话号取最小可用话（列表本身按目录名排序，这里再兜一次，避免脏数据）。
void _openBookReader(BuildContext context, WidgetRef ref, LibBook book) {
  final chapters = [...book.chapters]..sort((a, b) => a.no.compareTo(b.no));
  if (chapters.isEmpty) return;
  final first = chapters.first;
  ref
      .read(readerSessionProvider.notifier)
      .open(
        ReaderSession(key: book.key, chapterNo: first.no, pages: first.pageCount, translated: first.translatedSeqs),
      );
  context.go('/manga/reader');
}

Future<void> _mergeBook(BuildContext context, WidgetRef ref, LibBook book) async {
  final l10n = AppLocalizations.of(context);
  final result = await showMergeDialog(context, src: book.key);
  if (result == null || !context.mounted) return;
  try {
    await ref.read(mangaSvcClientProvider).mergeChapter(book.key, targetBook: result.$1, no: result.$2);
    await ref.read(libraryProvider.notifier).refresh();
    if (context.mounted) showAppToast(context, l10n.libMergeOk, tone: ToastTone.good);
  } catch (e) {
    if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
  }
}

Future<void> _edit(BuildContext context, WidgetRef ref, LibBook book) async {
  final l10n = AppLocalizations.of(context);
  final r = await _EditBookDialog.show(context, book: book);
  if (r == null || !context.mounted) return;
  final client = ref.read(mangaSvcClientProvider);
  try {
    // 封面与文字**同一次保存**（拆开会有半落盘状态）。
    switch (r.cover) {
      case CoverIntent.keep:
        break;
      case CoverIntent.first:
        await client.setBookCoverFromFirstChapter(book.key);
      case CoverIntent.remove:
        await client.deleteBookCover(book.key);
      case CoverIntent.local:
        await client.setBookCover(book.key, bytes: r.coverBytes!, filename: r.coverFileName ?? 'cover.png');
    }
    await client.setBookMeta(book.key, r.meta);
    await ref.read(libraryProvider.notifier).refresh();
    if (context.mounted) showAppToast(context, l10n.libEditInfoOk, tone: ToastTone.good);
  } catch (e) {
    if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
  }
}

/// `.bcover`：clamp(96..118) 宽 / 3:4.1 / 12 圆角 / 投影；
/// 左侧 20 宽书脊（`rgba(10,12,15,.55)` + 竖排前 4 字 + 2px 字距）。
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
    final width = (MediaQuery.sizeOf(context).width * 0.1).clamp(96.0, 118.0);
    return Container(
      width: width,
      height: width * 4.1 / 3,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: palette.cardCover,
        boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 26, offset: const Offset(0, 8))],
        // 单话：封面用虚线橙框（与单本的实心封面区分）。
        border: book.isBook ? null : Border.all(color: palette.accent.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<List<int>?>(
            future: _future,
            builder: (context, snap) {
              final bytes = snap.data;
              if (bytes == null || bytes.isEmpty) {
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [palette.cardCover, palette.bg],
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      book.isBook ? LucideIcons.bookOpen : LucideIcons.fileText,
                      size: 24,
                      color: palette.ink2,
                    ),
                  ),
                );
              }
              return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover);
            },
          ),
          // `.obi`：书脊竖排书名前 4 字（设计稿写作 4 字）。
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 20,
              padding: const EdgeInsets.only(top: 8),
              alignment: Alignment.center,
              color: const Color(0x8C0A0C0F),
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  book.name.length > 4 ? book.name.substring(0, 4) : book.name,
                  maxLines: 1,
                  style: TextStyle(fontSize: AppFont.px9, letterSpacing: 2, color: palette.ink2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.bactions .btn`：32 高 / 12.5 号 / 左右 14 内距（设计稿按钮标准尺寸）。
class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.label, this.primary = false, required this.onTap});

  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onTap: onTap,
      variant: primary ? AppButtonVariant.primary : AppButtonVariant.ghost,
      height: 32,
      horizontalPadding: 14,
      fontSize: AppFont.px12_5,
      fontWeight: primary ? FontWeight.w600 : null,
    );
  }
}

/// `.tag`：10 号、1/8 内距、999 圆角、card 底 + line2 描边。
enum _TagTone { normal, good, warn }

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.tone = _TagTone.normal});

  final String text;
  final _TagTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (bg, border, fg) = switch (tone) {
      _TagTone.normal => (palette.card, palette.line2, palette.ink2),
      _TagTone.good => (palette.good.withValues(alpha: 0.12), Colors.transparent, palette.good),
      _TagTone.warn => (palette.warn.withValues(alpha: 0.12), Colors.transparent, palette.warn),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(kPillRadius),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: AppFont.px10, color: fg),
      ),
    );
  }
}

/// 区头（`.lib-scroll` 里的 `h3 12.5/700` + `anno-note 10.5 mut` + 右侧视图切换）。
///
/// 章节区：`章节 · 共 N 话 · 封面取自本话第 1 页` + `重译整本`；
/// 页面区：`页面` + `单话没有章节层级 · 封面即第 1 页`。
class _PageSectionHeader extends ConsumerWidget {
  const _PageSectionHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(libModeProvider);
    return _SectionRow(
      title: l10n.readerPagesTitle,
      note: l10n.libSinglePageHint,
      trailing: [
        if (mode == 'capsule')
          Text(
            l10n.libCapsuleLegend,
            style: TextStyle(fontSize: AppFont.px9_5, color: AppPalette.of(context).mut),
          ),
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
    return _SectionRow(
      title: l10n.bookChapters,
      note: l10n.libChapterPages(book.chapterCount),
      trailing: [
        _ViewSeg(mode: mode, onSelect: (m) => ref.read(libModeProvider.notifier).set(m)),
        // `.btn.ghost.sm`：26 高 / 10 内距 / 11 号
        AppButton(
          label: l10n.libRetranslateBook,
          onTap: () => _retranslateBook(context, ref, book),
          variant: AppButtonVariant.ghost,
          height: 26,
          horizontalPadding: 10,
          fontSize: AppFont.px11,
        ),
      ],
    );
  }
}

Future<void> _retranslateBook(BuildContext context, WidgetRef ref, LibBook book) async {
  final l10n = AppLocalizations.of(context);
  try {
    await ref.read(mangaSvcClientProvider).retranslateBook(book.key);
    if (context.mounted) showAppToast(context, l10n.shelfRetranslateOk(book.name), tone: ToastTone.good);
  } catch (e) {
    if (context.mounted) showAppToast(context, '$e', tone: ToastTone.bad);
  }
}

/// `h3` + `anno-note` + 右侧动作的一行（章节区 / 页面区共用）。
class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.title, required this.note, this.trailing = const []});

  final String title;
  final String note;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.ink),
        ),
        const SizedBox(width: 10),
        // 🔴 说明文字用 **Expanded** 吃掉全部剩余宽度，不能 `Flexible + Spacer`：
        // 两者会平分剩余空间，说明短时它那半份用不完、Spacer 又只占另一半，
        // 于是右侧动作（卡片/简易、重译整本）停在离页边 280px 的半空 —— 没有靠右对齐。
        Expanded(
          child: Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
          ),
        ),
        for (final w in trailing) ...[const SizedBox(width: 8), w],
      ],
    );
  }
}

/// `.foot-hint`：10 号、mut、行高 1.7。
class _FootHint extends StatelessWidget {
  const _FootHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: AppFont.px10, height: 1.7, color: AppPalette.of(context).mut),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          style: TextStyle(fontSize: AppFont.px12_5, color: AppPalette.of(context).mut),
        ),
      ),
    );
  }
}

/// 话内页卡网格：minmax(104) / gap 10；缺页页 = 深底「缺页」格，不可点。
class _PageCells extends StatelessWidget {
  const _PageCells({required this.book, required this.chapter});

  final LibBook book;
  final LibChapter chapter;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 104,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 3 / 4,
      ),
      itemCount: chapter.pageCount,
      itemBuilder: (context, i) => _ChapterPageCell(book: book, chapter: chapter, seq: i + 1),
    );
  }
}

/// `.pcard`：已译 / 待译 / 缺页三态。判定**只用逐页集合**。
class _ChapterPageCell extends ConsumerStatefulWidget {
  const _ChapterPageCell({required this.book, required this.chapter, required this.seq});

  final LibBook book;
  final LibChapter chapter;
  final int seq;

  @override
  ConsumerState<_ChapterPageCell> createState() => _ChapterPageCellState();
}

class _ChapterPageCellState extends ConsumerState<_ChapterPageCell> {
  bool _hover = false;
  MemoryImage? _cover;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // 🔴 缺页不拉原图（服务端 404 会刷日志）；直接落「缺页」格。
    if (widget.chapter.isMissing(widget.seq)) {
      _loaded = true;
      return;
    }
    try {
      ref
          .read(mangaSvcClientProvider)
          .getChapterFile(widget.book.key, widget.chapter.no, widget.seq)
          .then((v) {
            if (!mounted) return;
            setState(() {
              _cover = v.isEmpty ? null : MemoryImage(Uint8List.fromList(v));
              _loaded = true;
            });
          })
          .catchError((_) {
            if (!mounted) return;
            setState(() => _loaded = true);
          });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final seq = widget.seq;
    final chapter = widget.chapter;
    final missing = chapter.isMissing(seq);
    final done = chapter.isTranslated(seq);
    final hoverable = !context.isMobile && !missing;

    final cell = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: missing ? palette.card : palette.paperCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hoverable && _hover ? palette.accent : Colors.transparent),
      ),
      child: missing
          ? Center(
              child: Text(
                l10n.libChapterMissingPlaceholder,
                style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                if (_cover != null)
                  Image(image: _cover!, fit: BoxFit.cover)
                else if (_loaded)
                  _NoImagePlaceholder(palette: palette)
                else
                  const SizedBox.shrink(),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: done ? palette.good.withValues(alpha: 0.9) : palette.accent.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(kPillRadius),
                    ),
                    child: Text(
                      done ? l10n.libChapterStatusDone : l10n.libChapterStatusPending,
                      style: TextStyle(
                        fontSize: AppFont.px8_5,
                        fontWeight: FontWeight.w700,
                        color: done ? palette.bg : palette.onAcc,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(5, 10, 5, 3),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x8C000000)],
                      ),
                    ),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            l10n.libPageLabel(seq),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: AppFont.px8_5, color: Colors.white),
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            _pageFileName(seq),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: AppFont.px8_5, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );

    if (missing) return cell;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => _openReaderAtChapterPage(context, ref, widget.book, chapter, widget.seq),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: hoverable && _hover ? 1.04 : 1,
          child: cell,
        ),
      ),
    );
  }
}

/// `.pggrid`：minmax(104,1fr) / gap 10 / 3:4 卡片。
class _PageGrid extends StatelessWidget {
  const _PageGrid({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 104,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 3 / 4,
      ),
      itemCount: book.directPages,
      itemBuilder: (context, i) => _PageCard(book: book, seq: i + 1),
    );
  }
}

/// `.pcard`：3:4 / 8 圆角 / `#f5f2ea` 纸底；hover 放大 1.04 + 主色描边。
/// 右上角 `stamp`（已译绿 / 待译橙 / 缺页灰），底部渐变条给页码 + 文件名。
class _PageCard extends ConsumerStatefulWidget {
  const _PageCard({required this.book, required this.seq});

  final LibBook book;
  final int seq;

  @override
  ConsumerState<_PageCard> createState() => _PageCardState();
}

class _PageCardState extends ConsumerState<_PageCard> {
  bool _hover = false;
  MemoryImage? _cover;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // 🔴 provider 缓存在 state：否则每次 build 新建 MemoryImage 会重新解码（闪烁）。
    // 🔴 A 级替身的取图方法**同步 throw**，必须 try/catch。
    try {
      ref
          .read(mangaSvcClientProvider)
          .getBookFile(widget.book.key, widget.seq)
          .then((v) {
            if (!mounted) return;
            setState(() {
              _cover = v.isEmpty ? null : MemoryImage(Uint8List.fromList(v));
              _loaded = true;
            });
          })
          .catchError((_) {
            if (!mounted) return;
            setState(() => _loaded = true);
          });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final book = widget.book;
    final seq = widget.seq;
    // 页卡三态判定**只用逐页集合**（张数推不出「译了哪几页」）。
    final done = book.directTranslated.contains(seq);
    final hoverable = !context.isMobile;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: hoverable ? (_) => setState(() => _hover = true) : null,
      onExit: hoverable ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        onTap: () => _openReaderAtPage(context, ref, book, widget.seq),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: hoverable && _hover ? 1.04 : 1,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: palette.paperCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hoverable && _hover ? palette.accent : Colors.transparent),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_cover != null)
                  Image(image: _cover!, fit: BoxFit.cover)
                else if (_loaded)
                  _NoImagePlaceholder(palette: palette)
                else
                  const SizedBox.shrink(),
                // `stamp`：右上角 8.5 号 999 圆角胶囊。
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: done ? palette.good.withValues(alpha: 0.9) : palette.accent.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(kPillRadius),
                    ),
                    child: Text(
                      done ? l10n.libChapterStatusDone : l10n.libChapterStatusPending,
                      style: TextStyle(
                        fontSize: AppFont.px8_5,
                        fontWeight: FontWeight.w700,
                        color: done ? palette.bg : palette.onAcc,
                      ),
                    ),
                  ),
                ),
                // `.plabel`：底部渐变条（页码 + `001.png`）。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(5, 10, 5, 3),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x8C000000)],
                      ),
                    ),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            l10n.libPageLabel(seq),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: AppFont.px8_5, color: Colors.white),
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            _pageFileName(seq),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: AppFont.px8_5, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _pageFileName(int seq) => '${seq.toString().padLeft(3, '0')}.png';

/// `.caps`：简易态页码胶囊（hover 主色描边 + 主色字）。
class _PageCapsules extends ConsumerWidget {
  const _PageCapsules({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var seq = 1; seq <= book.directPages; seq++)
          _Cap(label: l10n.libPageCapsule(seq), onTap: () => _openReaderAtPage(context, ref, book, seq)),
      ],
    );
  }
}

/// `.chgrid`：minmax(150,1fr) / gap 10 / 封面 4:5 + 卡片体。
///
/// 窄屏复用同一格 **只是放大格宽**（190 ⇒ 手机上两列）—— 话卡样式与桌面逐字一致
/// （用户口径，D-164），不再维护一套窄屏行列表。
///
/// 高度按「封面 4:5 + 固定卡片体」算：格宽在不同断点下不同，写死 `childAspectRatio`
/// 会让封面在手机上被压扁成方块（设计稿 `.cc-cover{aspect-ratio:4/5}`）。
class _ChapterGrid extends StatelessWidget {
  const _ChapterGrid({required this.book});

  final LibBook book;

  /// 卡片体（标题 + 进度 + 进度条 + 状态）的高度，与 [_ChapterCard] 的内距同源。
  static const double _bodyHeight = 92;

  @override
  Widget build(BuildContext context) {
    final maxExtent = context.isMobile ? 190.0 : 150.0;
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        final width = box.maxWidth.isFinite ? box.maxWidth : maxExtent;
        // 与 SliverGridDelegateWithMaxCrossAxisExtent 同一算式，只是要拿回真实格宽。
        final cols = math.max(1, ((width + gap) / (maxExtent + gap)).ceil());
        final cell = (width - gap * (cols - 1)) / cols;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: cell / (cell * 5 / 4 + _bodyHeight),
          ),
          itemCount: book.chapters.length,
          itemBuilder: (context, i) => _ChapterCard(book: book, chapter: book.chapters[i]),
        );
      },
    );
  }
}

/// `.ccard`：card 底 / 10 圆角 / `line` 描边（状态描边：done 绿、pending 琥珀、
/// missing 虚线 + 0.75 透明）；hover 上浮 2px。封面 4:5，左上状态徽标，右上 hover ⋯。
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
    final l10n = AppLocalizations.of(context);
    final book = widget.book;
    final chapter = widget.chapter;
    final missing = chapter.missingSeqs.length;
    final pending = chapter.pageCount - chapter.donePages - missing;
    final tone = missing > 0 ? _ChapterTone.missing : (pending > 0 ? _ChapterTone.pending : _ChapterTone.done);
    final borderColor = switch (tone) {
      _ChapterTone.done => palette.good.withValues(alpha: 0.35),
      _ChapterTone.pending => palette.warn.withValues(alpha: 0.4),
      _ChapterTone.missing => palette.line,
    };
    final hoverable = !context.isMobile;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: hoverable ? (_) => setState(() => _hover = true) : null,
      onExit: hoverable ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        onTap: () => _openChapter(context, ref, book, chapter),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0, hoverable && _hover ? -2 : 0, 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Opacity(
            opacity: tone == _ChapterTone.missing ? 0.75 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // `.cc-cover`：本话第 1 页做封面（单话同源：`PageArt.page(1)`）。
                      _ChapterCover(book: book, chapter: chapter),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: _StatusBadge(
                          label: switch (tone) {
                            _ChapterTone.done => l10n.libChapterStatusDone,
                            _ChapterTone.pending => l10n.libChapterStatusPending,
                            _ChapterTone.missing => l10n.libChapterStatusMissing,
                          },
                          tone: tone,
                        ),
                      ),
                      // 话卡「⋯」：桌面 hover 才显；窄屏没有 hover，常驻可见。
                      Positioned(
                        top: 6,
                        right: 6,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: hoverable && !_hover ? 0 : 1,
                          child: ChapterMenuButton(book: book, chapter: chapter),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.chapterTitle(jsNumStr(chapter.no)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppFont.px11_5, fontWeight: FontWeight.w700, color: palette.ink),
                      ),
                      Text(
                        l10n.chapterProgress(chapter.donePages, chapter.pageCount),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          height: 3,
                          child: LinearProgressIndicator(
                            value: chapter.ratio,
                            backgroundColor: palette.line,
                            valueColor: AlwaysStoppedAnimation(tone == _ChapterTone.done ? palette.good : palette.warn),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        // 状态优先级：缺页 > 待译，两个数都写出来（必须带「页」字）。
                        missing > 0 && pending > 0
                            ? l10n.libChapterBothState(missing, pending)
                            : missing > 0
                            ? l10n.chapterMissingPages(missing)
                            : pending > 0
                            ? l10n.chapterPendingPages(pending)
                            : l10n.libUpdatedRecently,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppFont.px9_5, color: palette.mut),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _openChapter(BuildContext context, WidgetRef ref, LibBook book, LibChapter chapter) {
  // 设计稿：桌面话卡点击进「页网格」，页卡点击才进阅读器。
  // 窄屏没有页网格屏，`查看` 直接进该话阅读器。
  if (context.isMobile) {
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
    return;
  }
  ref.read(libChapterOpenProvider.notifier).open(chapter.no);
}

/// 打开阅读器并落到**指定页**（1 基）。
///
/// 🔴 `open()` 的语义是「换话/换书 = 从头读」，它会把页码归零，
/// 所以点某页进去必须**在 open 之后再设页码**，顺序反了会被重置回第 1 页。
void _seekReaderPage(WidgetRef ref, int seq, int total) {
  if (total <= 0) return;
  ref.read(readerPageProvider.notifier).set((seq - 1).clamp(0, total - 1));
}

/// 单话直读：点第 [seq] 页进阅读器。
void _openReaderAtPage(BuildContext context, WidgetRef ref, LibBook book, int seq) {
  ref
      .read(readerSessionProvider.notifier)
      .open(ReaderSession(key: book.key, pages: book.directPages, translated: book.directTranslated));
  _seekReaderPage(ref, seq, book.directPages);
  context.go('/manga/reader');
}

/// 单本某话：点该话第 [seq] 页进阅读器（不是第 1 页）。
void _openReaderAtChapterPage(BuildContext context, WidgetRef ref, LibBook book, LibChapter chapter, int seq) {
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
  _seekReaderPage(ref, seq, chapter.pageCount);
  context.go('/manga/reader');
}

enum _ChapterTone { done, pending, missing }

/// 话卡封面：取本话第 1 页原图（`.cc-cover` 4:5）。
class _ChapterCover extends ConsumerStatefulWidget {
  const _ChapterCover({required this.book, required this.chapter});

  final LibBook book;
  final LibChapter chapter;

  @override
  ConsumerState<_ChapterCover> createState() => _ChapterCoverState();
}

class _ChapterCoverState extends ConsumerState<_ChapterCover> {
  MemoryImage? _cover;

  @override
  void initState() {
    super.initState();
    // 🔴 A 级替身的 getChapterFile 是**同步 throw**（不是失败 Future），
    // 不用 try/catch 会直接炸出 build。
    try {
      ref
          .read(mangaSvcClientProvider)
          .getChapterFile(widget.book.key, widget.chapter.no, 1)
          .then((v) {
            if (!mounted || v.isEmpty) return;
            setState(() => _cover = MemoryImage(Uint8List.fromList(v)));
          })
          .catchError((_) {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (_cover != null) return Image(image: _cover!, fit: BoxFit.cover);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.cardCover, palette.bg],
        ),
      ),
    );
  }
}

/// `.badge`：24 高 / 9 内距 / 999 圆角 / 7px 圆点 / 10.5 号；三态描边配色。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.tone});

  final String label;
  final _ChapterTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dot = switch (tone) {
      _ChapterTone.done => palette.good,
      _ChapterTone.pending => palette.warn,
      _ChapterTone.missing => palette.bad,
    };
    return Transform.scale(
      scale: 0.85,
      alignment: Alignment.topLeft,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(kPillRadius),
          border: Border.all(color: dot.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(fontSize: AppFont.px10_5, color: palette.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.caps` 简易态：章节胶囊（点击直达页网格）。
class _ChapterCapsules extends ConsumerWidget {
  const _ChapterCapsules({required this.book});

  final LibBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final c in book.chapters)
          _Cap(label: l10n.chapterTitle(jsNumStr(c.no)), onTap: () => _openChapter(context, ref, book, c)),
      ],
    );
  }
}

/// `.cap`：2/9 内距 / 999 圆角 / `hi` 底 + `line2` 描边 / 10 号 ink2；
/// hover 描边与字转主色（设计稿 `.cap:hover`）。
class _Cap extends StatefulWidget {
  const _Cap({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_Cap> createState() => _CapState();
}

class _CapState extends State<_Cap> {
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
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: palette.hi,
            borderRadius: BorderRadius.circular(kPillRadius),
            border: Border.all(color: _hover ? palette.accent : palette.line2),
          ),
          child: Text(
            widget.label,
            style: TextStyle(fontSize: AppFont.px10, color: _hover ? palette.accent : palette.ink2),
          ),
        ),
      ),
    );
  }
}

class _CreateBookDialog extends StatefulWidget {
  const _CreateBookDialog();

  static Future<String?> show(BuildContext context) =>
      showAppDialog<String>(context: context, builder: (_) => const _CreateBookDialog());

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
    final name = _controller.text.trim();
    // 设计稿校验三层顺序 = 非法字符 → 同名 → 空名（同名由服务端拦截，这里先拦前一层）。
    final invalid = RegExp(r'[\\/:*?"<>|]').hasMatch(name);
    final hint = invalid
        ? l10n.libCreateBookNameInvalid
        : (name.isEmpty ? l10n.libCreateBookNameRequired : l10n.libCreateBookFolderHint);
    return AppDialog(
      title: l10n.libCreateBook,
      subtitle: l10n.libCreateBookSub,
      actions: [
        AppButton(label: l10n.actionCancel, onTap: () => Navigator.of(context).pop()),
        AppButton(
          label: l10n.libCreateBook,
          variant: AppButtonVariant.primary,
          onTap: name.isEmpty || invalid ? null : () => Navigator.of(context).pop(name),
        ),
      ],
      child: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.libChapterName,
              style: TextStyle(fontSize: AppFont.px10_5, fontWeight: FontWeight.w600, color: palette.ink),
            ),
            const SizedBox(height: 5),
            AppInput(
              controller: _controller,
              hint: l10n.libCreateBookNameHint,
              errorText: invalid ? hint : null,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty && !invalid) Navigator.of(context).pop(v.trim());
              },
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              style: TextStyle(fontSize: AppFont.px10, color: invalid ? palette.bad : palette.mut),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.bookAuthorLabel('').replaceAll(' · ', ''),
              style: TextStyle(fontSize: AppFont.px10_5, fontWeight: FontWeight.w600, color: palette.ink),
            ),
            const SizedBox(height: 5),
            AppInput(hint: l10n.libAuthorHint, onChanged: (_) {}),
          ],
        ),
      ),
    );
  }
}

class _EditBookDialog extends ConsumerStatefulWidget {
  const _EditBookDialog({required this.book});

  final LibBook book;

  static Future<EditBookResult?> show(BuildContext context, {required LibBook book}) => showAppDialog<EditBookResult>(
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
    return AppDialog(
      title: l10n.libEditInfoTitle,
      width: 420,
      actions: [
        AppButton(label: l10n.actionCancel, onTap: () => Navigator.of(context).pop()),
        AppButton(
          label: l10n.libEditInfoOk,
          variant: AppButtonVariant.primary,
          // 选了「本地图片」但还没选文件时不可保存（半落盘状态比失败更糟）。
          onTap: (_cover == CoverIntent.local && _bytes == null)
              ? null
              : () => Navigator.of(context).pop(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                        style: TextStyle(fontSize: AppFont.px10_5, color: palette.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 文字信息
          Text(
            l10n.libCreateBookNameHint,
            style: TextStyle(fontSize: AppFont.px11, color: palette.textSecondary),
          ),
          const SizedBox(height: 5),
          AppInput(controller: _title, hint: l10n.libCreateBookNameHint),
          const SizedBox(height: 12),
          Text(
            l10n.bookAuthorLabel(''),
            style: TextStyle(fontSize: AppFont.px11, color: palette.textSecondary),
          ),
          const SizedBox(height: 5),
          AppInput(controller: _author, hint: l10n.bookAuthorLabel('')),
        ],
      ),
    );
  }

  /// 封面预览（ver1.0 `.cover-preview`）：本地图即时预览；无封面显示占位。
  Widget _preview() {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    if (_cover == CoverIntent.remove) {
      return Center(
        child: Text(
          l10n.libCoverNone,
          style: TextStyle(fontSize: AppFont.px10_5, color: palette.textSecondary),
        ),
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
            child: Text(
              l10n.libCoverNone,
              style: TextStyle(fontSize: AppFont.px10_5, color: palette.textSecondary),
            ),
          );
        }
        return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover);
      },
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
      fontSize: AppFont.px10_5,
    );
  }
}

/// `.vseg`（卡片 / 简易切换）：card 底 + line2 描边 + 8 圆角 + 2 内距；
/// 按钮 30×26，选中 = accent 底 + onAcc 图标（设计稿网格 / 列表两个图标）。
class _ViewSeg extends StatelessWidget {
  const _ViewSeg({required this.mode, required this.onSelect});

  final String mode;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.line2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (m, icon) in const [('card', LucideIcons.layoutGrid), ('capsule', LucideIcons.list)])
            GestureDetector(
              onTap: () => onSelect(m),
              child: Container(
                width: 30,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: mode == m ? palette.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 13, color: mode == m ? palette.onAcc : palette.ink2),
              ),
            ),
        ],
      ),
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

/// 单页卡片「无图」状态：中性底 + `imageOff` 图标 + 文案（**不含任何主色**）。
class _NoImagePlaceholder extends StatelessWidget {
  const _NoImagePlaceholder({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.card,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.imageOff, size: 18, color: palette.textSecondary),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).pageNoImage,
            style: TextStyle(fontSize: AppFont.px9_5, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
