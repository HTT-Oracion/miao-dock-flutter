import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../controller/music_playlist_library.dart';
import '../../controller/music_player.dart';
import '../../controller/music_session.dart';
import '../../domain/music_models.dart';
import '../widgets/fail_magic.dart';
import '../widgets/music_scroll_memory.dart';
import '../widgets/music_shared.dart';

/// 我的歌单库（设计稿 N41/N43/N44/M18）。
///
/// 信息架构对齐 miao-dock 左栏：`我喜欢的音乐` 系统歌单独占一张横卡置顶，
/// 其下是「创建的歌单」「收藏的歌单」两个按 `subscribed` 语义位拆分的分组，
/// 组头可折叠（状态放屏级 controller，跨视图保留）；点条目才下钻曲目详情。
///
/// 四态：未登录 → 登录 CTA；加载 → 按真实布局的骨架；失败 → 魔法阵 + 重试；
/// 整库空 → 「还没有创建歌单」。空分组连组头一起不渲染（不留假入口）。
/// 页内不放大标题 / 总数（N44：面包屑与页签已标出位置）。
class PlaylistLibraryView extends ConsumerWidget {
  const PlaylistLibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logged = ref.watch(musicAccountProvider.select((a) => a.logged));
    final library = ref.watch(playlistLibraryProvider);
    final playlists = ref.watch(userPlaylistsProvider);

    if (!logged) return const _LoginCta();

    final firstLoadFail = playlists.hasError && playlists.value == null;
    if (firstLoadFail) {
      return _FailPage(error: playlists.error, onRetry: () => ref.invalidate(userPlaylistsProvider));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // N29：已有旧数据时刷新失败 → 顶部横幅，旧内容继续显示。
        if (playlists.hasError && playlists.value != null)
          ErrorBanner(
            compact: true,
            error: playlists.error,
            onRetry: () => ref.invalidate(userPlaylistsProvider),
            showStaleHint: true,
          ),
        Expanded(
          // N03：切视图后回来恢复滚动位置。
          child: MusicScrollMemory(
            storageKey: 'playlist',
            builder: (context, controller) => SingleChildScrollView(
              controller: controller,
              child: playlists.value == null
                  ? const PlaylistLibrarySkeleton()
                  : _LibraryBody(groups: groupPlaylists(playlists.value!, library.unsubscribed), state: library),
            ),
          ),
        ),
      ],
    );
  }
}

/// 分组主体：系统歌单横卡 + 两个可折叠组（N41）。
class _LibraryBody extends ConsumerWidget {
  const _LibraryBody({required this.groups, required this.state});

  final PlaylistGroups groups;
  final PlaylistLibraryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mobile = context.isMobile;
    final liked = groups.liked;
    if (groups.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: mobile ? 40 : 60),
        child: Center(
          child: Text(
            l10n.musicPlLibraryEmpty,
            style: TextStyle(fontSize: AppFont.px11, color: AppPalette.of(context).mut),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (liked != null) ...[_LikedCard(playlist: liked), SizedBox(height: mobile ? 18 : 18)],
        if (groups.created.isNotEmpty) ...[
          _GroupCaption(
            label: l10n.musicPlLibraryCreated,
            collapsed: state.createdCollapsed,
            onTap: () => ref.read(playlistLibraryProvider.notifier).toggleGroup(collected: false),
          ),
          if (!state.createdCollapsed) _PlaylistGroupBody(items: groups.created),
        ],
        if (groups.collected.isNotEmpty) ...[
          SizedBox(height: mobile ? 12 : 14),
          _GroupCaption(
            label: l10n.musicPlLibraryCollected,
            collapsed: state.collectedCollapsed,
            onTap: () => ref.read(playlistLibraryProvider.notifier).toggleGroup(collected: true),
          ),
          if (!state.collectedCollapsed) _PlaylistGroupBody(items: groups.collected, collected: true),
        ],
        const SizedBox(height: 10),
      ],
    );
  }
}

