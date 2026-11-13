import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_providers.dart';
import '../../controller/music_player.dart';
import '../../controller/music_session.dart';
import '../../data/music_repository.dart';
import '../../domain/music_models.dart';
import '../widgets/fail_magic.dart';
import '../widgets/music_scroll_memory.dart';
import '../widgets/music_shared.dart';
import '../widgets/remote_cover_image.dart';
import '../widgets/music_state_box.dart';
import '../widgets/song_row.dart';

/// 发现页（N21/N37 顺序固定：推荐栏 → 推荐歌单 → 官方榜单 → 推荐歌曲）。
///
/// 三态（N27/N28/N29）：
/// · 首次加载 → 按真实布局骨架（无 CLS）；
/// · 任一分区**首次加载失败**（无旧值）→ 整页 FailMagicCircle（N28，测试口径）；
/// · 刷新失败但已有旧数据（value）→ 顶部横幅 + 旧内容保留（N29）。
class DiscoverView extends ConsumerWidget {
  const DiscoverView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // 🔴 未导入任何音乐源：不发起任何数据请求，直接给导入引导（与漫画在线模块同交互）。
    if (ref.watch(availableMusicPlatformsProvider).isEmpty) {
      return const MusicNoSourcePrompt();
    }
    final recs = ref.watch(recCardsProvider);
    final playlists = ref.watch(recPlaylistsProvider);
    final charts = ref.watch(chartsProvider);
    final daily = ref.watch(dailySongsProvider);
    final logged = ref.watch(musicAccountProvider.select((a) => a.logged));

    final sections = [recs, playlists, charts, daily];
    // N28：任一分区首次加载失败（没有旧值可回退）→ 整页魔法阵。
    final firstLoadFail = sections.any((v) => v.hasError && v.value == null);
    if (firstLoadFail) {
      return _FailPage(reason: l10n.musicFailReasonNetwork);
    }

    final anyError = sections.any((v) => v.hasError);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (anyError)
          ErrorBanner(
            compact: true,
            error: sections.firstWhere((v) => v.hasError).error,
            onRetry: () {
              // N29：重试只失效失败分区；Riverpod 重载会带上旧值（copyWithPrevious），
              // 已有数据的分区不会闪骨架。
              ref.invalidate(recCardsProvider);
              ref.invalidate(recPlaylistsProvider);
              ref.invalidate(chartsProvider);
              ref.invalidate(dailySongsProvider);
            },
            showStaleHint: true,
          ),
        Expanded(
          // N03：切视图后回来恢复滚动位置。
          child: MusicScrollMemory(
            storageKey: 'discover',
            builder: (context, controller) => SingleChildScrollView(
              controller: controller,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 6),
                  _RecSection(recs: recs),
                  MusicSectionHeader(
                    title: l10n.musicSecRecPlaylists,
                    more: true,
                    onRefresh: () => _refreshToast(context, ref, () => ref.invalidate(recPlaylistsProvider)),
                  ),
                  _PlaylistTiles(playlists: playlists),
                  MusicSectionHeader(
                    title: l10n.musicSecCharts,
                    more: true,
                    onRefresh: () => _refreshToast(context, ref, () => ref.invalidate(chartsProvider)),
                  ),
                  _ChartGrid(charts: charts),
                  MusicSectionHeader(
                    title: l10n.musicSecDaily,
                    trailing: logged && (daily.value?.isNotEmpty ?? false)
                        ? AppButton(
                            label: l10n.musicPlayAll,
                            icon: LucideIcons.play,
                            variant: AppButtonVariant.ghost,
                            height: 26,
                            fontSize: AppFont.px11_5,
                            onTap: () {
                              final songs = daily.value!;
                              ref.read(playerProvider.notifier).playAll(songs, title: l10n.musicSecDaily);
                              showAppToast(context, l10n.musicPlayingNow(songs.first.title), tone: ToastTone.good);
                            },
                          )
                        : null,
                  ),
                  logged ? _DailySection(daily: daily) : MusicLoginCtaCard(cur: ref.watch(musicAccountProvider).cur),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// N22「换一批」：轻提示 700ms 收尾，不做 loading 禁用、不清旧内容。
  void _refreshToast(BuildContext context, WidgetRef ref, VoidCallback invalidate) {
    final l10n = AppLocalizations.of(context);
    showAppToast(context, l10n.musicRefreshing);
    invalidate();
    Timer(const Duration(milliseconds: 700), () {
      if (context.mounted) showAppToast(context, l10n.musicRefreshed, tone: ToastTone.good);
    });
  }
}

/// N28 整页失败态（断线唱片魔法阵）：重试 / 切本地 两个出口。
class _FailPage extends ConsumerWidget {
  const _FailPage({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return Center(
      child: FailMagicCircle(
        reason: reason,
        lastSyncLabel: l10n.musicFailLastSync('$hh:$mm'),
        queueHint: l10n.musicFailQueueHint(ref.watch(playerProvider).queue.length),
        retryLabel: l10n.musicRetry,
        onRetry: () {
          ref.invalidate(recCardsProvider);
          ref.invalidate(recPlaylistsProvider);
          ref.invalidate(chartsProvider);
          ref.invalidate(dailySongsProvider);
        },
        switchLocalLabel: l10n.musicFailSwitchLocal,
        onSwitchLocal: () => GoRouter.of(context).go('/music/local'),
        viewStatusLabel: l10n.musicFailViewStatus,
        onViewStatus: () => _showServiceStatus(context, ref, '$hh:$mm'),
      ),
    );
  }

  /// N28 第三个出口：展示音源连接 / 缓存 / 上次同步（演示音源没有真实服务可探活）。
  void _showServiceStatus(BuildContext context, WidgetRef ref, String syncAt) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final account = ref.read(musicAccountProvider);
    final queueCount = ref.read(playerProvider).queue.length;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(fontSize: AppFont.px11_5, color: palette.mut),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: AppFont.px11_5, color: palette.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    showAppDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: l10n.musicServiceStatusTitle,
        icon: LucideIcons.activity,
        width: 340,
        onClose: () => Navigator.of(ctx).pop(),
        actions: [
          AppButton(
            label: l10n.musicServiceStatusAck,
            variant: AppButtonVariant.primary,
            onTap: () => Navigator.of(ctx).pop(),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(l10n.musicServiceStatusSource, platformBrands[account.cur]!.label),
            row(l10n.musicServiceStatusConnection, l10n.musicServiceStatusOffline),
            row(l10n.musicServiceStatusQueue, '$queueCount'),
            row(l10n.musicServiceStatusSync, syncAt),
          ],
        ),
      ),
    );
  }
}

