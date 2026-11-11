import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/toast.dart';
import '../controller/music_session.dart';
import '../domain/music_models.dart';
import 'widgets/platform_logo.dart';

/// 侧栏「音源」组（设计稿桌面侧栏：4 平台行 + 三态徽标，N04）。
///
/// 点击行为：未登录 → 拉起登录弹窗；已登录 → 切为当前源 + 轻提示；
/// 已是当前源 → 不动。渲染由壳层 [NavRail] 的 sourceGroup 槽位注入
/// （shared 层不得 import features，见 AGENTS §3）。
class SidebarSourceGroup extends ConsumerWidget {
  const SidebarSourceGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final account = ref.watch(musicAccountProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              l10n.musicSrcGroup,
              style: TextStyle(fontSize: AppFont.px8_5, color: palette.mut),
            ),
          ),
          for (final platform in MusicPlatform.values.where((p) => p != MusicPlatform.local))
            _SourceRow(
              platform: platform,
              badge: _badgeOf(account, platform, l10n),
              onTap: () => _onTap(context, ref, account, platform, l10n),
            ),
        ],
      ),
    );
  }

  String _badgeOf(MusicAccountState account, MusicPlatform p, AppLocalizations l10n) {
    if (account.cur == p) return l10n.musicBadgeCur;
    return account.isLogged(p) ? l10n.musicBadgeLogged : l10n.musicBadgeOff;
  }

  void _onTap(BuildContext context, WidgetRef ref, MusicAccountState account, MusicPlatform p, AppLocalizations l10n) {
    // 未登录优先：即使 p 已是当前源（典型：网易云未登录）也必须能拉登录，
    // 否则用户在「当前源」上点一次毫无反应，以为入口坏了。
    if (!account.isLogged(p)) {
      ref.read(musicUiProvider.notifier).openLogin(p);
      return;
    }
    if (account.cur == p) return; // 已登录且已是当前源 → 不动（N04）
    ref.read(musicAccountProvider.notifier).switchPlatform(p);
    showAppToast(context, l10n.musicSwitchSourceToast(platformBrands[p]!.label), tone: ToastTone.good);
  }
}

class _SourceRow extends StatefulWidget {
  const _SourceRow({required this.platform, required this.badge, required this.onTap});

  final MusicPlatform platform;
  final String badge;
  final VoidCallback onTap;

  @override
  State<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends State<_SourceRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final cur = widget.badge == l10n.musicBadgeCur;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.hover,
          height: 34,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hover ? palette.card : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              PlatformLogo(platform: widget.platform, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  platformBrands[widget.platform]!.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFont.px11,
                    color: cur ? palette.accInk : palette.ink2,
                    fontWeight: cur ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                widget.badge,
                style: TextStyle(fontSize: AppFont.px8_5, color: cur ? palette.acc : palette.mut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 收起态（68px）的音源指示：只留当前源 logo（N04 边界：模块入口保持原位）。
class SidebarSourceMini extends ConsumerWidget {
  const SidebarSourceMini({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(musicAccountProvider).cur;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: AppLocalizations.of(context).musicCurSourceAria(platformBrands[cur]!.label),
        child: PlatformLogo(platform: cur, size: 18),
      ),
    );
  }
}