/// 组头：纯小标签（10 / 700 / 疏排），可折叠但不加箭头或刷新钮（N41）。
class _GroupCaption extends ConsumerStatefulWidget {
  const _GroupCaption({required this.label, required this.collapsed, required this.onTap});

  final String label;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  ConsumerState<_GroupCaption> createState() => _GroupCaptionState();
}

class _GroupCaptionState extends ConsumerState<_GroupCaption> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final mobile = context.isMobile;
    return Semantics(
      button: true,
      expanded: !widget.collapsed,
      label: widget.collapsed ? l10n.musicPlLibraryExpand(widget.label) : l10n.musicPlLibraryCollapse(widget.label),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              mobile ? 4 : 6,
              widget.collapsed ? 3 : 7,
              mobile ? 4 : 6,
              widget.collapsed ? 3 : 5,
            ),
            child: Opacity(
              opacity: widget.collapsed ? 0.72 : 1,
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: AppFont.px10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: _hover ? palette.ink2 : palette.mut,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「我喜欢的音乐」系统歌单横卡（app.css `.pl-liked` / mobile `.m-plliked`）。
class _LikedCard extends ConsumerStatefulWidget {
  const _LikedCard({required this.playlist});

  final MusicPlaylist playlist;

  @override
  ConsumerState<_LikedCard> createState() => _LikedCardState();
}

class _LikedCardState extends ConsumerState<_LikedCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final mobile = context.isMobile;
    final p = widget.playlist;
    // 红心封面是**内容色**（设计稿 #C2553F → #7A2C26，约 hue 11），不随主题变化 ——
    // 与 SeedGradient 同口径用色相生成，而不是借主题 bad（浅色档会偏灰）。
    // 红心封面是**内容色**（设计稿 `.lk-cover`：linear-gradient(140deg,#C2553F,#7A2C26)
    // + 内描边），与封面渐变同属内容、不随主题变化；不用 SeedGradient 的固定
    // 明度档，否则深色下会偏成土黄。
    final cover = Container(
      width: mobile ? 52 : 60,
      height: mobile ? 52 : 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(mobile ? 11 : 14),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: likedCoverColors),
        boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.16), spreadRadius: -1)],
      ),
      child: Icon(LucideIcons.heart, size: mobile ? 26 : 30, color: palette.coverInk),
    );
    return Semantics(
      button: true,
      label: l10n.musicPlLibraryAriaLiked,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => GoRouter.of(context).go('/music/playlist/${p.id}'),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.morphCurve,
            transform: Matrix4.translationValues(0, _hover && !mobile ? -2 : 0, 0),
            padding: EdgeInsets.all(mobile ? 12 : 16),
            decoration: BoxDecoration(
              color: palette.card,
              border: Border.all(color: _hover ? palette.acc : palette.line),
              borderRadius: BorderRadius.circular(mobile ? AppMetrics.radiusCardLg : 14),
              boxShadow: _hover && !mobile
                  ? [
                      BoxShadow(
                        color: palette.shadow.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                cover,
                SizedBox(width: mobile ? 12 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.musicPlLibraryLikedTitle,
                        style: TextStyle(
                          fontSize: mobile ? AppFont.px14 : AppFont.px17,
                          fontWeight: FontWeight.w800,
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.musicPlLibraryLikedDesc(p.trackCount),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: mobile ? AppFont.px10_5 : AppFont.px11_5, color: palette.mut),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: mobile ? 18 : 20,
                        padding: EdgeInsets.symmetric(horizontal: mobile ? 7 : 8),
                        decoration: BoxDecoration(
                          color: palette.accSoft,
                          borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.sparkles, size: mobile ? 9 : 10, color: palette.accInk),
                            const SizedBox(width: 3),
                            Text(
                              l10n.musicPlLibraryLikedTag,
                              style: TextStyle(
                                fontSize: mobile ? AppFont.px9_5 : AppFont.px10,
                                fontWeight: FontWeight.w600,
                                color: palette.accInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: mobile ? 16 : 18, color: palette.mut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一组歌单的内容：桌面 4 列紧凑信息卡（lg/md 4 列、sm 2 列），移动单列行。
///
/// 创建 / 收藏两组复用同一个组件，只靠 [collected] 决定封面角标与遮挡语义（N43）。
class _PlaylistGroupBody extends StatelessWidget {
  const _PlaylistGroupBody({required this.items, this.collected = false});

  final List<MusicPlaylist> items;
  final bool collected;

  @override
  Widget build(BuildContext context) {
    if (context.isMobile) {
      return Column(
        children: [for (final p in items) _PlaylistRow(playlist: p, collected: collected)],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        // 设计稿 N42：lg/md 4 列、sm（<900）2 列；封面尺寸固定，降列不撑成巨块。
        final cols = box.maxWidth < AppMetrics.musicNarrowBreakpoint ? 2 : 4;
        return _CompactGrid(cols: cols, items: items, collected: collected);
      },
    );
  }
}

/// 紧凑信息卡网格（Column + Row 内在高度排版，避免固定高溢出）。
class _CompactGrid extends StatelessWidget {
  const _CompactGrid({required this.cols, required this.items, this.collected = false});

  final int cols;
  final List<MusicPlaylist> items;
  final bool collected;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    return Column(
      children: [
        for (var i = 0; i < items.length; i += cols) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var k = i; k < i + cols; k++) ...[
                if (k > i) const SizedBox(width: gap),
                Expanded(
                  child: k < items.length
                      ? _PlaylistCard(playlist: items[k], collected: collected)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
          const SizedBox(height: gap),
        ],
      ],
    );
  }
}

/// 单张紧凑信息卡（app.css `.pl-card`：60px 封面 / 两行歌名 / 作者 · N 首）。
class _PlaylistCard extends ConsumerStatefulWidget {
  const _PlaylistCard({required this.playlist, required this.collected});

  final MusicPlaylist playlist;
  final bool collected;

  @override
  ConsumerState<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends ConsumerState<_PlaylistCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final p = widget.playlist;
    final meta = p.author == null || p.author!.isEmpty
        ? l10n.musicCountSongs(p.trackCount)
        : l10n.musicPlLibraryCardMeta(p.author!, p.trackCount);
    return Semantics(
      button: true,
      label: widget.collected ? l10n.musicPlLibraryAriaCollected(p.name) : l10n.musicPlLibraryAriaPlaylist(p.name),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => GoRouter.of(context).go('/music/playlist/${p.id}'),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.morphCurve,
            transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.card,
              border: Border.all(color: _hover ? palette.acc : palette.line),
              borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
              boxShadow: _hover
                  ? [
                      BoxShadow(
                        color: palette.shadow.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                _PlaylistCover(playlist: p, size: 60, radius: 9, collected: widget.collected),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        // 两行标题的固定占位：单行标题也不让同行卡片塌高（N42）。
                        height: 32,
                        child: Text(
                          p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFont.px12_5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: palette.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  duration: AppMotion.fast,
                  opacity: _hover ? 1 : 0,
                  child: Icon(LucideIcons.chevronRight, size: 14, color: palette.mut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 封面 + 收藏角标（设计稿 `.pl-flag`：15px 橙圆底心形，压在封面右下角）。
class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.playlist, required this.size, required this.radius, this.collected = false});

  final MusicPlaylist playlist;
  final double size;
  final double radius;
  final bool collected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final flag = size > 50 ? 15.0 : 12.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SeedCover(seed: playlist.name, size: size, radius: radius),
          if (collected)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: flag,
                height: flag,
                decoration: BoxDecoration(
                  color: palette.acc,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.card, width: 2),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.heart, size: flag * 0.6, color: palette.onAcc),
              ),
            ),
        ],
      ),
    );
  }
}

/// 移动端单列歌单行（app.css `.m-plrow`：52 高 / 36 封面 / 12.5 标题）。
class _PlaylistRow extends ConsumerWidget {
  const _PlaylistRow({required this.playlist, this.collected = false});

  final MusicPlaylist playlist;
  final bool collected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final p = playlist;
    final meta = p.author == null || p.author!.isEmpty
        ? l10n.musicCountSongs(p.trackCount)
        : l10n.musicPlLibraryCardMeta(p.author!, p.trackCount);
    return Semantics(
      button: true,
      label: collected ? l10n.musicPlLibraryAriaCollected(p.name) : l10n.musicPlLibraryAriaPlaylist(p.name),
      child: InkWell(
        onTap: () => GoRouter.of(context).go('/music/playlist/${p.id}'),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            child: Row(
              children: [
                _PlaylistCover(playlist: p, size: 36, radius: 8, collected: collected),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w600, color: palette.ink),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 15, color: palette.mut.withValues(alpha: 0.55)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 未登录：登录 CTA 卡（不摆空态图，N41 四态之一）。
class _LoginCta extends ConsumerWidget {
  const _LoginCta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final mobile = context.isMobile;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: mobile ? 42 : 48),
        decoration: BoxDecoration(
          color: palette.card,
          border: Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(mobile ? AppMetrics.radiusCardLg : 14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.logOut, size: mobile ? 20 : 22, color: palette.mut),
            const SizedBox(height: 9),
            Text(
              l10n.musicPlLibraryLoginTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: mobile ? AppFont.px13 : AppFont.px14,
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.musicPlLibraryLoginDesc,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: mobile ? AppFont.px11 : AppFont.px11_5, height: 1.6, color: palette.mut),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: l10n.musicPlLibraryLoginAction,
              variant: AppButtonVariant.primary,
              height: mobile ? 32 : 30,
              onTap: () => ref.read(musicUiProvider.notifier).openLogin(ref.read(musicAccountProvider).cur),
            ),
          ],
        ),
      ),
    );
  }
}