// ── 推荐栏（N21/N37：竖卡横向滚动 + 桌面 hover 箭头按组宽平滑滚动）─────────────

class _RecSection extends ConsumerWidget {
  const _RecSection({required this.recs});

  final AsyncValue<List<MusicRecCard>> recs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = recs.value;
    if (data == null) return const _RecBarSkeleton();
    return _RecBar(cards: data);
  }
}

class _RecBar extends StatefulWidget {
  const _RecBar({required this.cards});

  final List<MusicRecCard> cards;

  @override
  State<_RecBar> createState() => _RecBarState();
}

class _RecBarState extends State<_RecBar> {
  final _ctrl = ScrollController();
  bool _hover = false;

  static const _gap = 14.0;
  static const _height = 246.0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 桌面箭头：按「一组」宽度平滑滚动（设计稿 scrollBy(clientWidth * .78)）。
  void _scroll(int dir) {
    if (!_ctrl.hasClients) return;
    final target = (_ctrl.offset + dir * _ctrl.position.viewportDimension * 0.78).clamp(
      0.0,
      _ctrl.position.maxScrollExtent,
    );
    _ctrl.animateTo(target, duration: AppMotion.pageSwitch, curve: AppMotion.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        // 箭头现在是内嵌定位，不需要出血；Clip.none 反而会让悬停阴影溢到相邻区块。
        clipBehavior: Clip.hardEdge,
        children: [
          // 只有 9 张定宽卡：用 Row + 单一横向滚动容器（非懒加载，全部可命中）。
          SingleChildScrollView(
            key: const ValueKey('rec-bar'),
            controller: _ctrl,
            scrollDirection: Axis.horizontal,
            // M17 对齐口径：首卡与分区标题左对齐，本页不再做负 margin 出血。
            padding: EdgeInsets.zero,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, card) in widget.cards.indexed) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  _RecCard(card: card),
                ],
              ],
            ),
          ),
          // 箭头只在 hover 时出现，不常驻抢视线（N37）。
          if (_hover) ...[
            Positioned(
              // 箭头完全落在推荐栏内部（不再用负偏移出血）：外层滚动容器会裁剪
              // 超出边界的子件，负偏移时左右各被切掉一半（用户实测「图标被截断」）。
              left: 8,
              top: _height / 2 - 16,
              child: _NavArrow(
                key: const ValueKey('music-rec-prev'),
                icon: LucideIcons.chevronLeft,
                onTap: () => _scroll(-1),
              ),
            ),
            Positioned(
              right: 8,
              top: _height / 2 - 16,
              child: _NavArrow(
                key: const ValueKey('music-rec-next'),
                icon: LucideIcons.chevronRight,
                onTap: () => _scroll(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // 32×32 圆形按钮 + 投影：Material 的 elevation 在圆形 shape 下会裁切阴影，
    // 这里用 Container + BoxShadow，保证图标视觉不被边框吃掉。
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: palette.panel,
            shape: BoxShape.circle,
            border: Border.all(color: palette.line2),
            boxShadow: [
              BoxShadow(color: palette.shadow.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: Icon(icon, size: 18, color: palette.ink2),
        ),
      ),
    );
  }
}

class _RecCard extends ConsumerWidget {
  const _RecCard({required this.card});

  final MusicRecCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final mobile = context.isMobile;
    // 设计稿尺寸：桌面 186×246，移动 140×196（`.m-rc`）。
    final width = mobile ? 140.0 : 186.0;
    final height = mobile ? 196.0 : 246.0;
    final radius = mobile ? AppMetrics.radiusCard : AppMetrics.radiusCardLg;
    final captionHeight = mobile ? 52.0 : 62.0;
    final glyphSize = mobile ? 58.0 : 74.0;
    final titleSize = mobile ? AppFont.px11_5 : AppFont.px13;
    return Semantics(
      label: l10n.musicRecCardAria(card.title),
      button: true,
      // 测试锚点：发现页 9 张推荐卡（N37）。
      child: Material(
        key: const ValueKey('rec-card'),
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: () async {
            var songs = <MusicSong>[];
            if (card.playlistId != null) {
              try {
                final detail = await ref.read(
                  sourceDetailProvider((MusicSourceKind.playlist, card.playlistId!)).future,
                );
                songs = detail.songs;
              } on MusicRepositoryException {
                if (context.mounted) showAppToast(context, l10n.musicBannerFail, tone: ToastTone.bad);
                return;
              }
            }
            if (songs.isEmpty || !context.mounted) return;
            ref.read(playerProvider.notifier).playAll(songs, title: card.title);
            showAppToast(context, l10n.musicRecCardAria(card.title), tone: ToastTone.good);
          },
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: AppPalette.of(context).shadow.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 插画区：有真实封面就铺图，没有才退回种子渐变 + 同心圆装饰。
                Expanded(
                  child: SeedGradient(
                    seed: card.seed,
                    hue: card.hue,
                    child: Stack(
                      children: [
                        if (card.coverUrl != null && card.coverUrl!.isNotEmpty)
                          Positioned.fill(
                            child: RemoteCoverImage(url: card.coverUrl!, fit: BoxFit.cover),
                          ),
                        Positioned(
                          right: mobile ? -8 : -12,
                          bottom: mobile ? -12 : -16,
                          child: Icon(card.icon, size: glyphSize, color: Colors.white.withValues(alpha: 0.18)),
                        ),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: Row(
                            children: [
                              Icon(card.icon, size: mobile ? 11 : 13, color: Colors.white),
                              SizedBox(width: mobile ? 4 : 6),
                              Text(
                                card.title,
                                style: TextStyle(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  shadows: const [Shadow(color: Color(0x80000000), blurRadius: 6)],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Center(
                          child: Container(
                            width: 118,
                            height: 118,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              boxShadow: [
                                BoxShadow(color: Colors.white.withValues(alpha: 0.05), spreadRadius: 24),
                                BoxShadow(color: Colors.white.withValues(alpha: 0.028), spreadRadius: 48),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 彩色说明带（recs[].tint 属内容色）。
                Container(
                  height: captionHeight,
                  padding: EdgeInsets.symmetric(horizontal: mobile ? 10 : 12, vertical: mobile ? 7 : 10),
                  color: Color.alphaBlend(card.tint.withValues(alpha: 0.82), palette.vinylBase),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    card.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: mobile ? AppFont.px10 : AppFont.px12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.45,
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

class _RecBarSkeleton extends StatelessWidget {
  const _RecBarSkeleton();

  @override
  Widget build(BuildContext context) {
    // N27：骨架按真实布局占位（186×246 竖卡），不产生 CLS。
    return SizedBox(
      height: 246,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            for (var i = 0; i < 6; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              const SkeletonBox(width: 186, height: 246, radius: AppMetrics.radiusCardLg),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 分区标题 / 歌单瓦片（发现页与歌单库共用）─────────────────────────────────

/// 分区标题（app.css `.sec-h`）：h3 + 可选右箭头 + 刷新圆钮。
class MusicSectionHeader extends StatelessWidget {
  const MusicSectionHeader({super.key, required this.title, this.more = false, this.onRefresh, this.trailing});

  final String title;
  final bool more;
  final VoidCallback? onRefresh;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 11),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w700, color: palette.ink),
          ),
          if (more) ...[const SizedBox(width: 2), Icon(LucideIcons.chevronRight, size: 13, color: palette.mut)],
          const Spacer(),
          ?trailing,
          if (onRefresh != null)
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                onPressed: onRefresh,
                icon: Icon(LucideIcons.refreshCw, size: 15, color: palette.mut),
                tooltip: AppLocalizations.of(context).musicRefreshBatch,
                hoverColor: palette.hi,
                splashColor: Colors.transparent,
              ),
            ),
        ],
      ),
    );
  }
}

/// 歌单瓦片（app.css `.tile`）：封面 + 播放量角标 + 两行标题 + 描述行。
class MusicPlaylistTile extends ConsumerWidget {
  const MusicPlaylistTile({super.key, required this.playlist, this.onPlayAll});

  final MusicPlaylist playlist;

  /// hover 播放整组；null = 只进入详情。
  final void Function(MusicPlaylist)? onPlayAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final hoverPlay = onPlayAll != null;
    // 播放量只在接口给出**数值**时显示，并按当前语言格式化（万 / 亿）。
    // 接口没给（或只给了平台自带的 "1.2w" 串）就不画角标 —— 不显示原始长数字，
    // 也不把英文缩略串直接贴到界面上。
    final playCount = playlist.playCountValue == null ? null : formatMusicPlayCount(l10n, playlist.playCountValue!);
    return Semantics(
      label: playCount == null ? playlist.name : l10n.musicPlaysAria(playCount),
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
          onTap: () => GoRouter.of(context).go('/music/playlist/${playlist.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: SeedCover(
                        seed: playlist.name,
                        imageUrl: playlist.coverUrl,
                        radius: AppMetrics.radiusCardLg,
                      ),
                    ),
                    // 播放量角标（左上）；没有数值时不渲染。
                    if (playCount != null)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          height: 19,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          decoration: BoxDecoration(
                            color: palette.coverScrim,
                            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.headphones, size: 10, color: palette.coverInk),
                              const SizedBox(width: 3),
                              Text(
                                playCount,
                                style: TextStyle(
                                  fontSize: AppFont.px10,
                                  fontWeight: FontWeight.w600,
                                  color: palette.coverInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // 红心歌单徽标（设计稿 `.t-badge`：我的收藏，仅 p0）。
                    if (playlist.special)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          decoration: BoxDecoration(
                            color: palette.coverScrim,
                            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.heart, size: 10, color: palette.coverInk),
                              const SizedBox(width: 4),
                              Text(
                                l10n.musicMyCollectionBadge,
                                style: TextStyle(
                                  fontSize: AppFont.px9_5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.coverInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // hover 播放钮（右下浮出）。
                    if (hoverPlay)
                      Positioned(right: 9, bottom: 9, child: _HoverPlayFab(onTap: () => onPlayAll!(playlist))),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                playlist.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFont.px12_5,
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                  height: 1.4,
                ),
              ),
              if (playlist.description != null) ...[
                const SizedBox(height: 1),
                Text(
                  playlist.description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HoverPlayFab extends StatefulWidget {
  const _HoverPlayFab({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_HoverPlayFab> createState() => _HoverPlayFabState();
}

class _HoverPlayFabState extends State<_HoverPlayFab> {
  bool _tileHover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _tileHover = true),
      onExit: (_) => setState(() => _tileHover = false),
      child: AnimatedOpacity(
        duration: AppMotion.hover,
        opacity: _tileHover ? 1 : 0,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.acc,
              boxShadow: [
                BoxShadow(color: palette.shadow.withValues(alpha: 0.5), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: Icon(LucideIcons.play, size: 14, color: palette.onAcc),
          ),
        ),
      ),
    );
  }
}

class _PlaylistTiles extends ConsumerWidget {
  const _PlaylistTiles({required this.playlists});

  final AsyncValue<List<MusicPlaylist>> playlists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = playlists.value;
    if (data == null) {
      // N27：6 个正方形瓦片骨架（与真内容同布局，无 CLS）。
      return LayoutBuilder(
        builder: (context, box) {
          final cols = _colsOf(context);
          return MusicTileGrid(cols: cols, children: [for (var i = 0; i < 6; i++) const SkeletonCoverTile()]);
        },
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        // 栅格自适应列数（AGENTS §4）：桌面内容宽下约 6 列，窄屏自动降为 2–3 列。
        final cols = _colsOf(context);
        return MusicTileGrid(
          cols: cols,
          children: [
            for (final p in data) MusicPlaylistTile(playlist: p, onPlayAll: (pl) => _playPlaylist(context, ref, pl)),
          ],
        );
      },
    );
  }

  /// 设计稿 N37/N32 的列数：lg 6 / md 4 / sm 3 / 移动 2。
  static int _colsOf(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w <= AppMetrics.breakpoint) return 2;
    if (w >= AppMetrics.musicIslandBreakpoint) return 6;
    if (w >= AppMetrics.musicNarrowBreakpoint) return 4;
    return 3;
  }

  Future<void> _playPlaylist(BuildContext context, WidgetRef ref, MusicPlaylist p) async {
    try {
      final detail = await ref.read(sourceDetailProvider((MusicSourceKind.playlist, p.id)).future);
      if (!context.mounted) return;
      ref.read(playerProvider.notifier).playAll(detail.songs, title: p.name);
      showAppToast(context, AppLocalizations.of(context).musicPlayingNow(p.name), tone: ToastTone.good);
    } on MusicRepositoryException {
      if (context.mounted) {
        showAppToast(context, AppLocalizations.of(context).musicBannerFail, tone: ToastTone.bad);
      }
    }
  }
}

/// 瓦片网格（Column + Row 内在高度排版：瓦片高度 = 封面宽 + 文字，天然无溢出；
/// 歌单库视图复用）。
class MusicTileGrid extends StatelessWidget {
  const MusicTileGrid({super.key, required this.cols, required this.children});

  final int cols;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <List<Widget>>[];
    for (var i = 0; i < children.length; i += cols) {
      final end = math.min(i + cols, children.length);
      rows.add(children.sublist(i, end));
    }
    return Column(
      children: [
        for (final row in rows) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, cell) in row.indexed) ...[if (i > 0) const SizedBox(width: 14), Expanded(child: cell)],
              // 末行补位，保证各列宽度一致。
              for (var k = row.length; k < cols; k++) ...[
                const SizedBox(width: 14),
                const Expanded(child: SizedBox.shrink()),
              ],
            ],
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

/// 骨架瓦片（正方形封面 + 两行文字条）。
class SkeletonCoverTile extends StatelessWidget {
  const SkeletonCoverTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: SkeletonBox(height: double.infinity, radius: AppMetrics.radiusCardLg),
        ),
        SizedBox(height: 8),
        SkeletonBox(height: 12),
        SizedBox(height: 4),
        SkeletonBox(width: 96, height: 10),
      ],
    );
  }
}

// ── 官方榜单（N38：横向卡 = 榜单名+更新时间 / 叠层封面 + Top3 + 趋势标记）──────

class _ChartGrid extends ConsumerWidget {
  const _ChartGrid({required this.charts});

  final AsyncValue<List<MusicChart>> charts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = charts.value;
    if (data == null) {
      return const _ChartSkeleton();
    }
    // N38：桌面 2 列 × 3 行（窄屏 1 列），行高取封面内在高度，天然无溢出。
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 620 ? 2 : 1;
        return Column(
          children: [
            for (var i = 0; i < data.length; i += cols) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var k = i; k < math.min(i + cols, data.length); k++) ...[
                    if (k > i) const SizedBox(width: 14),
                    Expanded(child: _ChartCard(chart: data[k])),
                  ],
                ],
              ),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }
}

class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 620 ? 2 : 1;
        return Column(
          children: [
            for (var i = 0; i < 6; i += cols) ...[
              Row(
                children: [
                  for (var k = i; k < math.min(i + cols, 6); k++) ...[
                    if (k > i) const SizedBox(width: 14),
                    const Expanded(child: SkeletonBox(height: 150, radius: AppMetrics.radiusCardLg)),
                  ],
                ],
              ),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.chart});

  final MusicChart chart;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
        side: BorderSide(color: palette.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
        onTap: () => GoRouter.of(context).go('/music/chart/${chart.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      chart.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                  ),
                  Text(
                    chart.updateMeta,
                    style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              // 内容行固定 92（封面基准）；卡片放滚动容器里，不能用 Expanded 撑。
              SizedBox(
                height: 92,
                child: Row(
                  children: [
                    // 叠层封面（设计稿 .ch-art）。
                    SizedBox(
                      width: 92,
                      height: 92,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            left: 13,
                            top: 0,
                            right: 0,
                            bottom: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.hi,
                                border: Border.all(color: palette.line2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            left: 7,
                            right: 6,
                            bottom: 3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.hi,
                                border: Border.all(color: palette.line2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: SeedCover(seed: chart.seed, imageUrl: chart.coverUrl, radius: 8),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (final (i, e) in chart.top.indexed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1.5),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 12,
                                    child: Text(
                                      '${i + 1}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: AppFont.px11,
                                        color: palette.mut,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      '${e.title} – ${e.artist}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: AppFont.px12, color: palette.ink),
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  _TrendMark(trend: e.trend),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 趋势标记（N38：红 ▲ 上升 / 绿「新」/ 灰「–」持平；形状+颜色+语义三重表意）。
class _TrendMark extends StatelessWidget {
  const _TrendMark({required this.trend});

  final ChartTrend trend;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final (icon, color, label, glyph) = switch (trend) {
      // 「新」取自 ARB 词条首字，避免硬编码中文。
      ChartTrend.newEntry => (null, palette.good, l10n.musicTrendNew, l10n.musicTrendNew.substring(0, 1)),
      ChartTrend.up => (LucideIcons.chevronUp, palette.bad, l10n.musicTrendUp, null),
      ChartTrend.flat => (LucideIcons.minus, palette.mut, l10n.musicTrendFlat, null),
    };
    return Semantics(
      label: label,
      child: SizedBox(
        width: 14,
        child: Center(
          child: glyph != null
              ? Text(
                  glyph,
                  style: TextStyle(fontSize: AppFont.px10, fontWeight: FontWeight.w700, color: color),
                )
              : Icon(icon, size: 11, color: color),
        ),
      ),
    );
  }
}

// ── 推荐歌曲 / 登录 CTA ──────────────────────────────────────────────────────

class _DailySection extends ConsumerWidget {
  const _DailySection({required this.daily});

  final AsyncValue<List<MusicSong>> daily;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = daily.value;
    if (data == null) return const _DailySkeleton();
    if (data.isEmpty) return const SizedBox(height: 8);
    return MusicSongTable(
      songs: data,
      scrollable: false,
      showAlbum: true,
      queueTitle: AppLocalizations.of(context).musicSecDaily,
    );
  }
}

class _DailySkeleton extends StatelessWidget {
  const _DailySkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 4; i++)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 7, horizontal: 10),
            child: Row(
              children: [
                SkeletonBox(width: 22, height: 12),
                SizedBox(width: 8),
                Expanded(child: SkeletonBox(height: 12)),
                SizedBox(width: 24),
                SkeletonBox(width: 40, height: 12),
              ],
            ),
          ),
      ],
    );
  }
}

/// 未登录 CTA 卡（N24：登录卡而不是空态图）。
class MusicLoginCtaCard extends ConsumerWidget {
  const MusicLoginCtaCard({super.key, required this.cur});

  final MusicPlatform cur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: palette.accSoft,
              borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
            ),
            child: Icon(LucideIcons.headphones, size: 22, color: palette.acc),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.musicDailyLoginTitle,
                  style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.musicDailyLoginDesc,
                  style: TextStyle(fontSize: AppFont.px11_5, color: palette.mut),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: l10n.musicLoginAction,
            onTap: () => ref.read(musicUiProvider.notifier).openLogin(cur),
            variant: AppButtonVariant.primary,
            height: 32,
          ),
        ],
      ),
    );
  }
}

// ── 局部失败横幅（N29）由 shared ErrorBanner 承担；三态辅助在此收口 ─────────────

/// 分区三态渲染辅助：有旧值先画旧值（N29），无旧值 loading → 骨架。
Widget musicSectionOf<T>(AsyncValue<T> value, {required Widget skeleton, required Widget Function(T data) build}) {
  final stale = value.value;
  if (stale != null) return build(stale);
  if (value.hasError) return const SizedBox.shrink();
  return skeleton;
}
