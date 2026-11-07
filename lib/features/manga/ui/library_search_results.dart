import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:protocol/protocol.dart' show jsNumStr;

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/buttons.dart';
import '../controller/library_controller.dart';
import '../domain/lib_book.dart';
import 'shelf_menu.dart';

/// 右栏搜索分组（设计稿 `renderSearch`，屏 A′）：
///
/// - 工具栏 = `搜索「词」` + `N 本作品 · N 个命中` + `清除搜索`；
/// - 分组 = 作品命中（全话列出）或话号命中（仅命中话），组头**命中高亮**；
/// - `其它` 组（未归并单话）恒置底，行上 `归并` 胶囊直达归并弹窗；
/// - Esc 先退搜索。
class LibrarySearchResults extends ConsumerWidget {
  const LibrarySearchResults({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final groups = searchGroups(ref);
    final hitCount = groups.fold<int>(0, (s, g) => s + g.chapters.length);
    final singles = ref
        .watch(libraryProvider)
        .value
        ?.where((b) => !b.isBook && (fuzzyHit(b.name, query) || fuzzyHit(b.author, query)))
        .toList();
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          ref.read(shelfQueryProvider.notifier).set('');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `.lib-toolbar`：14 号标题 + 命中统计 + 清除搜索。
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    AppLocalizations.of(context).searchQuery(query),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px14, fontWeight: FontWeight.w700, color: palette.ink),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    AppLocalizations.of(context).searchSummary(groups.length, hitCount + (singles?.length ?? 0)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                  ),
                ),
                const Spacer(),
                AppButton(
                  label: AppLocalizations.of(context).libSearchClear,
                  onTap: () => ref.read(shelfQueryProvider.notifier).set(''),
                  variant: AppButtonVariant.ghost,
                  height: 26,
                  horizontalPadding: 10,
                  fontSize: AppFont.px11,
                ),
              ],
            ),
          ),
          Expanded(
            child: groups.isEmpty && (singles == null || singles.isEmpty)
                ? _SearchEmpty(query: query)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    children: [
                      for (final group in groups) ...[
                        _SearchGroup(group: group, query: query),
                        const SizedBox(height: 16),
                      ],
                      _SinglesGroup(singles: singles ?? const []),
                      const SizedBox(height: 12),
                      _FootHint(text: AppLocalizations.of(context).searchHint),
                      const SizedBox(height: 2),
                      _FootHint(text: AppLocalizations.of(context).searchEscHint),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 与 `fuzzyMatch` 同口径的轻量子串判断（搜索分组是**子串**语义）。
  static bool fuzzyHit(String value, String query) => value.toLowerCase().contains(query.toLowerCase());
}

/// `.grp`：组头（gico + 高亮名 + 计数 + 打开书架）+ 命中话行。
class _SearchGroup extends ConsumerWidget {
  const _SearchGroup({required this.group, required this.query});

  final ({LibBook book, List<LibChapter> chapters}) group;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final book = group.book;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `.grp-head`：6/0 内距；gico 26×26 card 底。
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(6)),
                alignment: Alignment.center,
                child: Text(
                  book.name.isEmpty ? '' : book.name.characters.first,
                  style: TextStyle(fontSize: AppFont.px11, fontWeight: FontWeight.w700, color: palette.ink2),
                ),
              ),
              const SizedBox(width: 8),
              _HighlightName(name: book.name, query: query),
              const SizedBox(width: 4),
              Text(
                AppLocalizations.of(context).searchBookHits(group.chapters.length),
                style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
              ),
              const Spacer(),
              // `.openlink`：清搜索并选中该本（margin-left auto）。
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    ref.read(shelfQueryProvider.notifier).set('');
                    ref.read(selectedBookProvider.notifier).select(book.key);
                  },
                  child: Text(
                    AppLocalizations.of(context).libSearchOpenBook,
                    style: TextStyle(fontSize: AppFont.px10_5, color: palette.accent),
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final chapter in group.chapters)
          _HitRow(
            leading: LucideIcons.fileText,
            title: AppLocalizations.of(context).chapterTitle(jsNumStr(chapter.no)),
            meta: AppLocalizations.of(context).chapterProgress(chapter.donePages, chapter.pageCount),
            onTap: () {
              // 设计稿 hitrow：清搜索 → 选中本 → 直接打开该话页网格。
              ref.read(shelfQueryProvider.notifier).set('');
              ref.read(selectedBookProvider.notifier).select(book.key);
              ref.read(libChapterOpenProvider.notifier).open(chapter.no);
            },
          ),
      ],
    );
  }
}

