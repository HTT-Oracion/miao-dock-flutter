import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_playlist_library.dart';
import '../../controller/music_providers.dart';
import '../../controller/music_player.dart';
import '../../controller/music_session.dart';
import '../../data/music_repository.dart';
import '../../domain/music_models.dart';
import '../widgets/fail_magic.dart';
import '../widgets/music_shared.dart';
import '../widgets/song_row.dart';
import 'discover_view.dart';

/// 收藏态统一由 [playlistLibraryProvider] 持有（N43）：
/// 收藏歌单改的是 `subscribed` 语义位（取消订阅后从收藏分组消失），
/// 自建歌单 / 榜单只记本地回执。这里不再另建一份 Set，避免两处状态打架。

/// 详情页（N24）：歌单 / 榜单 / 每日推荐共用一套布局。
///
/// hero 大封面 + 名称 + 曲数·来源 + 描述；操作区只有「播放全部」与「收藏」两个按钮。
/// 曲目表：表头 + 歌曲行，当前播放行 ♪ 高亮联动 playerProvider。
class MusicDetailScreen extends ConsumerWidget {
  const MusicDetailScreen({super.key, required this.kind, required this.id});

  final MusicSourceKind kind;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final detail = ref.watch(sourceDetailProvider((kind, id)));
    final player = ref.watch(playerProvider);
    final library = ref.watch(playlistLibraryProvider);
    final mobile = context.isMobile;

    // 每日推荐未登录 → 登录 CTA（与发现页同卡）。
    if (kind == MusicSourceKind.daily && !ref.watch(musicAccountProvider.select((a) => a.logged))) {
      return ColoredBox(
        color: palette.bg,
        child: Center(child: MusicLoginCtaCard(cur: ref.watch(musicAccountProvider).cur)),
      );
    }

