import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_player.dart';
import '../../controller/music_providers.dart';
import '../../controller/music_session.dart';
import '../../data/demo_music_repository.dart';
import '../../domain/music_models.dart';
import '../widgets/music_shared.dart';

/// 搜索浮层（N06）：全屏遮罩 + 顶部居中浮层，输入即分组返回「单曲 / 歌单」。
///
/// 空关键词 = 最近搜索 chips + 每日推荐歌台（前 4 行）；无结果给明确空态；
/// 未登录直接给说明态与登录入口（不让用户对着灰框猜原因）；
/// Esc 关闭且清空关键词（清空由键盘层负责，浮层内输入框 Esc 亦关）。
class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      ref.read(musicSearchProvider.notifier).clear();
      return;
    }
    // 防抖 200ms（N06 输入即搜）。失败弹轻提示并保留已有关键词态。
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        await ref.read(musicSearchProvider.notifier).submit(q);
      } on Object {
        if (!mounted) return;
        showAppToast(context, AppLocalizations.of(context).musicSearchFail, tone: ToastTone.bad);
      }
    });
  }

  void _close() {
    ref.read(musicSearchProvider.notifier).clear();
    ref.read(musicUiProvider.notifier).setSearch(false);
  }

  void _playSong(MusicSong song) {
    ref.read(playerProvider.notifier).playSong(song);
    showAppToast(context, AppLocalizations.of(context).musicPlayingNow(song.title), tone: ToastTone.good);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final logged = ref.watch(musicAccountProvider.select((a) => a.logged));
    final search = ref.watch(musicSearchProvider);

    // M06/M17 移动端：整屏浮层（设计稿 `.m-search{inset:0;background:var(--bg)}`），
    // 顶栏是输入框 + 取消，结果直接铺满，不使用桌面的居中弹层。
    if (context.isMobile) {
      return Material(
        color: palette.bg,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _SearchInput(
                controller: _ctrl,
                focus: _focus,
                enabled: logged,
                onSubmit: _submit,
                onClose: _close,
                mobile: true,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
                  child: _SearchBody(
                    logged: logged,
                    search: search,
                    onSubmit: _submit,
                    onChip: (chip) {
                      _ctrl.text = chip;
                      _submit(chip);
                    },
                    onPlaySong: _playSong,
                    onOpenPlaylist: (p) {
                      GoRouter.of(context).go('/music/playlist/${p.id}');
                      _close();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _close,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 52),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 640,
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 80),
              decoration: BoxDecoration(
                color: palette.panel,
                border: Border.all(color: palette.line2),
                borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
                boxShadow: [
                  BoxShadow(color: palette.shadow.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 12)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SearchInput(controller: _ctrl, focus: _focus, enabled: logged, onSubmit: _submit, onClose: _close),
                  Container(height: 1, color: palette.line),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 440),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: _SearchBody(
                          logged: logged,
                          search: search,
                          onSubmit: _submit,
                          onChip: (chip) {
                            _ctrl.text = chip;
                            _submit(chip);
                          },
                          onPlaySong: _playSong,
                          onOpenPlaylist: (p) {
                            GoRouter.of(context).go('/music/playlist/${p.id}');
                            _close();
                          },
                        ),
                      ),
                    ),
                  ),
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: palette.line)),
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _sourceHint(context),
                      style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _sourceHint(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return l10n.musicCurSourceAria(platformLabel(l10n, ref.read(musicAccountProvider).cur));
  }
}

