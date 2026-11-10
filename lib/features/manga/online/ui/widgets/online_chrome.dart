import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/theme/tokens.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../shared/widgets/app_input.dart';
import '../../../../../shared/widgets/buttons.dart';
import '../../../../../shared/widgets/skeleton.dart';
import '../../controller/online_browse_controller.dart';
import '../../controller/online_sources_controller.dart';
import '../../domain/online_source.dart';
import 'online_common.dart';

/// 桌面在线主区顶栏（设计稿 `.topbar`，高 52）。
class OnlineTopBar extends ConsumerWidget {
  const OnlineTopBar({super.key, required this.title, required this.onManageSources, required this.onSearchSubmitted});

  final String title;
  final VoidCallback onManageSources;
  final ValueChanged<String> onSearchSubmitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final source = ref.watch(activeOnlineSourceProvider);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(bottom: BorderSide(color: palette.line2)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w700, color: palette.ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.onlineSourceCrumb(source?.name ?? '—', title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
            ),
          ),
          SizedBox(width: 320, child: _OnlineSearchField(onSubmitted: onSearchSubmitted)),
          const SizedBox(width: 10),
          AppButton(
            label: l10n.onlineManageSources,
            onTap: onManageSources,
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

class _OnlineSearchField extends ConsumerStatefulWidget {
  const _OnlineSearchField({required this.onSubmitted});

  final ValueChanged<String> onSubmitted;

  @override
  ConsumerState<_OnlineSearchField> createState() => _OnlineSearchFieldState();
}

class _OnlineSearchFieldState extends ConsumerState<_OnlineSearchField> {
  late final TextEditingController _controller = TextEditingController(text: ref.read(onlineNavProvider).searchInput);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    ref.read(onlineNavProvider.notifier).submitSearch(value);
    widget.onSubmitted(value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    ref.listen(onlineNavProvider.select((nav) => nav.searchInput), (previous, next) {
      if (next != _controller.text) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _controller.clear();
          ref.read(onlineNavProvider.notifier).clearSearch();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        height: 32,
        child: AppInput(
          controller: _controller,
          hint: l10n.onlineSearchHint,
          height: 32,
          fontSize: AppFont.px12,
          fillColor: palette.card,
          prefixIcon: LucideIcons.search,
          prefixIconSize: 13,
          onChanged: (value) => ref.read(onlineNavProvider.notifier).setSearchInput(value),
          onSubmitted: (_) => _submit(),
          suffix: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _submit,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(LucideIcons.chevronRight, size: 14, color: palette.mut),
            ),
          ),
        ),
      ),
    );
  }
}

/// 移动端顶部平台 chips（设计稿 `#m-platform`）。
class OnlineMobilePlatformBar extends ConsumerWidget {
  const OnlineMobilePlatformBar({super.key, required this.onImportSource});

  final VoidCallback onImportSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final sources = ref.watch(onlineSourcesProvider);
    final active = ref.watch(activeOnlineSourceProvider);
    return Container(
      height: 50,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: sources.when(
        skipLoadingOnRefresh: true,
        data: (items) {
          if (items.isEmpty) {
            return _scroll([
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: OnlineChip(
                  label: l10n.onlineImportFirst,
                  selected: true,
                  onTap: onImportSource,
                  leading: Icon(LucideIcons.plus, size: 13, color: palette.ink2),
                ),
              ),
            ]);
          }
          return _scroll([
            for (final source in items) _PlatformChip(source: source, selected: active?.id == source.id),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: OnlineChip(
                label: l10n.onlineImportSourceShort,
                onTap: onImportSource,
                leading: Icon(LucideIcons.plus, size: 13, color: palette.ink2),
              ),
            ),
          ]);
        },
        loading: () => _scroll([
          for (var i = 0; i < 4; i++)
            const Padding(padding: EdgeInsets.only(left: 8), child: SkeletonBox(width: 78, height: 32, radius: 999)),
        ]),
        error: (error, _) => _scroll([
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: OnlineTag(l10n.onlinePlatformLoadFailed, tone: OnlineTagTone.bad),
          ),
          OnlineChip(label: l10n.onlineErrorRetry, onTap: () => ref.read(onlineSourcesProvider.notifier).refresh()),
        ]),
      ),
    );
  }

  Widget _scroll(List<Widget> children) => ListView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 0),
    children: [
      const SizedBox(width: 14),
      for (final child in children) ...[child, const SizedBox(width: 12)],
    ],
  );
}

class _PlatformChip extends ConsumerWidget {
  const _PlatformChip({required this.source, required this.selected});

  final OnlineSource source;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return OnlineChip(
      label: source.name,
      selected: selected,
      leading: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: source.isAbnormal ? palette.bad : (source.enabled ? palette.good : palette.mut),
          shape: BoxShape.circle,
        ),
      ),
      onTap: source.enabled
          ? () {
              ref.read(onlineSourceSelectionProvider.notifier).select(source.id);
              ref.read(onlineNavProvider.notifier).selectView(OnlineView.discover);
            }
          : null,
    );
  }
}

/// 移动端搜索行：输入框占满宽度，回车 / 键盘搜索提交（不额外放按钮）。
class OnlineMobileSearchBar extends ConsumerStatefulWidget {
  const OnlineMobileSearchBar({super.key, required this.onSubmitted});

  final ValueChanged<String> onSubmitted;

  @override
  ConsumerState<OnlineMobileSearchBar> createState() => _OnlineMobileSearchBarState();
}

class _OnlineMobileSearchBarState extends ConsumerState<OnlineMobileSearchBar> {
  late final TextEditingController _controller = TextEditingController(text: ref.read(onlineNavProvider).searchInput);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    ref.read(onlineNavProvider.notifier).submitSearch(value);
    widget.onSubmitted(value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    ref.listen(onlineNavProvider.select((nav) => nav.searchInput), (previous, next) {
      if (next != _controller.text) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            _controller.clear();
            ref.read(onlineNavProvider.notifier).clearSearch();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AppInput(
          controller: _controller,
          hint: l10n.onlineSearchHint,
          height: 40,
          fontSize: AppFont.px12,
          fillColor: palette.card,
          prefixIcon: LucideIcons.search,
          prefixIconSize: 13,
          onChanged: (value) => ref.read(onlineNavProvider.notifier).setSearchInput(value),
          onSubmitted: (_) => _submit(),
        ),
      ),
    );
  }
}

/// 移动端二级标签（发现 / 分类 / 最近），设计稿 `.mtabs.sub`。
class OnlineMobileSubTabs extends ConsumerWidget {
  const OnlineMobileSubTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final nav = ref.watch(onlineNavProvider);
    final items = [
      (OnlineView.discover, l10n.onlineDiscover),
      (OnlineView.categories, l10n.onlineCategories),
      (OnlineView.recent, l10n.onlineRecentShort),
    ];
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.line2)),
      ),
      child: Row(
        children: [
          for (final (i, (view, label)) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 18),
            _SubTab(
              label: label,
              active: nav.view == view && nav.query.isEmpty,
              onTap: () => ref.read(onlineNavProvider.notifier).selectView(view),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubTab extends StatelessWidget {
  const _SubTab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active ? palette.acc : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppFont.px12,
            color: active ? palette.accInk : palette.mut,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