/// `其它` 组（未归并单话，恒置底）：warn 提示行 + 行内 `归并` 胶囊。
class _SinglesGroup extends ConsumerWidget {
  const _SinglesGroup({required this.singles});

  final List<LibBook> singles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: AppPalette.of(context).card, borderRadius: BorderRadius.circular(6)),
              alignment: Alignment.center,
              child: Text(
                l10n.libSearchOtherGico,
                style: TextStyle(
                  fontSize: AppFont.px11,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.of(context).ink2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.libSearchOtherGroup,
              style: TextStyle(
                fontSize: AppFont.px12_5,
                fontWeight: FontWeight.w700,
                color: AppPalette.of(context).ink,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              l10n.searchBookHits(singles.length),
              style: TextStyle(fontSize: AppFont.px10, color: AppPalette.of(context).mut),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.libSearchOtherHint,
          style: TextStyle(fontSize: AppFont.px10, height: 1.6, color: AppPalette.of(context).warn),
        ),
        for (final s in singles)
          _HitRow(
            leading: LucideIcons.file,
            title: s.name,
            meta: l10n.chapterProgress(s.directTranslated.length, s.pageCount),
            mergeSrc: s.key,
          ),
      ],
    );
  }
}

/// `.hitrow`：8/10 内距、10 圆角、hover card 底；
/// 行 = 文件图标 + 名（12/500）+ `N / N 页`（10.5 mut）+（可选）`归并` 胶囊。
class _HitRow extends ConsumerWidget {
  const _HitRow({required this.leading, required this.title, required this.meta, this.onTap, this.mergeSrc});

  final IconData leading;
  final String title;
  final String meta;
  final VoidCallback? onTap;

  /// 非 null 时行尾显示 `归并` 胶囊（只给未归并单话——已归并话的归并走章节菜单）。
  final String? mergeSrc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    bool hover = false;
    return StatefulBuilder(
      builder: (context, setState) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: hover ? palette.card : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(leading, size: 14, color: palette.mut),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px12, fontWeight: FontWeight.w500, color: palette.ink),
                  ),
                ),
                Text(
                  meta,
                  style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                ),
                if (mergeSrc != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => showMergeDialog(context, src: mergeSrc!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(kPillRadius),
                        border: Border.all(color: palette.accent.withValues(alpha: 0.45)),
                      ),
                      child: Text(
                        AppLocalizations.of(context).libMerge,
                        style: TextStyle(fontSize: AppFont.px10, color: palette.accent),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 组头书名：命中子串高亮（`.grp-hit`：accent 22% 底 + accent 字）。
class _HighlightName extends StatelessWidget {
  const _HighlightName({required this.name, required this.query});

  final String name;
  final String query;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final lower = name.toLowerCase();
    final q = query.toLowerCase();
    final idx = lower.indexOf(q);
    if (query.isEmpty || idx < 0) {
      return Text(
        name,
        style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.ink),
      );
    }
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.ink),
        children: [
          TextSpan(text: name.substring(0, idx)),
          TextSpan(
            text: name.substring(idx, idx + q.length),
            style: TextStyle(
              background: Paint()..color = palette.accent.withValues(alpha: 0.22),
              color: palette.accent,
            ),
          ),
          TextSpan(text: name.substring(idx + q.length)),
        ],
      ),
    );
  }
}

/// 空搜索态（设计稿）：居中标题 + 说明 + `清除搜索` / `去投放`。
class _SearchEmpty extends ConsumerWidget {
  const _SearchEmpty({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.libSearchNoResultTitle(query),
            style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 360,
            child: Text(
              l10n.libSearchNoResultHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppFont.px10_5, height: 1.7, color: palette.mut),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: l10n.libSearchClear,
                onTap: () => ref.read(shelfQueryProvider.notifier).set(''),
                variant: AppButtonVariant.ghost,
                height: 26,
                horizontalPadding: 10,
                fontSize: AppFont.px11,
              ),
              const SizedBox(width: 8),
              AppButton(
                label: l10n.shelfGoDrop,
                onTap: () => context.go('/manga/drop'),
                variant: AppButtonVariant.primary,
                height: 26,
                horizontalPadding: 10,
                fontSize: AppFont.px11,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `.foot-hint`：10 号 mut。
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