    // 详情页是独立路由屏（B 端集成），与 MusicScreen 一样自带内容边距。
    // 背景必须自己铺：嵌在分支 Navigator 里时透明底会把下层歌单列表透出来。
    return ColoredBox(
      color: palette.bg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          mobile ? 16 : AppMetrics.contentPadding,
          mobile ? 14 : 6,
          mobile ? 16 : AppMetrics.contentPadding,
          mobile ? 4 : 6,
        ),
        child: detail.when(
          loading: () => const _DetailSkeleton(),
          error: (e, _) => Center(
            child: FailMagicCircle(
              reason: e is MusicRepositoryException ? l10n.musicFailReasonNetwork : l10n.musicFailTitle,
              lastSyncLabel: l10n.musicFailLastSync(_hhmm()),
              queueHint: l10n.musicFailQueueHint(player.queue.length),
              retryLabel: l10n.musicRetry,
              onRetry: () => ref.invalidate(sourceDetailProvider((kind, id))),
            ),
          ),
          data: (d) {
            final saved = library.isSaved(d.meta);
            // 面包屑第三级：数据到位后再写，避免先挂一个空名。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) ref.read(musicDetailCrumbProvider.notifier).set(d.meta.id, d.meta.name);
            });
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // N18/M18：详情顶部返回栏 —— 桌面「返回我的歌单」+ 类型胶囊，
                // 移动端返回箭头已在壳层顶栏（M18），这里只留类型胶囊。
                if (kind != MusicSourceKind.daily) _DetailBackBar(kind: kind, meta: d.meta, mobile: mobile),
                _Hero(
                  kind: kind,
                  meta: d.meta,
                  songsCount: d.meta.trackCount > 0 ? d.meta.trackCount : d.songs.length,
                  mobile: mobile,
                  isCollected: saved,
                  onPlayAll: () {
                    // N24/N10：只有从「我喜欢的音乐」播放才允许经过心动模式档。
                    ref
                        .read(playerProvider.notifier)
                        .playAll(
                          d.songs,
                          title: d.meta.name,
                          fromLiked: d.meta.special && kind == MusicSourceKind.playlist,
                        );
                    showAppToast(context, l10n.musicPlayingNow(d.meta.name), tone: ToastTone.good);
                  },
                  onToggleCollect: () {
                    // N43：收藏歌单取消订阅后从收藏分组移除，可再点一次加回；
                    // 自建歌单 / 榜单只切本地收藏回执。
                    final notifier = ref.read(playlistLibraryProvider.notifier);
                    if (d.meta.subscribed) {
                      notifier.toggleSubscribe(d.meta.id);
                    } else {
                      notifier.toggleSaved(d.meta.id);
                    }
                    showAppToast(
                      context,
                      saved
                          ? (d.meta.subscribed ? l10n.musicPlUnsubscribe : l10n.musicCollectOff)
                          : (d.meta.subscribed ? l10n.musicPlSubscribe(d.meta.name) : l10n.musicCollectDone),
                      tone: saved ? ToastTone.info : ToastTone.good,
                    );
                  },
                ),
                // 移动端不放表头（设计稿只有分隔线 + 行），桌面保留专辑 / 音质 / 时长表头。
                if (mobile) Container(height: 1, color: palette.line) else const _TableHead(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: d.songs.length,
                    itemBuilder: (_, i) {
                      final s = d.songs[i];
                      return SongRow(
                        song: s,
                        index: i,
                        showAlbum: true,
                        current: player.current?.id == s.id,
                        liked: player.likedIds.contains(s.id),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _hhmm() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

/// 详情顶部返回栏（桌面 `app.css .pl-backbar`）：返回我的歌单 + 类型胶囊。
///
/// 移动端顶栏返回箭头由壳层渲染（M18：歌单库是一级页，只有详情才出现箭头），
/// 这里只保留类型胶囊，避免出现两个返回入口。
class _DetailBackBar extends StatelessWidget {
  const _DetailBackBar({required this.kind, required this.meta, required this.mobile});

  final MusicSourceKind kind;
  final MusicPlaylist meta;
  final bool mobile;

  String _chip(AppLocalizations l10n) {
    if (kind == MusicSourceKind.chart) return l10n.musicPlChipChart;
    if (kind == MusicSourceKind.daily) return l10n.musicPlChipDaily;
    if (meta.special) return l10n.musicPlChipLiked;
    if (meta.subscribed) return l10n.musicPlChipCollected;
    return l10n.musicPlChipPlaylist;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    // 🔴 不要用 Container(alignment: ...)：带 alignment 的 Container 会撑满有界宽度，
    // 胶囊会变成一条整行横条（移动端实测）。高度 + padding 已足够让它收缩到内容宽。
    final chip = Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          _chip(l10n),
          style: TextStyle(fontSize: AppFont.px10_5, color: palette.ink2),
        ),
      ),
    );
    if (mobile) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Align(alignment: Alignment.centerLeft, child: chip),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // 链接样式按钮只画文字（buttons.dart 的 link 变体不渲染 icon），
          // 设计稿 `.pl-backbar` 是「← + 文案」，这里自己排一行。
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => GoRouter.of(context).go('/music/playlist'),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 26,
                child: Row(
                  children: [
                    Icon(LucideIcons.arrowLeft, size: 12, color: palette.accInk),
                    const SizedBox(width: 5),
                    Text(
                      l10n.musicPlBack,
                      style: TextStyle(fontSize: AppFont.px12, color: palette.accInk),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          chip,
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.kind,
    required this.meta,
    required this.songsCount,
    required this.mobile,
    required this.isCollected,
    required this.onPlayAll,
    required this.onToggleCollect,
  });

  final MusicSourceKind kind;
  final MusicPlaylist meta;
  final int songsCount;
  final bool mobile;
  final bool isCollected;
  final VoidCallback onPlayAll;
  final VoidCallback onToggleCollect;

  /// hero 上方的小标签：设计稿用英文眉标（PLAYLIST / CHART / LIKED / COLLECTED）。
  String _kicker(AppLocalizations l10n) {
    if (kind == MusicSourceKind.daily) return l10n.musicKickerDaily;
    if (kind == MusicSourceKind.chart) return l10n.musicKickerChart;
    if (meta.special) return l10n.musicKickerLiked;
    if (meta.subscribed) return l10n.musicKickerCollected;
    return l10n.musicKickerTokenPlaylist;
  }

  /// 来源行：收藏歌单显示「作者 · 已收藏」（N43），其余沿用平台语义。
  String _source(AppLocalizations l10n) {
    if (kind == MusicSourceKind.daily) return l10n.musicDetailSourceDaily;
    if (kind == MusicSourceKind.chart) return l10n.musicDetailSourceChart;
    if (meta.special) return l10n.musicDetailSourceLiked;
    if (meta.subscribed) {
      final author = meta.author;
      return author == null || author.isEmpty ? l10n.musicDetailSourcePlaylist : l10n.musicPlSourceCollected(author);
    }
    return l10n.musicDetailSourcePlaylist;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final desc = meta.description;
    final hasDesc = desc != null && desc.isNotEmpty;
    // 设计稿：桌面 p-meta 是「曲数 · 描述 · 来源」，移动 m-plhead .meta 只有「曲数 · 描述」
    // （来源行在移动端并入类型胶囊与 COLLECTED 眉标，避免单行截断）。
    final metaLine = mobile
        ? (hasDesc ? l10n.musicDetailMetaCompact('$songsCount', desc) : l10n.musicCountSongs(songsCount))
        : (hasDesc
              ? l10n.musicDetailMeta('$songsCount', desc, _source(l10n))
              : l10n.musicDetailMetaSimple('$songsCount', _source(l10n)));

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _kicker(l10n),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: mobile ? AppFont.px9 : AppFont.px9_5,
            letterSpacing: 1.2,
            color: palette.mut,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          meta.name,
          maxLines: mobile ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: mobile ? AppFont.px17 : AppFont.px26,
            fontWeight: FontWeight.w800,
            color: palette.ink,
            height: 1.2,
            letterSpacing: mobile ? 0 : -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          metaLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: mobile ? AppFont.px10_5 : AppFont.px11_5, color: palette.mut),
        ),
      ],
    );