class _SearchInput extends StatelessWidget {
  const _SearchInput({
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.onSubmit,
    required this.onClose,
    this.mobile = false,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClose;

  /// 移动端：输入框装在 38 高的圆角底上，右侧是「取消」文字（设计稿 M06 顶栏）。
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    if (mobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: palette.card,
                  border: Border.all(color: palette.line2),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusCardLg),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.search, size: 16, color: palette.mut),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focus,
                        autofocus: true,
                        enabled: enabled,
                        onSubmitted: onSubmit,
                        onChanged: onSubmit,
                        style: TextStyle(fontSize: AppFont.px14, color: palette.ink),
                        cursorColor: palette.acc,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: l10n.musicSearchHint,
                          hintStyle: TextStyle(fontSize: AppFont.px13, color: palette.mut),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 38,
                child: Center(
                  child: Text(
                    l10n.actionCancel,
                    style: TextStyle(fontSize: AppFont.px13, color: palette.accInk),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 16, color: palette.mut),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              enabled: enabled,
              // Esc 关闭且清空（浮层内输入框直接响应；全局键盘层兜底）。
              onSubmitted: onSubmit,
              onChanged: onSubmit,
              style: TextStyle(fontSize: AppFont.px14, color: palette.ink),
              cursorColor: palette.acc,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: l10n.musicSearchHint,
                hintStyle: TextStyle(fontSize: AppFont.px14, color: palette.mut),
              ),
            ),
          ),
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              border: Border.all(color: palette.line2),
              borderRadius: BorderRadius.circular(4),
              color: palette.card,
            ),
            alignment: Alignment.center,
            child: Text(
              'Esc',
              style: TextStyle(fontSize: AppFont.px9, color: palette.ink2),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onClose,
            child: Tooltip(
              message: l10n.musicSearchCloseAria,
              child: SizedBox(width: 26, height: 26, child: Icon(LucideIcons.x, size: 15, color: palette.ink2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBody extends ConsumerWidget {
  const _SearchBody({
    required this.logged,
    required this.search,
    required this.onSubmit,
    required this.onChip,
    required this.onPlaySong,
    required this.onOpenPlaylist,
  });

  final bool logged;
  final MusicSearchState search;
  final ValueChanged<String> onSubmit;

  /// 点最近搜索 chip：回填输入框并立即搜索。
  final ValueChanged<String> onChip;
  final ValueChanged<MusicSong> onPlaySong;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);

    // 未登录态（N06 边界）：说明 + 登录入口，不给灰框。
    if (!logged) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: palette.line2),
              ),
              child: Icon(LucideIcons.search, size: 26, color: palette.mut),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.musicSearchLoginTitle,
              style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.musicSearchLoginDesc,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppFont.px11_5, height: 1.6, color: palette.mut),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: l10n.musicSearchGoLogin,
              variant: AppButtonVariant.primary,
              height: 30,
              onTap: () {
                final cur = ref.read(musicAccountProvider).cur;
                ref.read(musicUiProvider.notifier).openLogin(cur);
              },
            ),
          ],
        ),
      );
    }

    final q = search.query.trim();
    // 空关键词：最近搜索 + 每日推荐歌台（前 4 行）。
    if (q.isEmpty) {
      final daily = ref.watch(dailySongsProvider).value ?? const <MusicSong>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupLabel(l10n.musicSearchRecent),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in DemoMusicRepository.recentSearches)
                  _RecentChip(label: chip, onTap: () => onChip(chip)),
              ],
            ),
          ),
          _GroupLabel(l10n.musicSearchPicks),
          for (final s in daily.take(4))
            _SearchSongRow(
              song: s,
              current: ref.watch(playerProvider).current?.id == s.id,
              onPlay: () => onPlaySong(s),
            ),
        ],
      );
    }

    // 搜索结果分组（N06）：单曲 / 歌单。
    if (search.searched && !search.hasResults) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
        child: Column(
          children: [
            Text(
              l10n.musicSearchNoResult,
              style: TextStyle(fontSize: AppFont.px13, fontWeight: FontWeight.w700, color: palette.ink),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.musicSearchNoResultHint,
              style: TextStyle(fontSize: AppFont.px11_5, color: palette.mut),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (search.songs.isNotEmpty) ...[
          _GroupLabel(l10n.musicSearchGroupSongs),
          for (final s in search.songs.take(6))
            _SearchSongRow(
              song: s,
              current: ref.watch(playerProvider).current?.id == s.id,
              onPlay: () => onPlaySong(s),
            ),
        ],
        if (search.playlists.isNotEmpty) ...[
          _GroupLabel(l10n.musicSearchGroupPlaylists),
          for (final p in search.playlists.take(4)) _SearchPlaylistRow(playlist: p, onOpen: () => onOpenPlaylist(p)),
        ],
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Text(
        text,
        style: TextStyle(fontSize: AppFont.px10, letterSpacing: 1.4, color: palette.mut, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: palette.card,
          border: Border.all(color: palette.line2),
          borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
        ),
        // 不要 alignment：Wrap 给的宽松约束 + alignment 会让每个 chip 撑成整行。
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: TextStyle(fontSize: AppFont.px10_5, color: palette.ink2),
          ),
        ),
      ),
    );
  }
}

/// 搜索结果歌曲行（紧凑 s-row 版式）：封面 32 + 曲名/歌手 + 时长。
class _SearchSongRow extends StatelessWidget {
  const _SearchSongRow({required this.song, required this.current, required this.onPlay});

  final MusicSong song;
  final bool current;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPlay,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: current ? palette.accSoft.withValues(alpha: 0.5) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
        ),
        child: Row(
          children: [
            SeedCover(seed: song.title, imageUrl: song.coverUrl, size: 32, radius: 6),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w500, color: palette.ink),
                  ),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                  ),
                ],
              ),
            ),
            Text(
              formatSongDuration(song.duration),
              style: TextStyle(
                fontSize: AppFont.px10,
                color: palette.mut,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPlaylistRow extends StatelessWidget {
  const _SearchPlaylistRow({required this.playlist, required this.onOpen});

  final MusicPlaylist playlist;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            SeedCover(seed: playlist.name, size: 32, radius: 6),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w500, color: palette.ink),
                  ),
                  Text(
                    l10n.musicCountSongs(playlist.trackCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 12, color: palette.mut),
          ],
        ),
      ),
    );
  }
}