/// 整页失败态（N28 魔法阵）：重试 / 切本地两个出口。
class _FailPage extends ConsumerWidget {
  const _FailPage({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final hhmm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Center(
      child: FailMagicCircle(
        reason: l10n.musicFailReasonNetwork,
        lastSyncLabel: l10n.musicFailLastSync(hhmm),
        queueHint: l10n.musicFailQueueHint(ref.watch(playerProvider).queue.length),
        retryLabel: l10n.musicRetry,
        onRetry: onRetry,
        switchLocalLabel: l10n.musicFailSwitchLocal,
        onSwitchLocal: () => GoRouter.of(context).go('/music/local'),
      ),
    );
  }
}

/// 加载骨架：与真内容同布局（N27：系统歌单横卡 + 8 + 4 张 80 高卡片），无 CLS。
class PlaylistLibrarySkeleton extends StatelessWidget {
  const PlaylistLibrarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final mobile = context.isMobile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBox(height: mobile ? 84 : 92, radius: mobile ? AppMetrics.radiusCardLg : 14),
        SizedBox(height: mobile ? 20 : 22),
        const SkeletonBox(width: 110, height: 12),
        const SizedBox(height: 10),
        if (mobile)
          for (var i = 0; i < 3; i++) ...[
            const SkeletonBox(height: 52, radius: AppMetrics.radiusCard),
            const SizedBox(height: 4),
          ]
        else
          const _CardSkeletonGrid(count: 8),
        SizedBox(height: mobile ? 16 : 20),
        const SkeletonBox(width: 110, height: 12),
        const SizedBox(height: 10),
        if (mobile)
          for (var i = 0; i < 2; i++) ...[
            const SkeletonBox(height: 52, radius: AppMetrics.radiusCard),
            const SizedBox(height: 4),
          ]
        else
          const _CardSkeletonGrid(count: 4),
      ],
    );
  }
}

class _CardSkeletonGrid extends StatelessWidget {
  const _CardSkeletonGrid({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth < AppMetrics.musicNarrowBreakpoint ? 2 : 4;
        return Column(
          children: [
            for (var i = 0; i < count; i += cols) ...[
              Row(
                children: [
                  for (var k = i; k < i + cols; k++) ...[
                    if (k > i) const SizedBox(width: 12),
                    Expanded(
                      child: k < count
                          ? const SkeletonBox(height: 80, radius: AppMetrics.radiusCardLg)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}