    final play = AppButton(
      label: l10n.musicPlayAll,
      icon: LucideIcons.play,
      variant: AppButtonVariant.primary,
      height: mobile ? 34 : 32,
      width: mobile ? double.infinity : null,
      onTap: onPlayAll,
    );
    final collect = AppButton(
      label: isCollected ? l10n.musicCollected : l10n.musicCollect,
      icon: LucideIcons.heart,
      variant: AppButtonVariant.ghost,
      height: mobile ? 34 : 32,
      width: mobile ? double.infinity : null,
      color: isCollected ? palette.bad : null,
      onTap: onToggleCollect,
    );

    if (mobile) {
      return Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SeedCover(seed: meta.name, size: 78, radius: AppMetrics.radiusCard),
                const SizedBox(width: 13),
                Expanded(child: info),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: play),
                const SizedBox(width: 8),
                Expanded(child: collect),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 设计稿 `.pl-hero .cover`：152 方形、r14。
          SeedCover(seed: meta.name, size: 152, radius: AppMetrics.radiusCardLg),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 14),
                Row(children: [play, const SizedBox(width: 8), collect]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 曲目表头（app.css `.thead`）。
class _TableHead extends StatelessWidget {
  const _TableHead();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final style = TextStyle(fontSize: AppFont.px10_5, letterSpacing: 1.2, color: palette.mut);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('#', textAlign: TextAlign.center, style: style),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.musicColTitle, style: style)),
          SizedBox(width: 150, child: Text(l10n.musicAlbumTag, style: style)),
          SizedBox(
            width: 46,
            child: Text(l10n.musicQualitySheetTitle, textAlign: TextAlign.center, style: style),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: Text(l10n.musicColDuration, textAlign: TextAlign.right, style: style),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 120, radius: AppMetrics.radiusCardLg),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 90, height: 12),
                    SizedBox(height: 8),
                    SkeletonBox(width: 220, height: 20),
                    SizedBox(height: 8),
                    SkeletonBox(width: 140, height: 12),
                    SizedBox(height: 16),
                    SkeletonBox(width: 180, height: 32, radius: AppMetrics.radiusButton),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(height: 34, color: palette.card.withValues(alpha: 0.5)),
        const SizedBox(height: 2),
        for (var i = 0; i < 8; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            child: Row(
              children: [
                SkeletonBox(width: 22, height: 12),
                const SizedBox(width: 8),
                Expanded(child: SkeletonBox(height: 12)),
                const SizedBox(width: 16),
                SkeletonBox(width: 120, height: 12),
                const SizedBox(width: 16),
                SkeletonBox(width: 36, height: 12),
              ],
            ),
          ),
      ],
    );
  }
}

/// 等宽数字样式（表格时长用）—— 供行内复用的口径收口。
TextStyle musicMonoStyle(AppPalette palette) =>
    TextStyle(fontSize: AppFont.px11, color: palette.mut, fontFeatures: const [FontFeature.tabularFigures()]);
