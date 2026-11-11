import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_session.dart';
import '../../domain/music_models.dart';
import '../widgets/platform_logo.dart';
import '../widgets/song_row.dart';

/// 账号菜单（N05）：头像 / 昵称 / 当前音源 / 四平台状态 / 退出登录。
///
/// 由 MusicScreen 顶层挂载（accountMenuOpen 时整层显示，点空白关闭）；
/// 平台行点击：未登录 → 拉起登录弹窗；已登录 → 切当前源 + 轻提示；已是当前源 → 不动。
class AccountMenuPopover extends ConsumerWidget {
  const AccountMenuPopover({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final account = ref.watch(musicAccountProvider);

    String badgeOf(MusicPlatform p) {
      if (p == account.cur) return l10n.musicBadgeCur;
      return account.isLogged(p) ? l10n.musicBadgeLogged : l10n.musicBadgeOff;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(musicUiProvider.notifier).setAccountMenu(false),
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 56, right: 16),
          child: Material(
            color: Colors.transparent,
            child: MusicPanelBox(
              width: 230,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 头像 + 昵称 + 当前音源。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: account.logged ? palette.acc : palette.hi,
                          child: Text(
                            account.logged && (account.nick?.isNotEmpty ?? false) ? account.nick!.substring(0, 1) : '?',
                            style: TextStyle(
                              fontSize: AppFont.px13,
                              fontWeight: FontWeight.w700,
                              color: account.logged ? palette.onAcc : palette.mut,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                account.logged ? (account.nick ?? '') : l10n.musicNotLogged,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppFont.px12_5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.ink,
                                ),
                              ),
                              Text(
                                l10n.musicCurSourceAria(platformBrands[account.cur]?.label ?? ''),
                                style: TextStyle(fontSize: AppFont.px10, color: palette.mut),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const MusicMenuDivider(),
                  // 四平台行。
                  for (final p in MusicPlatform.values.where((p) => p != MusicPlatform.local))
                    MusicMenuTile(
                      leading: PlatformLogo(platform: p, size: 14),
                      label: platformBrands[p]?.label ?? '',
                      sub: badgeOf(p),
                      checked: p == account.cur,
                      onTap: () => _onPlatformTap(context, ref, p),
                    ),
                  if (account.logged) ...[
                    const MusicMenuDivider(),
                    MusicMenuTile(
                      icon: LucideIcons.logOut,
                      label: l10n.musicLogout,
                      danger: true,
                      onTap: () {
                        ref.read(musicAccountProvider.notifier).logout();
                        ref.read(musicUiProvider.notifier).setAccountMenu(false);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onPlatformTap(BuildContext context, WidgetRef ref, MusicPlatform p) {
    final account = ref.read(musicAccountProvider);
    final l10n = AppLocalizations.of(context);
    if (p == account.cur) {
      // 已是当前源 → 不动（N04），只收菜单。
      ref.read(musicUiProvider.notifier).setAccountMenu(false);
      return;
    }
    if (!account.isLogged(p)) {
      // 未登录 → 拉起登录弹窗。
      ref.read(musicUiProvider.notifier).openLogin(p);
      return;
    }
    ref.read(musicAccountProvider.notifier).switchPlatform(p);
    ref.read(musicUiProvider.notifier).setAccountMenu(false);
    showAppToast(context, l10n.musicSwitchSourceToast(platformBrands[p]?.label ?? ''), tone: ToastTone.good);
  }
}
